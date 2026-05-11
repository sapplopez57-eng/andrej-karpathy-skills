"""
Santa Bárbara Tactical Module — Signal Handler
Wrapper around the ground-station core tracking and acquisition functions.
Provides tactical-layer status aggregation without coupling to internal state.
"""

import logging
import time
from typing import Any, Dict, Optional

logger = logging.getLogger("santa_barbara")


def get_station_operational_status() -> Dict[str, Any]:
    """
    Aggregate operational status from the ground-station runtime.
    Gracefully degrades if the core is not running (prototype mode).
    """
    status: Dict[str, Any] = {
        "timestamp": time.time(),
        "mode": "PROTOTYPE",
        "sdr": _probe_sdr_status(),
        "tracking": _probe_tracking_status(),
        "pipeline": _probe_pipeline_status(),
    }
    return status


def _probe_sdr_status() -> Dict[str, Any]:
    """Query the core process manager for active SDR sessions."""
    try:
        from server.runtimestate import process_manager  # type: ignore

        if process_manager is None:
            return {"active": False, "sessions": 0, "reason": "process_manager_uninitialized"}

        sessions = getattr(process_manager, "active_sessions", {})
        session_count = len(sessions) if isinstance(sessions, dict) else 0
        return {
            "active": session_count > 0,
            "sessions": session_count,
            "hardware": "detected" if session_count > 0 else "none",
        }
    except Exception as exc:
        logger.debug(f"SDR probe failed (prototype mode): {exc}")
        return {"active": False, "sessions": 0, "hardware": "mock", "reason": str(exc)}


def _probe_tracking_status() -> Dict[str, Any]:
    """Query the tracker instances for active satellite tracking."""
    try:
        from tracker.instances import get_tracker_instances  # type: ignore

        instances = get_tracker_instances()
        active = [i for i in (instances or []) if getattr(i, "running", False)]
        return {
            "active_trackers": len(active),
            "targets": [getattr(i, "satellite_name", "unknown") for i in active],
        }
    except Exception as exc:
        logger.debug(f"Tracker probe failed (prototype mode): {exc}")
        return {"active_trackers": 0, "targets": [], "reason": str(exc)}


def _probe_pipeline_status() -> Dict[str, Any]:
    """Check if the processing pipeline (FFT + demod) is running."""
    try:
        from server.runtimestate import process_manager  # type: ignore

        if process_manager is None:
            return {"running": False}

        processes = getattr(process_manager, "_processes", {})
        running_count = sum(
            1 for p in processes.values() if getattr(p, "is_alive", lambda: False)()
        )
        return {"running": running_count > 0, "active_processes": running_count}
    except Exception as exc:
        logger.debug(f"Pipeline probe failed (prototype mode): {exc}")
        return {"running": False, "reason": str(exc)}


def check_rf_link(frequency_hz: Optional[float] = None) -> Dict[str, Any]:
    """
    Simulate an RF link verification check.
    In a real system this would send a test tone and measure SNR.
    """
    return {
        "timestamp": time.time(),
        "link_status": "SIMULATED",
        "frequency_hz": frequency_hz or 144_800_000,
        "estimated_snr_db": 12.5,
        "latency_ms": 8,
        "bit_error_rate": 0.0001,
        "note": "Simulated link check — no live RF verification in prototype mode",
    }
