"""Password hashing and signed tokens, standard library only (no extra packages)."""
import base64
import hashlib
import hmac
import json
import os
import time

from app.core import config

_ITERATIONS = 200_000


# ---------- passwords ----------
def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _ITERATIONS)
    return f"pbkdf2${_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, iterations, salt_hex, hash_hex = stored.split("$")
        if scheme != "pbkdf2":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt_hex), int(iterations)
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(digest.hex(), hash_hex)


# ---------- signed tokens ----------
def _b64e(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _b64d(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _sign(data: bytes) -> str:
    return _b64e(hmac.new(config.SECRET_KEY.encode(), data, hashlib.sha256).digest())


def create_token(username: str, ttl_seconds: int | None = None) -> str:
    ttl = ttl_seconds if ttl_seconds is not None else config.TOKEN_TTL_HOURS * 3600
    body = {"sub": username, "role": "staff", "exp": int(time.time()) + ttl}
    payload = _b64e(json.dumps(body, separators=(",", ":")).encode())
    return f"{payload}.{_sign(payload.encode())}"


def decode_token(token: str) -> dict | None:
    try:
        payload, signature = token.split(".")
        if not hmac.compare_digest(signature, _sign(payload.encode())):
            return None
        data = json.loads(_b64d(payload))
        if data.get("exp", 0) < time.time():
            return None
        return data
    except (ValueError, TypeError):
        return None


# ---------- per-ticket secret (lets a customer cancel only their own ticket) ----------
def ticket_key(ticket_id: int) -> str:
    mac = hmac.new(config.SECRET_KEY.encode(), f"ticket:{ticket_id}".encode(), hashlib.sha256)
    return mac.hexdigest()[:20]


def check_ticket_key(ticket_id: int, key: str) -> bool:
    return hmac.compare_digest(ticket_key(ticket_id), key or "")