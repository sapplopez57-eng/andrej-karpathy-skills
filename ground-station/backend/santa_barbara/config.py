"""
Santa Bárbara Tactical Module — Configuration
Prototype v5 for Ares OS artillery communications.
"""

import os
from pathlib import Path

# === TACTICAL API AUTHENTICATION ===
# Fixed prototype key — replace with HSM-backed secret in production.
TACTICAL_API_KEY: str = os.environ.get(
    "SB_TACTICAL_API_KEY",
    "SB-PROTO-v5-ARES-2026-ARTILLERIA-KEY",
)

# === STATION IDENTITY ===
STATION_CALLSIGN: str = os.environ.get("SB_CALLSIGN", "ALPHA-6")
STATION_UNIT: str = os.environ.get("SB_UNIT", "GRUPO-ART-61")
STATION_MGRS: str = os.environ.get("SB_MGRS", "30TWM1234567890")
PROTOTYPE_VERSION: str = "v5.0.0-PROTOTYPE"

# === LOGGING ===
BACKEND_DIR: Path = Path(__file__).parent.parent
LOGS_DIR: Path = BACKEND_DIR / "logs"
LOGS_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE: Path = LOGS_DIR / "santa_barbara.log"
LOG_MAX_BYTES: int = 10 * 1024 * 1024  # 10 MB
LOG_BACKUP_COUNT: int = 5

# === FIRE MISSION SIMULATION ===
# Default artillery impact radius for simulation (meters)
FIRE_MISSION_RADIUS_M: int = 50

# Supported MGRS precision levels (digits per easting/northing)
MGRS_PRECISION_DIGITS: int = 10
