"""Shared check for the app key header (see app.py for why it's deterrence only)."""
import hmac
import os

from fastapi import HTTPException


def require_app_key(x_app_key: str | None) -> None:
    # Fails closed: no configured key means nothing is served.
    expected_key = os.environ.get("APP_API_KEY")
    if not expected_key:
        raise HTTPException(status_code=503, detail="Server is not configured.")
    if not x_app_key or not hmac.compare_digest(x_app_key, expected_key):
        raise HTTPException(status_code=401, detail="Unauthorized.")
