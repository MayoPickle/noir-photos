import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

from .config import get_settings


def utcnow() -> datetime:
    return datetime.now(UTC)


def as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def generate_token() -> str:
    return secrets.token_urlsafe(48)


def hash_secret(value: str) -> str:
    settings = get_settings()
    return hmac.new(
        settings.secret_key.encode("utf-8"),
        value.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def constant_time_equal(left: str, right: str) -> bool:
    return hmac.compare_digest(left, right)


def expires_in(days: int) -> datetime:
    return utcnow() + timedelta(days=days)


def seconds_from_now(seconds: int) -> datetime:
    return utcnow() + timedelta(seconds=seconds)
