"""
Santa Bárbara Tactical Module — API Router
FastAPI router at prefix /api/v5/santa_barbara
All endpoints require X-API-Key tactical authentication.
"""

import logging
import logging.handlers
import re
import time
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, field_validator

from .auth import require_tactical_auth
from .config import (
    LOG_BACKUP_COUNT,
    LOG_FILE,
    LOG_MAX_BYTES,
    MGRS_PRECISION_DIGITS,
    PROTOTYPE_VERSION,
    STATION_CALLSIGN,
    STATION_MGRS,
    STATION_UNIT,
)
from .signal_handler import check_rf_link, get_station_operational_status

# ---------------------------------------------------------------------------
# Logger — rotating file handler, 5 × 10 MB
# ---------------------------------------------------------------------------
logger = logging.getLogger("santa_barbara")
logger.setLevel(logging.INFO)

if not any(isinstance(h, logging.handlers.RotatingFileHandler) for h in logger.handlers):
    _fh = logging.handlers.RotatingFileHandler(
        LOG_FILE,
        maxBytes=LOG_MAX_BYTES,
        backupCount=LOG_BACKUP_COUNT,
        encoding="utf-8",
    )
    _fh.setFormatter(
        logging.Formatter(
            "[%(asctime)s] %(levelname)-8s [%(name)s] %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    )
    logger.addHandler(_fh)

# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------
router = APIRouter(
    prefix="/api/v5/santa_barbara",
    tags=["Santa Bárbara — Tactical"],
    dependencies=[Depends(require_tactical_auth)],
)

# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------
_MGRS_RE = re.compile(
    r"^[0-9]{1,2}[C-X][A-HJ-NP-Z]{2}[0-9]{4,10}$", re.IGNORECASE
)


class FireMissionRequest(BaseModel):
    target_mgrs: str
    mission_type: str = "ADJUST_FIRE"
    rounds: int = 3
    fuse: str = "PD"
    requesting_unit: Optional[str] = None

    @field_validator("target_mgrs")
    @classmethod
    def validate_mgrs(cls, v: str) -> str:
        v = v.replace(" ", "").upper()
        if not _MGRS_RE.match(v):
            raise ValueError(
                f"Invalid MGRS coordinate '{v}'. "
                "Expected format: <zone><band><sq><easting><northing> e.g. 30TWM1234567890"
            )
        return v

    @field_validator("rounds")
    @classmethod
    def validate_rounds(cls, v: int) -> int:
        if not 1 <= v <= 100:
            raise ValueError("rounds must be between 1 and 100")
        return v

    @field_validator("mission_type")
    @classmethod
    def validate_mission_type(cls, v: str) -> str:
        allowed = {"ADJUST_FIRE", "FIRE_FOR_EFFECT", "SUPPRESS", "SMOKE", "ILLUM"}
        v = v.upper()
        if v not in allowed:
            raise ValueError(f"mission_type must be one of {allowed}")
        return v


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/tactical", summary="Redirects to core tracking + acquisition status")
async def tactical_overview(api_key: str = Depends(require_tactical_auth)) -> Dict[str, Any]:
    """
    Main tactical endpoint. Queries the ground-station core for tracking and
    acquisition state and returns a combined tactical picture.
    """
    logger.info(f"[TACTICAL] Overview requested from key={api_key[:8]}***")
    core_status = get_station_operational_status()
    return {
        "system": "Santa Bárbara",
        "version": PROTOTYPE_VERSION,
        "callsign": STATION_CALLSIGN,
        "unit": STATION_UNIT,
        "mgrs": STATION_MGRS,
        "timestamp": time.time(),
        "core": core_status,
    }


@router.get("/status", summary="Operational status of the ground station")
async def station_status(api_key: str = Depends(require_tactical_auth)) -> Dict[str, Any]:
    """Returns full operational status including SDR, tracking, and pipeline health."""
    logger.info("[STATUS] Station status queried")
    core = get_station_operational_status()
    return {
        "callsign": STATION_CALLSIGN,
        "unit": STATION_UNIT,
        "version": PROTOTYPE_VERSION,
        "timestamp": core["timestamp"],
        "operational": True,
        "mode": core["mode"],
        "sdr": core["sdr"],
        "tracking": core["tracking"],
        "pipeline": core["pipeline"],
        "logs": str(LOG_FILE),
    }


@router.get("/comms/check", summary="RF communications link verification")
async def comms_check(
    frequency_hz: Optional[float] = Query(None, description="Frequency to check in Hz"),
    api_key: str = Depends(require_tactical_auth),
) -> Dict[str, Any]:
    """
    Performs (simulated) RF link quality check.
    Reports estimated SNR, latency, and BER on the tactical net.
    """
    logger.info(f"[COMMS] Link check at {frequency_hz or 'default'} Hz")
    result = check_rf_link(frequency_hz)
    return {
        "callsign": STATION_CALLSIGN,
        "comms_check": result,
    }


@router.post("/firemission", status_code=status.HTTP_200_OK, summary="Artillery fire mission request")
async def fire_mission(
    request: FireMissionRequest,
    api_key: str = Depends(require_tactical_auth),
) -> Dict[str, Any]:
    """
    Simulates an artillery fire mission request (STANAG 2934 / FM 3-09 format).
    Validates the target MGRS coordinate and returns a structured fire mission JSON.
    In a live BMS integration this would be forwarded to the C2 fire control system.
    """
    logger.info(
        f"[FIREMISSION] type={request.mission_type} target={request.target_mgrs} "
        f"rounds={request.rounds} unit={request.requesting_unit or STATION_UNIT}"
    )

    mission_id = f"SB-{int(time.time())}-{request.mission_type[:3]}"

    return {
        "mission_id": mission_id,
        "status": "TRANSMITTED",
        "timestamp": time.time(),
        "requesting_unit": request.requesting_unit or STATION_UNIT,
        "fire_mission": {
            "type": request.mission_type,
            "target": {
                "mgrs": request.target_mgrs,
                "precision_m": 10 ** (MGRS_PRECISION_DIGITS - len(request.target_mgrs.split()[0] if ' ' in request.target_mgrs else request.target_mgrs[5:]) // 2 + 1) if len(request.target_mgrs) > 5 else 100,
            },
            "ammunition": {
                "rounds": request.rounds,
                "fuse": request.fuse,
            },
            "authentication": {
                "method": "X-API-Key",
                "station": STATION_CALLSIGN,
            },
        },
        "note": "PROTOTYPE — simulation only, no live fire control integration",
    }
