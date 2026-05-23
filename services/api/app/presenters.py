from app.models import Collection, CollectionMember, EncryptedFile, FileObject, SearchIndex, SessionToken, User
from app.schemas import (
    CollectionMemberOut,
    CollectionOut,
    FileObjectOut,
    FileOut,
    SearchIndexOut,
    SessionOut,
    UserOut,
)


def user_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        email=user.email,
        public_key=user.public_key,
        key_bundle=user.key_bundle,
        storage_used_bytes=user.storage_used_bytes,
    )


def session_out(session: SessionToken) -> SessionOut:
    return SessionOut(
        id=session.id,
        device_name=session.device_name,
        platform=session.platform,
        created_at=session.created_at.isoformat(),
        expires_at=session.expires_at.isoformat(),
        revoked_at=session.revoked_at.isoformat() if session.revoked_at else None,
        last_seen_at=session.last_seen_at.isoformat() if session.last_seen_at else None,
    )


def collection_out(
    collection: Collection,
    current_member: CollectionMember,
    members: list[tuple[CollectionMember, User]],
) -> CollectionOut:
    return CollectionOut(
        id=collection.id,
        owner_id=collection.owner_id,
        encrypted_name=collection.encrypted_name,
        name_nonce=collection.name_nonce,
        collection_type=collection.collection_type,
        encrypted_metadata=collection.encrypted_metadata,
        role=current_member.role,
        encrypted_collection_key=current_member.encrypted_collection_key,
        collection_key_nonce=current_member.collection_key_nonce,
        members=[
            CollectionMemberOut(
                user_id=user.id,
                email=user.email,
                role=member.role,
                encrypted_collection_key=member.encrypted_collection_key,
                collection_key_nonce=member.collection_key_nonce,
            )
            for member, user in members
        ],
    )


def file_object_out(obj: FileObject, download_url: str | None = None) -> FileObjectOut:
    return FileObjectOut(
        object_type=obj.object_type,
        bucket=obj.bucket,
        object_key=obj.object_key,
        size_bytes=obj.size_bytes,
        checksum=obj.checksum,
        encryption_header=obj.encryption_header,
        download_url=download_url,
    )


def file_out(file: EncryptedFile, objects: list[FileObjectOut]) -> FileOut:
    return FileOut(
        id=file.id,
        owner_id=file.owner_id,
        collection_id=file.collection_id,
        encrypted_metadata=file.encrypted_metadata,
        metadata_nonce=file.metadata_nonce,
        encrypted_file_key=file.encrypted_file_key,
        file_key_nonce=file.file_key_nonce,
        ciphertext_hash=file.ciphertext_hash,
        original_size=file.original_size,
        encrypted_size=file.encrypted_size,
        capture_time_ciphertext=file.capture_time_ciphertext,
        objects=objects,
    )


def search_index_out(index: SearchIndex) -> SearchIndexOut:
    return SearchIndexOut(
        id=index.id,
        user_id=index.user_id,
        file_id=index.file_id,
        collection_id=index.collection_id,
        model_version=index.model_version,
        encrypted_payload=index.encrypted_payload,
        payload_nonce=index.payload_nonce,
        created_at=index.created_at.isoformat(),
        updated_at=index.updated_at.isoformat(),
    )
