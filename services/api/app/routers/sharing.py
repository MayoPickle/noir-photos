from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas import ShareLookupOut
from app.services import normalize_email

router = APIRouter(prefix="/sharing", tags=["sharing"])


@router.get("/lookup", response_model=ShareLookupOut)
def lookup_recipient(
    email: str = Query(min_length=3),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ShareLookupOut:
    recipient = db.scalar(select(User).where(User.email == normalize_email(email), User.deleted_at.is_(None)))
    if recipient is None or recipient.id == current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recipient not found")
    return ShareLookupOut(user_id=recipient.id, email=recipient.email, public_key=recipient.public_key)

