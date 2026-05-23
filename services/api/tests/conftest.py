import os
import re
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

os.environ.setdefault("NOIR_ENV", "test")
os.environ.setdefault("NOIR_SECRET_KEY", "test-secret")
os.environ.setdefault("NOIR_DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("NOIR_OBJECT_STORAGE_BACKEND", "local")

from app.db.session import get_db
from app.main import app
from app.models import Base


@pytest.fixture()
def client() -> Generator[TestClient, None, None]:
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    Base.metadata.create_all(bind=engine)

    def override_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def otp_from_logs(caplog, email: str, purpose: str) -> str:
    pattern = re.compile(rf"email={re.escape(email)} purpose={purpose} code=(\d{{6}})")
    for record in reversed(caplog.records):
        match = pattern.search(record.getMessage())
        if match:
            return match.group(1)
    raise AssertionError(f"OTP for {email} / {purpose} not found in logs")


def register_user(client: TestClient, caplog, email: str, public_key: str = "pub-key-with-valid-length") -> dict:
    client.post("/auth/otp/start", json={"email": email, "purpose": "register"}).raise_for_status()
    otp = otp_from_logs(caplog, email, "register")
    response = client.post(
        "/auth/register",
        json={
            "email": email,
            "otp": otp,
            "public_key": public_key,
            "key_bundle": {
                "version": 1,
                "kdf": {"name": "argon2id"},
                "encryptedMasterKey": "ciphertext",
                "masterKeyNonce": "nonce",
            },
            "device": {"name": "test", "platform": "pytest"},
        },
    )
    response.raise_for_status()
    return response.json()
