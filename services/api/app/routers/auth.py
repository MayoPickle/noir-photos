import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import generate_otp, hash_secret, seconds_from_now
from app.db.session import get_db
from app.models import EmailOtp, User
from app.presenters import user_out
from app.schemas import AuthLoginVerifyIn, AuthOut, AuthRegisterIn, OtpStartIn, OtpStartOut
from app.services import add_sync_event, consume_otp, create_session, normalize_email

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/otp/start", response_model=OtpStartOut)
def start_otp(payload: OtpStartIn, db: Session = Depends(get_db)) -> OtpStartOut:
    settings = get_settings()
    email = normalize_email(payload.email)
    existing_user = db.scalar(select(User).where(User.email == email, User.deleted_at.is_(None)))

    if payload.purpose == "register" and existing_user is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Account already exists")
    if payload.purpose in {"login", "recovery"} and existing_user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")

    code = generate_otp()
    db.add(
        EmailOtp(
            email=email,
            purpose=payload.purpose,
            otp_hash=hash_secret(code),
            expires_at=seconds_from_now(settings.otp_ttl_seconds),
        )
    )
    db.commit()

    logger.warning("Noir Photos development OTP email=%s purpose=%s code=%s", email, payload.purpose, code)
    return OtpStartOut(
        status="sent",
        delivery="development-log",
        expires_in_seconds=settings.otp_ttl_seconds,
    )


@router.post("/register", response_model=AuthOut, status_code=status.HTTP_201_CREATED)
def register(payload: AuthRegisterIn, db: Session = Depends(get_db)) -> AuthOut:
    email = normalize_email(payload.email)
    if not consume_otp(db, email, "register", payload.otp):
        db.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired OTP")
    if db.scalar(select(User).where(User.email == email, User.deleted_at.is_(None))) is not None:
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Account already exists")

    user = User(email=email, public_key=payload.public_key, key_bundle=payload.key_bundle)
    db.add(user)
    db.flush()
    token, _ = create_session(db, user, payload.device)
    add_sync_event(
        db,
        user_id=user.id,
        actor_user_id=user.id,
        event_type="account.created",
        entity_type="user",
        entity_id=user.id,
        payload={"email": user.email},
    )
    db.commit()
    db.refresh(user)
    return AuthOut(access_token=token, user=user_out(user))


@router.post("/login/verify", response_model=AuthOut)
def login_verify(payload: AuthLoginVerifyIn, db: Session = Depends(get_db)) -> AuthOut:
    email = normalize_email(payload.email)
    user = db.scalar(select(User).where(User.email == email, User.deleted_at.is_(None)))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")
    if not consume_otp(db, email, "login", payload.otp):
        db.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired OTP")

    token, _ = create_session(db, user, payload.device)
    add_sync_event(
        db,
        user_id=user.id,
        actor_user_id=user.id,
        event_type="account.login",
        entity_type="session",
        entity_id=user.id,
        payload={"platform": payload.device.platform if payload.device else None},
    )
    db.commit()
    db.refresh(user)
    return AuthOut(access_token=token, user=user_out(user))

