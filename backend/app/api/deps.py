from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.security import decode_token
from app.database import models
from app.database.session import get_db

bearer = HTTPBearer(auto_error=False)


def current_staff(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> models.StaffUser:
    """Use as a dependency on any route that only staff may call."""
    headers = {"WWW-Authenticate": "Bearer"}
    if creds is None:
        raise HTTPException(401, "Please sign in", headers=headers)
    data = decode_token(creds.credentials)
    if not data:
        raise HTTPException(401, "Session expired, please sign in again", headers=headers)
    user = db.query(models.StaffUser).filter_by(username=data["sub"]).first()
    if not user:
        raise HTTPException(401, "Unknown user", headers=headers)
    return user