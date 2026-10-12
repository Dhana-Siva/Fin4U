"""Sign-in with Splitwise (OAuth 2.0 authorization code flow).

Why this lives on the server: Splitwise requires a client *secret* to turn the
sign-in code into a token, and a secret can't be shipped inside an iPhone app.
So the server does that one step -- and then forgets the token. It is held in
memory for two minutes under a random one-time "handoff" code so the app can
collect it, and is never written to disk or logged. After that the app talks
to Splitwise directly with the token, which lives only in the iPhone's Keychain.

Flow:
  1. App opens   GET  /splitwise/authorize?state=...   in a system web sheet.
  2. We redirect to Splitwise's sign-in/consent page.
  3. Splitwise redirects to  GET /splitwise/callback?code=...&state=...
  4. We swap the code for a token, park it under a handoff code, and redirect
     to  fin4u://splitwise?handoff=...&state=...  (only the app gets this).
  5. App calls  POST /splitwise/token  (with the app key) once to collect it.
"""
import logging
import os
import re
import secrets
import threading
import time
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Header, HTTPException, Query
from fastapi.responses import RedirectResponse
from pydantic import BaseModel

from security import require_app_key

log = logging.getLogger("receipt-backend")

AUTHORIZE_URL = os.environ.get("SPLITWISE_AUTHORIZE_URL", "https://www.splitwise.com/oauth/authorize")
TOKEN_URL = os.environ.get("SPLITWISE_TOKEN_URL", "https://www.splitwise.com/oauth/token")
APP_SCHEME_URL = "fin4u://splitwise"

HANDOFF_TTL_SECONDS = 120
MAX_PENDING = 1000
_STATE_RE = re.compile(r"^[A-Za-z0-9_-]{16,128}$")

router = APIRouter(prefix="/splitwise")

_pending: dict[str, tuple[str, float]] = {}  # handoff code -> (token, expires_at)
_lock = threading.Lock()


class TokenRequest(BaseModel):
    handoff: str


class TokenResponse(BaseModel):
    access_token: str


def _credentials() -> tuple[str, str]:
    client_id = os.environ.get("SPLITWISE_CLIENT_ID")
    client_secret = os.environ.get("SPLITWISE_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise HTTPException(status_code=503, detail="Splitwise isn't set up on this server.")
    return client_id, client_secret


def _callback_url() -> str:
    base = os.environ.get("PUBLIC_BASE_URL")
    if not base and os.environ.get("RAILWAY_PUBLIC_DOMAIN"):
        base = "https://" + os.environ["RAILWAY_PUBLIC_DOMAIN"]
    if not base:
        raise HTTPException(status_code=503, detail="Splitwise isn't set up on this server.")
    return base.rstrip("/") + "/splitwise/callback"


def exchange_code(code: str) -> str:
    """Swaps a sign-in code for an access token. Raises on any failure."""
    client_id, client_secret = _credentials()
    response = httpx.post(
        TOKEN_URL,
        data={
            "client_id": client_id,
            "client_secret": client_secret,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": _callback_url(),
        },
        timeout=20,
    )
    response.raise_for_status()
    token = response.json().get("access_token")
    if not token:
        raise ValueError("no access_token in response")
    return token


def _app_redirect(**params: str) -> RedirectResponse:
    return RedirectResponse(APP_SCHEME_URL + "?" + urlencode(params), status_code=302)


def _purge_expired(now: float) -> None:
    for key in [k for k, (_, expires) in _pending.items() if expires <= now]:
        del _pending[key]


@router.get("/authorize")
def authorize(state: str = Query(...)) -> RedirectResponse:
    if not _STATE_RE.match(state):
        raise HTTPException(status_code=400, detail="Bad request.")
    client_id, _ = _credentials()
    query = urlencode({
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": _callback_url(),
        "state": state,
    })
    return RedirectResponse(f"{AUTHORIZE_URL}?{query}", status_code=302)


@router.get("/callback")
def callback(
    state: str = Query(default=""),
    code: str | None = Query(default=None),
    error: str | None = Query(default=None),
) -> RedirectResponse:
    safe_state = state if _STATE_RE.match(state) else ""
    if error or not code:
        return _app_redirect(error="access_denied", state=safe_state)
    try:
        token = exchange_code(code)
    except HTTPException:
        return _app_redirect(error="not_configured", state=safe_state)
    except Exception as exc:  # network error, bad response, rejected code
        # Class name only: the message could echo the code or secret.
        log.error("Splitwise token exchange failed (%s)", type(exc).__name__)
        return _app_redirect(error="exchange_failed", state=safe_state)

    handoff = secrets.token_urlsafe(32)
    now = time.time()
    with _lock:
        _purge_expired(now)
        if len(_pending) >= MAX_PENDING:
            return _app_redirect(error="busy", state=safe_state)
        _pending[handoff] = (token, now + HANDOFF_TTL_SECONDS)
    return _app_redirect(handoff=handoff, state=safe_state)


@router.post("/token", response_model=TokenResponse)
def collect_token(body: TokenRequest, x_app_key: str | None = Header(default=None)) -> TokenResponse:
    require_app_key(x_app_key)
    now = time.time()
    with _lock:
        _purge_expired(now)
        entry = _pending.pop(body.handoff, None)  # single use
    if entry is None:
        raise HTTPException(status_code=404, detail="That sign-in has expired. Try again.")
    return TokenResponse(access_token=entry[0])
