from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


OtpPurpose = Literal["register", "login", "recovery"]
MemberRole = Literal["owner", "contributor", "viewer"]


def normalize_email_format(value: str) -> str:
    email = value.strip().lower()
    if "@" not in email:
        raise ValueError("value is not a valid email address")
    local, domain = email.rsplit("@", 1)
    if not local or not domain or "." not in domain:
        raise ValueError("value is not a valid email address")
    return email


class EmailModel(BaseModel):
    @field_validator("email", "recipient_email", check_fields=False)
    @classmethod
    def validate_email_format(cls, value: str) -> str:
        return normalize_email_format(value)


class DeviceIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    platform: str = Field(min_length=1, max_length=50)
    app_version: str | None = Field(default=None, max_length=50)


class OtpStartIn(EmailModel):
    email: str
    purpose: OtpPurpose


class OtpStartOut(BaseModel):
    status: str
    delivery: str
    expires_in_seconds: int


class UserOut(BaseModel):
    id: str
    email: str
    public_key: str
    key_bundle: dict[str, Any]
    storage_used_bytes: int


class SessionOut(BaseModel):
    id: str
    device_name: str | None
    platform: str | None
    created_at: str
    expires_at: str
    revoked_at: str | None
    last_seen_at: str | None


class AuthRegisterIn(EmailModel):
    email: str
    otp: str = Field(min_length=6, max_length=12)
    public_key: str = Field(min_length=16)
    key_bundle: dict[str, Any]
    device: DeviceIn | None = None


class AuthLoginVerifyIn(EmailModel):
    email: str
    otp: str = Field(min_length=6, max_length=12)
    device: DeviceIn | None = None


class AuthOut(BaseModel):
    token_type: str = "bearer"
    access_token: str
    user: UserOut


class AccountMeOut(BaseModel):
    user: UserOut
    sessions: list[SessionOut]
    devices: list[dict[str, Any]]


class AccountKeyBundleUpdateIn(BaseModel):
    key_bundle: dict[str, Any]


class RecoveryResetIn(EmailModel):
    email: str
    otp: str = Field(min_length=6, max_length=12)
    key_bundle: dict[str, Any]
    device: DeviceIn | None = None


class CollectionCreateIn(BaseModel):
    encrypted_name: str = Field(min_length=1)
    name_nonce: str = Field(min_length=1)
    encrypted_collection_key: str = Field(min_length=1)
    collection_key_nonce: str | None = None
    collection_type: str = Field(default="album", max_length=50)
    encrypted_metadata: dict[str, Any] | None = None


class CollectionMemberOut(BaseModel):
    user_id: str
    email: str
    role: str
    encrypted_collection_key: str
    collection_key_nonce: str | None


class CollectionOut(BaseModel):
    id: str
    owner_id: str
    encrypted_name: str
    name_nonce: str
    collection_type: str
    encrypted_metadata: dict[str, Any] | None
    role: str
    encrypted_collection_key: str
    collection_key_nonce: str | None
    members: list[CollectionMemberOut] = []


class CollectionShareIn(EmailModel):
    recipient_email: str
    encrypted_collection_key: str = Field(min_length=1)
    collection_key_nonce: str | None = None
    role: Literal["contributor", "viewer"] = "viewer"


class ShareLookupOut(BaseModel):
    user_id: str
    email: str
    public_key: str


class UploadSessionIn(BaseModel):
    collection_id: str
    object_type: Literal["original", "thumbnail"] = "original"
    size_bytes: int = Field(ge=1)
    checksum: str | None = Field(default=None, max_length=128)


class UploadSessionOut(BaseModel):
    upload_id: str
    bucket: str
    object_key: str
    upload_url: str
    expires_in_seconds: int
    headers: dict[str, str]


class FileObjectCommitIn(BaseModel):
    upload_id: str
    object_type: Literal["original", "thumbnail"]
    size_bytes: int = Field(ge=1)
    checksum: str | None = Field(default=None, max_length=128)
    encryption_header: str = Field(min_length=1)


class FileCommitIn(BaseModel):
    collection_id: str
    encrypted_metadata: dict[str, Any]
    metadata_nonce: str = Field(min_length=1)
    encrypted_file_key: str = Field(min_length=1)
    file_key_nonce: str | None = None
    ciphertext_hash: str = Field(min_length=16, max_length=128)
    original_size: int | None = Field(default=None, ge=0)
    encrypted_size: int = Field(ge=1)
    capture_time_ciphertext: str | None = None
    objects: list[FileObjectCommitIn] = Field(min_length=1)


class FileObjectOut(BaseModel):
    object_type: str
    bucket: str
    object_key: str
    size_bytes: int
    checksum: str | None
    encryption_header: str
    download_url: str | None = None


class FileOut(BaseModel):
    id: str
    owner_id: str
    collection_id: str
    encrypted_metadata: dict[str, Any]
    metadata_nonce: str
    encrypted_file_key: str
    file_key_nonce: str | None
    ciphertext_hash: str
    original_size: int | None
    encrypted_size: int
    capture_time_ciphertext: str | None
    objects: list[FileObjectOut]


class SearchIndexUpsertIn(BaseModel):
    file_id: str = Field(min_length=1)
    collection_id: str = Field(min_length=1)
    model_version: str = Field(min_length=1, max_length=80)
    encrypted_payload: str = Field(min_length=1)
    payload_nonce: str = Field(min_length=1)


class SearchIndexOut(BaseModel):
    id: str
    user_id: str
    file_id: str
    collection_id: str
    model_version: str
    encrypted_payload: str
    payload_nonce: str
    created_at: str
    updated_at: str


class SyncEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    actor_user_id: str | None
    event_type: str
    entity_type: str
    entity_id: str
    payload: dict[str, Any]
    created_at: str


class SyncOut(BaseModel):
    events: list[SyncEventOut]
    next_cursor: int
