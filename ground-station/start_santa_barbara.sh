#!/usr/bin/env bash
# =============================================================================
# start_santa_barbara.sh — Santa Bárbara Prototype v5
# Ares OS native startup script (no Docker, no containers)
# Arranque nativo para artillería táctica C4ISR
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
LOG_DIR="$BACKEND_DIR/logs"

BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"

AMBER='\033[38;5;214m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

# ---- PID tracking for cleanup ----
PIDS=()

log()   { echo -e "${AMBER}[SB]${RESET} $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()  { echo -e "${RED}[!]${RESET} $*"; }
info()  { echo -e "${CYAN}[>>]${RESET} $*"; }
sep()   { echo -e "${DIM}────────────────────────────────────────────${RESET}"; }

# =============================================================================
banner() {
    echo -e ""
    echo -e "${AMBER}${BOLD}"
    echo -e "  ███████╗ █████╗ ███╗   ██╗████████╗ █████╗ "
    echo -e "  ██╔════╝██╔══██╗████╗  ██║╚══██╔══╝██╔══██╗"
    echo -e "  ███████╗███████║██╔██╗ ██║   ██║   ███████║"
    echo -e "  ╚════██║██╔══██║██║╚██╗██║   ██║   ██╔══██║"
    echo -e "  ███████║██║  ██║██║ ╚████║   ██║   ██║  ██║"
    echo -e "  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝"
    echo -e "  ${RESET}${AMBER}  BÁRBARA — Prototipo v5 — Ares OS${RESET}"
    echo -e "  ${DIM}Artillería Táctica C4ISR — ground-station v0.4.7${RESET}"
    echo -e ""
}

# =============================================================================
# Dependency checks
# =============================================================================
check_dependency() {
    local cmd="$1"
    local pkg="$2"
    local aur="${3:-}"

    if ! command -v "$cmd" &>/dev/null; then
        warn "Dependencia faltante: '$cmd'"
        if [[ -n "$aur" ]]; then
            warn "  Instalar: yay -S $aur"
        else
            warn "  Instalar: sudo pacman -S $pkg"
        fi
        return 1
    fi
    ok "'$cmd' disponible"
    return 0
}

check_python_module() {
    local module="$1"
    local pip_pkg="${2:-$1}"
    if ! python3 -c "import $module" &>/dev/null; then
        warn "Módulo Python faltante: '$module' → pip install $pip_pkg"
        return 1
    fi
    return 0
}

run_dependency_checks() {
    sep
    log "Verificando dependencias del sistema..."
    sep
    local missing=0

    check_dependency python3   python   || ((missing++)) || true
    check_dependency node      nodejs   || ((missing++)) || true
    check_dependency npm       npm      || ((missing++)) || true
    check_dependency redis-cli redis    || ((missing++)) || true

    # GNU Radio (optional — mock used if absent)
    if command -v gnuradio-config-info &>/dev/null; then
        ok "GNU Radio disponible ($(gnuradio-config-info --version 2>/dev/null || echo 'desconocida'))"
        GNR_AVAILABLE=true
    else
        warn "GNU Radio no encontrado — se usará mock SigMF para señales RF"
        warn "  Instalar: sudo pacman -S gnuradio"
        GNR_AVAILABLE=false
    fi

    # SoapySDR (optional)
    if python3 -c "import SoapySDR" &>/dev/null 2>&1; then
        ok "SoapySDR Python disponible"
    else
        warn "SoapySDR Python no encontrado — sin soporte SDR en tiempo real"
        warn "  Instalar: sudo pacman -S soapysdr && pip install SoapySDR"
    fi

    # Key Python dependencies
    for mod_pkg in "fastapi:fastapi" "uvicorn:uvicorn" "skyfield:skyfield" "numpy:numpy" "sqlalchemy:sqlalchemy"; do
        mod="${mod_pkg%%:*}"
        pkg="${mod_pkg##*:}"
        check_python_module "$mod" "$pkg" || ((missing++)) || true
    done

    if (( missing > 0 )); then
        warn "${missing} dependencias faltantes. El sistema puede no funcionar correctamente."
        warn "Ver DEPENDENCIAS_ARES.md para guía completa de instalación."
        sep
        read -rp "¿Continuar de todas formas? [s/N] " ans
        if [[ "${ans,,}" != "s" ]]; then
            log "Abortado por el usuario."
            exit 1
        fi
    else
        ok "Todas las dependencias principales verificadas."
    fi
    sep
}

# =============================================================================
# SDR detection
# =============================================================================
detect_sdr() {
    log "Detectando hardware SDR..."
    SDR_DETECTED=false
    SDR_TYPE="none"

    # RTL-SDR
    if command -v rtl_test &>/dev/null; then
        if rtl_test -t 2>&1 | grep -q "Found.*device" 2>/dev/null; then
            ok "RTL-SDR detectado"
            SDR_DETECTED=true
            SDR_TYPE="rtlsdr"
            return
        fi
    fi

    # HackRF
    if command -v hackrf_info &>/dev/null; then
        if hackrf_info 2>&1 | grep -q "HackRF" 2>/dev/null; then
            ok "HackRF detectado"
            SDR_DETECTED=true
            SDR_TYPE="hackrf"
            return
        fi
    fi

    # SoapySDR generic probe
    if python3 -c "import SoapySDR; devs=SoapySDR.Device.enumerate(); print(len(devs))" 2>/dev/null | grep -qv "^0$"; then
        ok "Dispositivo SoapySDR detectado"
        SDR_DETECTED=true
        SDR_TYPE="soapy"
        return
    fi

    warn "No se detectó SDR hardware — usando mock SigMF (señal simulada)"
    SDR_TYPE="mock"
}

# =============================================================================
# Redis
# =============================================================================
start_redis() {
    log "Comprobando Redis..."
    if redis-cli ping &>/dev/null 2>&1; then
        ok "Redis ya está corriendo"
    else
        info "Iniciando Redis..."
        redis-server --daemonize yes --logfile "$LOG_DIR/redis.log" \
            --loglevel warning 2>/dev/null || {
            warn "No se pudo iniciar Redis con redis-server --daemonize"
            warn "  Intentar: sudo systemctl start redis"
            warn "  Instalar: sudo pacman -S redis"
        }
        sleep 1
        if redis-cli ping &>/dev/null 2>&1; then
            ok "Redis iniciado"
        else
            warn "Redis no disponible — algunas funciones pueden fallar"
        fi
    fi
}

# =============================================================================
# Backend (FastAPI + uvicorn)
# =============================================================================
start_backend() {
    log "Iniciando backend FastAPI en http://${BACKEND_HOST}:${BACKEND_PORT}..."
    mkdir -p "$LOG_DIR"

    if ! [[ -f "$BACKEND_DIR/app.py" ]]; then
        warn "No se encontró backend/app.py — verifica la ruta del proyecto"
        return 1
    fi

    # Activate virtualenv if present
    if [[ -f "$BACKEND_DIR/.venv/bin/activate" ]]; then
        # shellcheck disable=SC1091
        source "$BACKEND_DIR/.venv/bin/activate"
        ok "Virtualenv activado: $BACKEND_DIR/.venv"
    elif [[ -f "$SCRIPT_DIR/.venv/bin/activate" ]]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/.venv/bin/activate"
        ok "Virtualenv activado: $SCRIPT_DIR/.venv"
    fi

    PYTHONPATH="$BACKEND_DIR" python3 "$BACKEND_DIR/app.py" \
        --host "$BACKEND_HOST" \
        --port "$BACKEND_PORT" \
        --temp-db \
        >"$LOG_DIR/backend.log" 2>&1 &

    local backend_pid=$!
    PIDS+=("$backend_pid")
    info "Backend PID: $backend_pid"

    # Wait for backend to come up
    local retries=0
    while (( retries < 20 )); do
        if curl -sf "http://${BACKEND_HOST}:${BACKEND_PORT}/api/version" >/dev/null 2>&1; then
            ok "Backend activo en http://${BACKEND_HOST}:${BACKEND_PORT}"
            return 0
        fi
        sleep 1
        ((retries++))
    done
    warn "Backend tardó demasiado en responder. Ver logs: $LOG_DIR/backend.log"
    return 1
}

# =============================================================================
# Frontend (React + Vite)
# =============================================================================
start_frontend() {
    log "Iniciando frontend React en http://localhost:${FRONTEND_PORT}..."

    if ! [[ -f "$FRONTEND_DIR/package.json" ]]; then
        warn "No se encontró frontend/package.json"
        return 1
    fi

    if ! [[ -d "$FRONTEND_DIR/node_modules" ]]; then
        info "Instalando dependencias Node.js (primera vez)..."
        (cd "$FRONTEND_DIR" && npm install --silent) || {
            warn "npm install falló. Ver errores arriba."
            return 1
        }
    fi

    (cd "$FRONTEND_DIR" && \
        VITE_BACKEND_URL="http://${BACKEND_HOST}:${BACKEND_PORT}" \
        npm run dev -- --port "$FRONTEND_PORT" --host 0.0.0.0 \
        >"$LOG_DIR/frontend.log" 2>&1) &

    local frontend_pid=$!
    PIDS+=("$frontend_pid")
    info "Frontend PID: $frontend_pid"

    sleep 3
    if kill -0 "$frontend_pid" 2>/dev/null; then
        ok "Frontend activo en http://localhost:${FRONTEND_PORT}"
    else
        warn "Frontend no pudo arrancar. Ver logs: $LOG_DIR/frontend.log"
    fi
}

# =============================================================================
# GNU Radio mock worker
# =============================================================================
start_mock_signal() {
    if [[ "$SDR_DETECTED" == "true" ]]; then
        log "SDR real detectado ($SDR_TYPE) — sin necesidad de mock"
        return
    fi

    log "Iniciando mock de señal SigMF (sin SDR real)..."

    # Check for sample SigMF files in data directory
    local sigmf_file
    sigmf_file=$(find "$BACKEND_DIR/data" -name "*.sigmf-meta" 2>/dev/null | head -1)

    if [[ -n "$sigmf_file" ]]; then
        ok "Mock SigMF: $sigmf_file"
    else
        info "Generando señal mock con Python (tono FM simple)..."
        python3 - <<'PYEOF' >"$LOG_DIR/mock_signal.log" 2>&1 &
import numpy as np, time, sys
print("Santa Barbara mock signal generator running...")
# Simulate 100 MHz FM signal parameters for testing
fs = 2.048e6
fc = 100e6
t = np.linspace(0, 1, int(fs), endpoint=False)
iq = np.exp(1j * 2 * np.pi * 1000 * t).astype(np.complex64)
print(f"Mock IQ generated: {len(iq)} samples at {fs/1e6} MHz")
# In a real integration, this would feed into iq_queue_fft
while True:
    time.sleep(5)
    print("Mock signal heartbeat OK")
    sys.stdout.flush()
PYEOF
        PIDS+=($!)
        info "Mock signal generator PID: ${PIDS[-1]}"
    fi
}

# =============================================================================
# Cleanup on exit
# =============================================================================
cleanup() {
    echo ""
    log "Cerrando Santa Bárbara..."
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            info "Proceso $pid terminado"
        fi
    done
    ok "Sistema cerrado. ¡Fuego suspendido!"
    exit 0
}

trap cleanup INT TERM EXIT

# =============================================================================
# MAIN
# =============================================================================
banner
run_dependency_checks
start_redis
detect_sdr
start_backend
start_frontend
start_mock_signal

sep
echo -e ""
echo -e "${AMBER}${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
echo -e "${AMBER}${BOLD}  ║   SANTA BÁRBARA — SISTEMA OPERATIVO     ║${RESET}"
echo -e "${AMBER}${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
echo -e "${AMBER}  ║  Backend API:  http://${BACKEND_HOST}:${BACKEND_PORT}         ║${RESET}"
echo -e "${AMBER}  ║  Frontend UI:  http://localhost:${FRONTEND_PORT}          ║${RESET}"
echo -e "${AMBER}  ║  API Key:      SB-PROTO-v5-ARES-2026-...  ║${RESET}"
echo -e "${AMBER}  ║  HUD Mode:     Ctrl+Shift+T               ║${RESET}"
echo -e "${AMBER}  ║  Logs:         backend/logs/              ║${RESET}"
echo -e "${AMBER}${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
echo -e ""
log "Santa Bárbara activa. Ctrl+C para cerrar el sistema."
sep

# Keep script alive, tail backend log for live feedback
tail -f "$LOG_DIR/backend.log" 2>/dev/null || wait
