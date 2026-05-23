from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.deps import get_current_user
from app.models import SyncEvent, User
from app.schemas import SyncEventOut, SyncOut

router = APIRouter(prefix="/sync", tags=["sync"])


@router.get("", response_model=SyncOut)
def sync(
    cursor: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=500),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SyncOut:
    events = db.scalars(
        select(SyncEvent)
        .where(SyncEvent.user_id == current_user.id, SyncEvent.id > cursor)
        .order_by(SyncEvent.id.asc())
        .limit(limit)
    ).all()
    next_cursor = events[-1].id if events else cursor
    return SyncOut(
        events=[
            SyncEventOut(
                id=event.id,
                actor_user_id=event.actor_user_id,
                event_type=event.event_type,
                entity_type=event.entity_type,
                entity_id=event.entity_id,
                payload=event.payload,
                created_at=event.created_at.isoformat(),
            )
            for event in events
        ],
        next_cursor=next_cursor,
    )

