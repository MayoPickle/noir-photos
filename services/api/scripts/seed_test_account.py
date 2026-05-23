import argparse
import base64
import sys
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv
import nacl.bindings as sodium
import nacl.pwhash.argon2id as argon2id
from sqlalchemy import select

ROOT = Path(__file__).resolve().parents[3]
API_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(API_ROOT))
load_dotenv(ROOT / ".env")

from app.core.security import hash_secret, seconds_from_now, utcnow
from app.db.session import SessionLocal, engine
from app.models import Base, EmailOtp, User
from app.services import normalize_email


def b64(value: bytes) -> str:
    return base64.b64encode(value).decode("ascii")


def wrap_secret(message: bytes, key: bytes) -> dict[str, str]:
    nonce = sodium.randombytes(sodium.crypto_secretbox_NONCEBYTES)
    ciphertext = sodium.crypto_secretbox_easy(message, nonce, key)
    return {"ciphertext": b64(ciphertext), "nonce": b64(nonce)}


def key_bundle_for_password(password: str) -> tuple[str, dict]:
    master_key = sodium.randombytes(sodium.crypto_secretbox_KEYBYTES)
    public_key, private_key = sodium.crypto_box_keypair()
    salt = sodium.randombytes(argon2id.SALTBYTES)
    ops_limit = argon2id.OPSLIMIT_MODERATE
    mem_limit = argon2id.MEMLIMIT_MODERATE
    password_key = argon2id.kdf(
        sodium.crypto_secretbox_KEYBYTES,
        password.encode("utf-8"),
        salt,
        opslimit=ops_limit,
        memlimit=mem_limit,
    )
    recovery_key = sodium.randombytes(sodium.crypto_secretbox_KEYBYTES)
    return b64(public_key), {
        "version": 1,
        "kdf": {
            "name": "argon2id",
            "salt": b64(salt),
            "opsLimit": ops_limit,
            "memLimit": mem_limit,
            "algorithm": "argon2id13",
        },
        "encryptedMasterKey": wrap_secret(master_key, password_key),
        "encryptedPrivateKey": wrap_secret(private_key, master_key),
        "recovery": {
            "type": "seeded-dev-only",
            "encryptedMasterKey": wrap_secret(master_key, recovery_key),
        },
    }


def seed(email: str, password: str, otp: str) -> None:
    Base.metadata.create_all(bind=engine)
    normalized_email = normalize_email(email)
    public_key, key_bundle = key_bundle_for_password(password)

    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.email == normalized_email))
        if user is None:
            user = User(
                email=normalized_email,
                public_key=public_key,
                key_bundle=key_bundle,
                storage_used_bytes=0,
            )
        else:
            user.public_key = public_key
            user.key_bundle = key_bundle
            user.deleted_at = None
        db.add(user)

        db.query(EmailOtp).filter(
            EmailOtp.email == normalized_email,
            EmailOtp.purpose == "login",
            EmailOtp.consumed_at.is_(None),
        ).update({"consumed_at": utcnow()}, synchronize_session=False)
        db.add(
            EmailOtp(
                email=normalized_email,
                purpose="login",
                otp_hash=hash_secret(otp),
                expires_at=seconds_from_now(int(timedelta(days=30).total_seconds())),
            )
        )
        db.commit()

    print(f"Seeded account: {normalized_email}")
    print(f"Password: {password}")
    print(f"Development login OTP: {otp}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed a development Noir Photos account.")
    parser.add_argument("--email", default="demo@noir.local")
    parser.add_argument("--password", default="NoirDemo123!")
    parser.add_argument("--otp", default="000000")
    args = parser.parse_args()
    seed(args.email, args.password, args.otp)


if __name__ == "__main__":
    main()
