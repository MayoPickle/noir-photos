from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.deps import get_current_user
from app.models import CollectionMember, EncryptedFile, SearchIndex, User
from app.presenters import search_index_out
from app.schemas import SearchIndexOut, SearchIndexUpsertIn
from app.services import add_sync_event, collection_member

router = APIRouter(prefix="/search-index", tags=["search-index"])


def _ensure_can_index_file(db: Session, payload: SearchIndexUpsertIn, user: User) -> EncryptedFile:
    file = db.get(EncryptedFile, payload.file_id)
    if file is None or file.collection_id != payload.collection_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    if collection_member(db, payload.collection_id, user.id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return file


def _emit_index_event(db: Session, index: SearchIndex, actor_user_id: str, event_type: str) -> None:
    add_sync_event(
        db,
        user_id=index.user_id,
        actor_user_id=actor_user_id,
        event_type=event_type,
        entity_type="search_index",
        entity_id=index.id,
        payload={
            "search_index_id": index.id,
            "file_id": index.file_id,
            "collection_id": index.collection_id,
            "model_version": index.model_version,
        },
    )


@router.put("", response_model=SearchIndexOut)
def upsert_search_index(
    payload: SearchIndexUpsertIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SearchIndexOut:
    _ensure_can_index_file(db, payload, current_user)
    index = db.scalar(
        select(SearchIndex).where(
            SearchIndex.user_id == current_user.id,
            SearchIndex.file_id == payload.file_id,
            SearchIndex.model_version == payload.model_version,
        )
    )
    event_type = "search_index.updated"
    if index is None:
        index = SearchIndex(
            user_id=current_user.id,
            file_id=payload.file_id,
            collection_id=payload.collection_id,
            model_version=payload.model_version,
            encrypted_payload=payload.encrypted_payload,
            payload_nonce=payload.payload_nonce,
        )
        event_type = "search_index.created"
    else:
        index.collection_id = payload.collection_id
        index.encrypted_payload = payload.encrypted_payload
        index.payload_nonce = payload.payload_nonce
    db.add(index)
    db.flush()
    _emit_index_event(db, index, current_user.id, event_type)
    db.commit()
    db.refresh(index)
    return search_index_out(index)


@router.get("", response_model=list[SearchIndexOut])
def list_search_indexes(
    collection_id: str | None = Query(default=None),
    model_version: str | None = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[SearchIndexOut]:
    query = (
        select(SearchIndex)
        .join(CollectionMember, CollectionMember.collection_id == SearchIndex.collection_id)
        .where(SearchIndex.user_id == current_user.id, CollectionMember.user_id == current_user.id)
        .order_by(SearchIndex.updated_at.desc())
    )
    if collection_id is not None:
        query = query.where(SearchIndex.collection_id == collection_id)
    if model_version is not None:
        query = query.where(SearchIndex.model_version == model_version)
    indexes = db.scalars(query).all()
    return [search_index_out(index) for index in indexes]


@router.delete("/{file_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_search_index(
    file_id: str,
    model_version: str = Query(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    index = db.scalar(
        select(SearchIndex).where(
            SearchIndex.user_id == current_user.id,
            SearchIndex.file_id == file_id,
            SearchIndex.model_version == model_version,
        )
    )
    if index is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Search index not found")
    _emit_index_event(db, index, current_user.id, "search_index.deleted")
    db.delete(index)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
