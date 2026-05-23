from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import as_utc, hash_secret, utcnow
from app.db.session import get_db
from app.models import SessionToken, User

bearer = HTTPBearer(auto_error=False)


def get_current_session(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    db: Annotated[Session, Depends(get_db)],
) -> SessionToken:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    token_hash = hash_secret(credentials.credentials)
    session = db.scalar(select(SessionToken).where(SessionToken.token_hash == token_hash))
    if session is None or session.revoked_at is not None or as_utc(session.expires_at) <= utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")
    session.last_seen_at = utcnow()
    db.add(session)
    return session


def get_current_user(
    session: Annotated[SessionToken, Depends(get_current_session)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    user = db.get(User, session.user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account unavailable")
    return user
