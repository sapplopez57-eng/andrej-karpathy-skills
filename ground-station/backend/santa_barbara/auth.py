"""
Santa Bárbara Tactical Module — Authentication
Validates the X-API-Key header on every tactical endpoint.
"""

import logging
from fastapi import HTTPException, Security, status
from fastapi.security import APIKeyHeader

from .config import TACTICAL_API_KEY

logger = logging.getLogger("santa_barbara")

_API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)


async def require_tactical_auth(api_key: str = Security(_API_KEY_HEADER)) -> str:
    """FastAPI dependency that enforces X-API-Key authentication."""
    if not api_key:
        logger.warning("Tactical endpoint accessed without X-API-Key header")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing X-API-Key header",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    if api_key != TACTICAL_API_KEY:
        logger.warning("Tactical endpoint accessed with invalid API key")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid tactical API key",
        )
    return api_key
