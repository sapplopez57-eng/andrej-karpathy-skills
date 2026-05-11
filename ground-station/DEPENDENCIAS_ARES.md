# DEPENDENCIAS_ARES.md — Santa Bárbara en Ares OS

Guía completa de instalación de dependencias para ejecutar Santa Bárbara de forma nativa en **Ares OS** (distribución basada en Garuda/Arch Linux).

---

## 1. Paquetes de Sistema (pacman)

```bash
sudo pacman -S --needed \
    python \
    python-pip \
    python-virtualenv \
    nodejs \
    npm \
    redis \
    git \
    base-devel \
    cmake \
    pkgconf \
    fftw \
    libusb \
    soapysdr \
    python-soapysdr
```

### GNU Radio (opcional — requerido para señal RF real)

```bash
sudo pacman -S --needed gnuradio gnuradio-companion
```

### RTL-SDR (para dongles RTL-SDR)

```bash
sudo pacman -S --needed rtl-sdr
# Regla udev para acceso sin root:
sudo bash -c 'echo "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"0bda\", MODE=\"0666\", GROUP=\"plugdev\"" > /etc/udev/rules.d/99-rtlsdr.rules'
sudo udevadm control --reload-rules
sudo usermod -aG plugdev $USER
```

### HackRF (para HackRF One)

```bash
sudo pacman -S --needed hackrf
# o desde AUR:
yay -S hackrf-git
```

### USRP (para dispositivos Ettus/USRP)

```bash
yay -S uhd-git python-uhd
```

---

## 2. Dependencias Python (pip)

Instalar en virtualenv recomendado:

```bash
cd ground-station/backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Paquetes adicionales para Santa Bárbara

```bash
pip install \
    fastapi>=0.135.0 \
    uvicorn>=0.34.0 \
    python-socketio>=5.16.0 \
    skyfield>=1.53 \
    numpy>=2.0.0 \
    scipy>=1.15.0 \
    sqlalchemy>=2.0.0 \
    aiosqlite>=0.21.0 \
    alembic>=1.14.0 \
    google-genai>=1.60.0 \
    sounddevice>=0.5.0 \
    psutil>=7.0.0 \
    pydantic>=2.10.0 \
    colorlog>=6.9.0 \
    apscheduler>=3.10.0 \
    requests>=2.33.0
```

### Tabla completa de módulos Python

| Paquete | Versión mínima | Rol |
|---------|---------------|-----|
| `fastapi` | 0.135 | API REST principal y Santa Bárbara |
| `uvicorn` | 0.34 | Servidor ASGI HTTP/WebSocket |
| `python-socketio` | 5.16 | Comunicación en tiempo real frontend |
| `skyfield` | 1.53 | Propagación TLE, cálculo Doppler |
| `numpy` | 2.0 | Procesado de señal IQ, FFT |
| `scipy` | 1.15 | Filtros digitales, demodulación |
| `SoapySDR` | sistema | Abstracción hardware SDR |
| `sqlalchemy` | 2.0 | ORM base de datos |
| `aiosqlite` | 0.21 | SQLite async |
| `alembic` | 1.14 | Migraciones de BD |
| `google-genai` | 1.60 | Gemini Live API (transcripción SIGINT) |
| `sounddevice` | 0.5 | Captura audio micrófono |
| `psutil` | 7.0 | Monitorización de procesos y CPU |
| `pydantic` | 2.10 | Validación de modelos (API) |
| `apscheduler` | 3.10 | Scheduler de observaciones |
| `webrtcvad-wheels` | 2.0 | Detección de actividad de voz |

---

## 3. Dependencias Node.js (frontend)

```bash
cd ground-station/frontend
npm install
```

### Paquetes principales

| Paquete | Versión | Rol |
|---------|---------|-----|
| `react` | 18+ | Framework UI |
| `react-dom` | 18+ | Renderizado DOM |
| `react-router` | 7+ | Enrutamiento SPA |
| `@mui/material` | 6+ | Componentes Material UI |
| `@toolpad/core` | latest | Shell MUI con navegación |
| `@reduxjs/toolkit` | 2+ | Estado global Redux |
| `redux-persist` | 6+ | Persistencia de estado |
| `socket.io-client` | 4+ | WebSocket con backend |
| `vite` | 6+ | Bundler/dev server |
| `hugeicons-react` | latest | Iconos satelitales |

---

## 4. Servicios del Sistema

### Redis (broker de mensajería)

```bash
# Iniciar con systemd
sudo systemctl enable --now redis

# O manualmente para pruebas
redis-server --daemonize yes
```

### Verificar Redis
```bash
redis-cli ping   # debe responder: PONG
```

---

## 5. Variables de Entorno

Crear archivo `.env` en la raíz del proyecto (opcional, el script detecta valores por defecto):

```bash
# Santa Bárbara — .env
SB_TACTICAL_API_KEY="SB-PROTO-v5-ARES-2026-ARTILLERIA-KEY"
SB_CALLSIGN="ALPHA-6"
SB_UNIT="GRUPO-ART-61"
SB_MGRS="30TWM1234567890"

BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8000"
FRONTEND_PORT="3000"

# Gemini (para SIGINT SIGINT)
# Guardar la API key en el navegador vía: localStorage.setItem('gemini_api_key', 'TU_KEY')
```

---

## 6. Configuración Udev para SDR sin Root

```bash
# Crear regla para RTL-SDR + HackRF + LimeSDR
sudo tee /etc/udev/rules.d/99-sdr-tactical.rules <<'EOF'
# RTL-SDR
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", MODE="0666", GROUP="plugdev"
# HackRF
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="6089", MODE="0666", GROUP="plugdev"
# LimeSDR
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="6108", MODE="0666", GROUP="plugdev"
EOF
sudo udevadm control --reload-rules
sudo usermod -aG plugdev $USER
# Relogar para que aplique el grupo
```

---

## 7. Verificación Rápida Post-instalación

```bash
# Verificar Python y módulos clave
python3 -c "import fastapi, uvicorn, skyfield, numpy; print('Backend OK')"

# Verificar Node.js
node -v && npm -v

# Verificar Redis
redis-cli ping

# Verificar SoapySDR (si hay SDR conectado)
python3 -c "import SoapySDR; print(SoapySDR.Device.enumerate())"

# Iniciar todo el sistema
./start_santa_barbara.sh
```

---

*Ares OS — Santa Bárbara Prototipo v5 — 2026*
