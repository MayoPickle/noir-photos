from .conftest import register_user


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def create_collection(client, token: str) -> dict:
    response = client.post(
        "/collections",
        json={
            "encrypted_name": "album-name-ciphertext",
            "name_nonce": "album-name-nonce",
            "encrypted_collection_key": "collection-key-for-owner",
            "collection_key_nonce": "collection-key-nonce",
            "encrypted_metadata": {"cover": "encrypted-cover"},
        },
        headers=auth_header(token),
    )
    response.raise_for_status()
    return response.json()


def commit_file(client, token: str, collection_id: str) -> dict:
    upload = client.post(
        "/files/upload-session",
        json={"collection_id": collection_id, "object_type": "original", "size_bytes": 128},
        headers=auth_header(token),
    )
    upload.raise_for_status()
    committed = client.post(
        "/files/commit",
        json={
            "collection_id": collection_id,
            "encrypted_metadata": {"filename": "ciphertext"},
            "metadata_nonce": "metadata-nonce",
            "encrypted_file_key": "file-key-ciphertext",
            "file_key_nonce": "file-key-nonce",
            "ciphertext_hash": "b" * 64,
            "original_size": 100,
            "encrypted_size": 128,
            "objects": [
                {
                    "upload_id": upload.json()["upload_id"],
                    "object_type": "original",
                    "size_bytes": 128,
                    "checksum": "b" * 64,
                    "encryption_header": "secretstream-header",
                }
            ],
        },
        headers=auth_header(token),
    )
    committed.raise_for_status()
    return committed.json()


def test_search_index_is_opaque_per_user_and_syncs(client, caplog):
    owner = register_user(client, caplog, "index-owner@example.com")
    outsider = register_user(client, caplog, "index-outsider@example.com")
    collection = create_collection(client, owner["access_token"])
    file = commit_file(client, owner["access_token"], collection["id"])
    payload = {
        "file_id": file["id"],
        "collection_id": collection["id"],
        "model_version": "mobileclip-s0-test",
        "encrypted_payload": "opaque-ciphertext-containing-no-server-contract",
        "payload_nonce": "opaque-nonce",
    }

    created = client.put("/search-index", json=payload, headers=auth_header(owner["access_token"]))
    assert created.status_code == 200
    assert created.json()["encrypted_payload"] == payload["encrypted_payload"]
    assert created.json()["payload_nonce"] == payload["payload_nonce"]

    listed = client.get("/search-index?model_version=mobileclip-s0-test", headers=auth_header(owner["access_token"]))
    assert listed.status_code == 200
    assert [row["file_id"] for row in listed.json()] == [file["id"]]
    assert listed.json()[0]["user_id"] == owner["user"]["id"]

    outsider_list = client.get("/search-index", headers=auth_header(outsider["access_token"]))
    assert outsider_list.status_code == 200
    assert outsider_list.json() == []

    outsider_write = client.put("/search-index", json=payload, headers=auth_header(outsider["access_token"]))
    assert outsider_write.status_code == 404

    sync = client.get("/sync?cursor=0", headers=auth_header(owner["access_token"]))
    assert sync.status_code == 200
    assert "search_index.created" in [event["event_type"] for event in sync.json()["events"]]


def test_search_index_upsert_and_delete_are_scoped_to_current_user(client, caplog):
    owner = register_user(client, caplog, "index-update@example.com")
    collection = create_collection(client, owner["access_token"])
    file = commit_file(client, owner["access_token"], collection["id"])
    first = {
        "file_id": file["id"],
        "collection_id": collection["id"],
        "model_version": "mobileclip-s0-test",
        "encrypted_payload": "first-ciphertext",
        "payload_nonce": "first-nonce",
    }
    second = {**first, "encrypted_payload": "second-ciphertext", "payload_nonce": "second-nonce"}

    created = client.put("/search-index", json=first, headers=auth_header(owner["access_token"]))
    assert created.status_code == 200
    updated = client.put("/search-index", json=second, headers=auth_header(owner["access_token"]))
    assert updated.status_code == 200
    assert updated.json()["id"] == created.json()["id"]
    assert updated.json()["encrypted_payload"] == "second-ciphertext"

    deleted = client.delete(
        f"/search-index/{file['id']}?model_version=mobileclip-s0-test",
        headers=auth_header(owner["access_token"]),
    )
    assert deleted.status_code == 204

    listed = client.get("/search-index", headers=auth_header(owner["access_token"]))
    assert listed.status_code == 200
    assert listed.json() == []
