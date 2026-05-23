import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import get_db
from app.deps import get_current_user
from app.models import EncryptedFile, FileObject, User
from app.presenters import file_object_out, file_out
from app.schemas import FileCommitIn, FileOut, UploadSessionIn, UploadSessionOut
from app.services import collection_member, emit_collection_event
from app.storage import storage

router = APIRouter(prefix="/files", tags=["files"])


def _ensure_can_read(db: Session, file: EncryptedFile, user: User) -> None:
    if collection_member(db, file.collection_id, user.id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")


def _ensure_can_write_collection(db: Session, collection_id: str, user: User) -> None:
    member = collection_member(db, collection_id, user.id)
    if member is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Collection not found")
    if member.role not in {"owner", "contributor"}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="This collection is read-only")


@router.post("/upload-session", response_model=UploadSessionOut)
def create_upload_session(
    payload: UploadSessionIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> UploadSessionOut:
    _ensure_can_write_collection(db, payload.collection_id, current_user)
    object_key = (
        f"users/{current_user.id}/collections/{payload.collection_id}/"
        f"{uuid.uuid4()}-{payload.object_type}.enc"
    )
    signed = storage.presign_put(object_key, payload.size_bytes, payload.checksum)
    settings = get_settings()
    return UploadSessionOut(
        upload_id=object_key,
        bucket=settings.s3_bucket,
        object_key=object_key,
        upload_url=signed.url,
        expires_in_seconds=settings.upload_url_ttl_seconds,
        headers=signed.headers,
    )


@router.post("/commit", response_model=FileOut, status_code=status.HTTP_201_CREATED)
def commit_file(
    payload: FileCommitIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FileOut:
    _ensure_can_write_collection(db, payload.collection_id, current_user)
    expected_prefix = f"users/{current_user.id}/collections/{payload.collection_id}/"
    for obj in payload.objects:
        if not obj.upload_id.startswith(expected_prefix):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid upload id")

    file = EncryptedFile(
        owner_id=current_user.id,
        collection_id=payload.collection_id,
        encrypted_metadata=payload.encrypted_metadata,
        metadata_nonce=payload.metadata_nonce,
        encrypted_file_key=payload.encrypted_file_key,
        file_key_nonce=payload.file_key_nonce,
        ciphertext_hash=payload.ciphertext_hash,
        original_size=payload.original_size,
        encrypted_size=payload.encrypted_size,
        capture_time_ciphertext=payload.capture_time_ciphertext,
    )
    db.add(file)
    db.flush()
    settings = get_settings()
    object_rows: list[FileObject] = []
    for obj in payload.objects:
        row = FileObject(
            file_id=file.id,
            object_type=obj.object_type,
            bucket=settings.s3_bucket,
            object_key=obj.upload_id,
            size_bytes=obj.size_bytes,
            checksum=obj.checksum,
            encryption_header=obj.encryption_header,
        )
        db.add(row)
        object_rows.append(row)

    current_user.storage_used_bytes += payload.encrypted_size
    db.add(current_user)
    emit_collection_event(
        db,
        payload.collection_id,
        current_user.id,
        "file.created",
        {"collection_id": payload.collection_id, "file_id": file.id},
    )
    db.commit()
    db.refresh(file)
    return file_out(file, [file_object_out(obj) for obj in object_rows])


@router.get("", response_model=list[FileOut])
def list_files(
    collection_id: str = Query(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[FileOut]:
    if collection_member(db, collection_id, current_user.id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Collection not found")
    files = db.scalars(
        select(EncryptedFile)
        .where(EncryptedFile.collection_id == collection_id)
        .order_by(EncryptedFile.created_at.desc())
    ).all()
    return [
        file_out(file, [file_object_out(obj) for obj in file.objects])
        for file in files
    ]


@router.get("/{file_id}/download-url", response_model=FileOut)
def download_url(
    file_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FileOut:
    file = db.get(EncryptedFile, file_id)
    if file is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    _ensure_can_read(db, file, current_user)
    return file_out(
        file,
        [
            file_object_out(obj, download_url=storage.presign_get(obj.object_key))
            for obj in file.objects
        ],
    )

