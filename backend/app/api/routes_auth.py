import time

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.api.deps import current_staff
from app.api.schemas import LoginIn
from app.core.security import create_token, hash_password, verify_password
from app.database import models
from app.database.session import get_db

router = APIRouter(prefix="/auth", tags=["auth"])

# very small brute-force guard: max 5 failed logins per 5 minutes per username+IP
_failures: dict[str, list[float]] = {}
_DUMMY_HASH = hash_password("not-a-real-password")


def _recent_failures(key: str) -> list[float]:
    cutoff = time.time() - 300
    _failures[key] = [t for t in _failures.get(key, []) if t > cutoff]
    return _failures[key]


@router.post("/login")
def login(body: LoginIn, request: Request, db: Session = Depends(get_db)):
    key = f"{body.username.lower()}|{request.client.host if request.client else '?'}"
    if len(_recent_failures(key)) >= 5:
        raise HTTPException(429, "Too many attempts. Try again in a few minutes.")

    user = db.query(models.StaffUser).filter_by(username=body.username).first()
    ok = verify_password(body.password, user.password_hash if user else _DUMMY_HASH)
    if not (user and ok):
        _recent_failures(key).append(time.time())
        raise HTTPException(401, "Wrong username or password")

    _failures.pop(key, None)
    return {"token": create_token(user.username), "username": user.username}


@router.get("/me")
def me(user: models.StaffUser = Depends(current_staff)):
    return {"username": user.username}