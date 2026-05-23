from app.models import User

from .conftest import otp_from_logs, register_user


def test_register_login_change_password_and_recovery(client, caplog):
    auth = register_user(client, caplog, "alice@example.com")
    token = auth["access_token"]
    assert auth["user"]["email"] == "alice@example.com"
    assert auth["user"]["key_bundle"]["encryptedMasterKey"] == "ciphertext"

    me = client.get("/account/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert len(me.json()["sessions"]) == 1

    changed = client.post(
        "/account/password/change",
        json={"key_bundle": {"version": 2, "encryptedMasterKey": "new-ciphertext"}},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert changed.status_code == 200
    assert changed.json()["user"]["key_bundle"]["version"] == 2

    client.post("/auth/otp/start", json={"email": "alice@example.com", "purpose": "login"}).raise_for_status()
    login_otp = otp_from_logs(caplog, "alice@example.com", "login")
    login = client.post(
        "/auth/login/verify",
        json={"email": "alice@example.com", "otp": login_otp, "device": {"name": "web", "platform": "web"}},
    )
    assert login.status_code == 200
    assert login.json()["user"]["key_bundle"]["version"] == 2

    client.post("/auth/otp/start", json={"email": "alice@example.com", "purpose": "recovery"}).raise_for_status()
    recovery_otp = otp_from_logs(caplog, "alice@example.com", "recovery")
    recovered = client.post(
        "/account/recovery/reset",
        json={
            "email": "alice@example.com",
            "otp": recovery_otp,
            "key_bundle": {"version": 3, "encryptedMasterKey": "recovered"},
            "device": {"name": "phone", "platform": "ios"},
        },
    )
    assert recovered.status_code == 200
    assert recovered.json()["user"]["key_bundle"]["version"] == 3


def test_delete_account_revokes_access(client, caplog):
    auth = register_user(client, caplog, "delete-me@example.com")
    token = auth["access_token"]
    deleted = client.delete("/account", headers={"Authorization": f"Bearer {token}"})
    assert deleted.status_code == 204

    denied = client.get("/account/me", headers={"Authorization": f"Bearer {token}"})
    assert denied.status_code == 401

