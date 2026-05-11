# Santa Bárbara Tactical Module — Backend

Módulo de comunicaciones tácticas de artillería, prototipo v5, integrado en el sistema de estación terrena ground-station v0.4.7 para **Ares OS**.

## Estructura

```
backend/santa_barbara/
├── __init__.py          # Exporta santa_barbara_router
├── api.py               # Router FastAPI con todos los endpoints
├── auth.py              # Middleware de autenticación táctica X-API-Key
├── signal_handler.py    # Wrapper sobre el core de tracking/adquisición
├── config.py            # Clave API, identidad de estación, parámetros de log
└── README.md            # Este archivo
```

## Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET`  | `/api/v5/santa_barbara/tactical` | Visión táctica combinada (tracking + SDR) |
| `GET`  | `/api/v5/santa_barbara/status`   | Estado operativo completo de la estación |
| `GET`  | `/api/v5/santa_barbara/comms/check` | Verificación de enlace RF (simulado) |
| `POST` | `/api/v5/santa_barbara/firemission` | Solicitud de misión de fuego artillero |

Todos los endpoints requieren la cabecera `X-API-Key`.

## Autenticación

Todos los endpoints requieren la cabecera HTTP:
```
X-API-Key: SB-PROTO-v5-ARES-2026-ARTILLERIA-KEY
```
La clave se puede sobreescribir con la variable de entorno `SB_TACTICAL_API_KEY`.

## Variables de entorno

| Variable | Defecto | Descripción |
|----------|---------|-------------|
| `SB_TACTICAL_API_KEY` | `SB-PROTO-v5-...` | Clave de autenticación táctica |
| `SB_CALLSIGN` | `ALPHA-6` | Indicativo de la estación |
| `SB_UNIT` | `GRUPO-ART-61` | Unidad táctica |
| `SB_MGRS` | `30TWM1234567890` | Posición MGRS de la estación |

## Pruebas rápidas (curl)

```bash
API_KEY="SB-PROTO-v5-ARES-2026-ARTILLERIA-KEY"
BASE="http://localhost:8000/api/v5/santa_barbara"

# Estado operativo
curl -s -H "X-API-Key: $API_KEY" $BASE/status | python3 -m json.tool

# Verificación de enlace
curl -s -H "X-API-Key: $API_KEY" "$BASE/comms/check?frequency_hz=144800000" | python3 -m json.tool

# Misión de fuego
curl -s -X POST $BASE/firemission \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"target_mgrs":"30TWM1234567890","mission_type":"ADJUST_FIRE","rounds":3,"fuse":"PD"}' \
  | python3 -m json.tool
```

## Logs

Los logs rotativos se guardan en `backend/logs/santa_barbara.log` (5 ficheros × 10 MB).

```bash
tail -f backend/logs/santa_barbara.log
```
