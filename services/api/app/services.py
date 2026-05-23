from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import as_utc, generate_token, hash_secret, seconds_from_now, utcnow
from app.models import CollectionMember, Device, EmailOtp, SessionToken, SyncEvent, User
from app.schemas import DeviceIn


def normalize_email(email: str) -> str:
    return email.strip().lower()


def create_session(db: Session, user: User, device: DeviceIn | None = None) -> tuple[str, SessionToken]:
    settings = get_settings()
    token = generate_token()
    session = SessionToken(
        user_id=user.id,
        token_hash=hash_secret(token),
        device_name=device.name if device else None,
        platform=device.platform if device else None,
        expires_at=seconds_from_now(settings.access_token_days * 24 * 60 * 60),
        last_seen_at=utcnow(),
    )
    db.add(session)
    if device is not None:
        db.add(
            Device(
                user_id=user.id,
                name=device.name,
                platform=device.platform,
                app_version=device.app_version,
                last_seen_at=utcnow(),
            )
        )
    db.flush()
    return token, session


def consume_otp(db: Session, email: str, purpose: str, code: str) -> bool:
    rows = db.scalars(
        select(EmailOtp)
        .where(
            EmailOtp.email == normalize_email(email),
            EmailOtp.purpose == purpose,
            EmailOtp.consumed_at.is_(None),
        )
        .order_by(EmailOtp.created_at.desc())
    ).all()
    hashed = hash_secret(code)
    now = utcnow()
    for otp in rows:
        if as_utc(otp.expires_at) <= now:
            continue
        otp.attempts += 1
        if otp.otp_hash == hashed:
            otp.consumed_at = now
            db.add(otp)
            return True
        db.add(otp)
    return False


def add_sync_event(
    db: Session,
    *,
    user_id: str,
    actor_user_id: str | None,
    event_type: str,
    entity_type: str,
    entity_id: str,
    payload: dict,
) -> SyncEvent:
    event = SyncEvent(
        user_id=user_id,
        actor_user_id=actor_user_id,
        event_type=event_type,
        entity_type=entity_type,
        entity_id=entity_id,
        payload=payload,
    )
    db.add(event)
    return event


def collection_member(db: Session, collection_id: str, user_id: str) -> CollectionMember | None:
    return db.scalar(
        select(CollectionMember).where(
            CollectionMember.collection_id == collection_id,
            CollectionMember.user_id == user_id,
        )
    )


def collection_member_user_ids(db: Session, collection_id: str) -> list[str]:
    return list(
        db.scalars(select(CollectionMember.user_id).where(CollectionMember.collection_id == collection_id)).all()
    )


def emit_collection_event(db: Session, collection_id: str, actor_user_id: str, event_type: str, payload: dict) -> None:
    for user_id in collection_member_user_ids(db, collection_id):
        add_sync_event(
            db,
            user_id=user_id,
            actor_user_id=actor_user_id,
            event_type=event_type,
            entity_type="collection",
            entity_id=collection_id,
            payload=payload,
        )
