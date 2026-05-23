from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import utcnow
from app.db.session import get_db
from app.deps import get_current_session, get_current_user
from app.models import Device, FileObject, SessionToken, User
from app.presenters import session_out, user_out
from app.schemas import AccountKeyBundleUpdateIn, AccountMeOut, AuthOut, RecoveryResetIn
from app.services import add_sync_event, consume_otp, create_session, normalize_email
from app.storage import storage

router = APIRouter(prefix="/account", tags=["account"])


@router.get("/me", response_model=AccountMeOut)
def me(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AccountMeOut:
    sessions = db.scalars(
        select(SessionToken)
        .where(SessionToken.user_id == current_user.id)
        .order_by(SessionToken.created_at.desc())
    ).all()
    devices = db.scalars(
        select(Device)
        .where(Device.user_id == current_user.id)
        .order_by(Device.updated_at.desc())
    ).all()
    return AccountMeOut(
        user=user_out(current_user),
        sessions=[session_out(session) for session in sessions],
        devices=[
            {
                "id": device.id,
                "name": device.name,
                "platform": device.platform,
                "app_version": device.app_version,
                "last_seen_at": device.last_seen_at.isoformat() if device.last_seen_at else None,
                "created_at": device.created_at.isoformat(),
            }
            for device in devices
        ],
    )


@router.post("/password/change", response_model=AccountMeOut)
def change_password(
    payload: AccountKeyBundleUpdateIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AccountMeOut:
    current_user.key_bundle = payload.key_bundle
    db.add(current_user)
    add_sync_event(
        db,
        user_id=current_user.id,
        actor_user_id=current_user.id,
        event_type="account.key_bundle_updated",
        entity_type="user",
        entity_id=current_user.id,
        payload={},
    )
    db.commit()
    db.refresh(current_user)
    return me(current_user=current_user, db=db)


@router.post("/recovery/reset", response_model=AuthOut)
def recovery_reset(payload: RecoveryResetIn, db: Session = Depends(get_db)) -> AuthOut:
    email = normalize_email(payload.email)
    user = db.scalar(select(User).where(User.email == email, User.deleted_at.is_(None)))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")
    if not consume_otp(db, email, "recovery", payload.otp):
        db.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired OTP")

    user.key_bundle = payload.key_bundle
    db.add(user)
    db.query(SessionToken).filter(SessionToken.user_id == user.id, SessionToken.revoked_at.is_(None)).update(
        {"revoked_at": utcnow()},
        synchronize_session=False,
    )
    token, _ = create_session(db, user, payload.device)
    add_sync_event(
        db,
        user_id=user.id,
        actor_user_id=user.id,
        event_type="account.recovered",
        entity_type="user",
        entity_id=user.id,
        payload={},
    )
    db.commit()
    db.refresh(user)
    return AuthOut(access_token=token, user=user_out(user))


@router.post("/sessions/{session_id}/revoke", status_code=status.HTTP_204_NO_CONTENT)
def revoke_session(
    session_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    session = db.get(SessionToken, session_id)
    if session is None or session.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found")
    session.revoked_at = utcnow()
    db.add(session)
    add_sync_event(
        db,
        user_id=current_user.id,
        actor_user_id=current_user.id,
        event_type="session.revoked",
        entity_type="session",
        entity_id=session.id,
        payload={},
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/sessions/revoke-all", status_code=status.HTTP_204_NO_CONTENT)
def revoke_all_sessions(
    current_session: SessionToken = Depends(get_current_session),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    db.query(SessionToken).filter(
        SessionToken.user_id == current_user.id,
        SessionToken.id != current_session.id,
        SessionToken.revoked_at.is_(None),
    ).update({"revoked_at": utcnow()}, synchronize_session=False)
    add_sync_event(
        db,
        user_id=current_user.id,
        actor_user_id=current_user.id,
        event_type="session.revoked_all",
        entity_type="user",
        entity_id=current_user.id,
        payload={},
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    objects = db.scalars(
        select(FileObject).join(FileObject.file).where(FileObject.file.has(owner_id=current_user.id))
    ).all()
    for obj in objects:
        storage.delete_object(obj.object_key)
    current_user.deleted_at = utcnow()
    current_user.email = f"deleted-{current_user.id}@deleted.noir.local"
    db.add(current_user)
    db.query(SessionToken).filter(SessionToken.user_id == current_user.id).update(
        {"revoked_at": utcnow()},
        synchronize_session=False,
    )
    add_sync_event(
        db,
        user_id=current_user.id,
        actor_user_id=current_user.id,
        event_type="account.deleted",
        entity_type="user",
        entity_id=current_user.id,
        payload={},
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

