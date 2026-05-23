from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.deps import get_current_user
from app.models import Collection, CollectionMember, User
from app.presenters import collection_out
from app.schemas import CollectionCreateIn, CollectionOut, CollectionShareIn
from app.services import add_sync_event, collection_member, emit_collection_event, normalize_email

router = APIRouter(prefix="/collections", tags=["collections"])


def _collection_with_members(db: Session, collection: Collection, current_user: User) -> CollectionOut:
    current_member = collection_member(db, collection.id, current_user.id)
    if current_member is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Collection not found")
    member_rows = db.execute(
        select(CollectionMember, User)
        .join(User, User.id == CollectionMember.user_id)
        .where(CollectionMember.collection_id == collection.id)
        .order_by(CollectionMember.created_at.asc())
    ).all()
    return collection_out(collection, current_member, list(member_rows))


@router.post("", response_model=CollectionOut, status_code=status.HTTP_201_CREATED)
def create_collection(
    payload: CollectionCreateIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CollectionOut:
    collection = Collection(
        owner_id=current_user.id,
        encrypted_name=payload.encrypted_name,
        name_nonce=payload.name_nonce,
        collection_type=payload.collection_type,
        encrypted_metadata=payload.encrypted_metadata,
    )
    db.add(collection)
    db.flush()
    member = CollectionMember(
        collection_id=collection.id,
        user_id=current_user.id,
        role="owner",
        encrypted_collection_key=payload.encrypted_collection_key,
        collection_key_nonce=payload.collection_key_nonce,
        added_by_user_id=current_user.id,
    )
    db.add(member)
    add_sync_event(
        db,
        user_id=current_user.id,
        actor_user_id=current_user.id,
        event_type="collection.created",
        entity_type="collection",
        entity_id=collection.id,
        payload={"collection_id": collection.id},
    )
    db.commit()
    db.refresh(collection)
    return _collection_with_members(db, collection, current_user)


@router.get("", response_model=list[CollectionOut])
def list_collections(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[CollectionOut]:
    rows = db.execute(
        select(Collection)
        .join(CollectionMember, CollectionMember.collection_id == Collection.id)
        .where(CollectionMember.user_id == current_user.id, Collection.archived_at.is_(None))
        .order_by(Collection.updated_at.desc())
    ).scalars()
    return [_collection_with_members(db, collection, current_user) for collection in rows]


@router.get("/{collection_id}", response_model=CollectionOut)
def get_collection(
    collection_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CollectionOut:
    collection = db.get(Collection, collection_id)
    if collection is None or collection.archived_at is not None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Collection not found")
    return _collection_with_members(db, collection, current_user)


@router.post("/{collection_id}/share", response_model=CollectionOut)
def share_collection(
    collection_id: str,
    payload: CollectionShareIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CollectionOut:
    collection = db.get(Collection, collection_id)
    if collection is None or collection.archived_at is not None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Collection not found")

    current_member = collection_member(db, collection.id, current_user.id)
    if current_member is None or current_member.role != "owner":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only owners can share collections")

    recipient = db.scalar(select(User).where(User.email == normalize_email(payload.recipient_email), User.deleted_at.is_(None)))
    if recipient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recipient not found")
    if recipient.id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot share with yourself")

    existing = collection_member(db, collection.id, recipient.id)
    if existing is None:
        db.add(
            CollectionMember(
                collection_id=collection.id,
                user_id=recipient.id,
                role=payload.role,
                encrypted_collection_key=payload.encrypted_collection_key,
                collection_key_nonce=payload.collection_key_nonce,
                added_by_user_id=current_user.id,
            )
        )
    else:
        existing.role = payload.role
        existing.encrypted_collection_key = payload.encrypted_collection_key
        existing.collection_key_nonce = payload.collection_key_nonce
        db.add(existing)

    db.flush()
    emit_collection_event(
        db,
        collection.id,
        current_user.id,
        "collection.shared",
        {"collection_id": collection.id, "recipient_user_id": recipient.id, "role": payload.role},
    )
    db.commit()
    db.refresh(collection)
    return _collection_with_members(db, collection, current_user)

