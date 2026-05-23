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


def test_upload_commit_download_and_sync(client, caplog):
    auth = register_user(client, caplog, "owner@example.com")
    token = auth["access_token"]
    collection = create_collection(client, token)

    upload = client.post(
        "/files/upload-session",
        json={"collection_id": collection["id"], "object_type": "original", "size_bytes": 128},
        headers=auth_header(token),
    )
    assert upload.status_code == 200
    upload_json = upload.json()
    assert upload_json["object_key"].startswith(f"users/{auth['user']['id']}/collections/{collection['id']}/")

    committed = client.post(
        "/files/commit",
        json={
            "collection_id": collection["id"],
            "encrypted_metadata": {"filename": "ciphertext", "exif": "ciphertext"},
            "metadata_nonce": "metadata-nonce",
            "encrypted_file_key": "file-key-ciphertext",
            "file_key_nonce": "file-key-nonce",
            "ciphertext_hash": "a" * 64,
            "original_size": 100,
            "encrypted_size": 128,
            "objects": [
                {
                    "upload_id": upload_json["upload_id"],
                    "object_type": "original",
                    "size_bytes": 128,
                    "checksum": "a" * 64,
                    "encryption_header": "secretstream-header",
                }
            ],
        },
        headers=auth_header(token),
    )
    assert committed.status_code == 201
    file_id = committed.json()["id"]

    download = client.get(f"/files/{file_id}/download-url", headers=auth_header(token))
    assert download.status_code == 200
    assert download.json()["objects"][0]["download_url"].startswith("http://local-object-storage.test/")

    sync = client.get("/sync?cursor=0", headers=auth_header(token))
    assert sync.status_code == 200
    assert [event["event_type"] for event in sync.json()["events"]] == [
        "account.created",
        "collection.created",
        "file.created",
    ]


def test_share_collection_with_registered_user(client, caplog):
    owner = register_user(client, caplog, "owner-share@example.com", public_key="owner-public-key-valid")
    recipient = register_user(client, caplog, "recipient@example.com", public_key="recipient-public-key-valid")
    collection = create_collection(client, owner["access_token"])

    lookup = client.get(
        "/sharing/lookup?email=recipient@example.com",
        headers=auth_header(owner["access_token"]),
    )
    assert lookup.status_code == 200
    assert lookup.json()["public_key"] == "recipient-public-key-valid"

    shared = client.post(
        f"/collections/{collection['id']}/share",
        json={
            "recipient_email": "recipient@example.com",
            "encrypted_collection_key": "sealed-key-for-recipient",
            "collection_key_nonce": None,
            "role": "viewer",
        },
        headers=auth_header(owner["access_token"]),
    )
    assert shared.status_code == 200
    assert any(member["email"] == "recipient@example.com" for member in shared.json()["members"])

    recipient_collections = client.get("/collections", headers=auth_header(recipient["access_token"]))
    assert recipient_collections.status_code == 200
    assert recipient_collections.json()[0]["encrypted_collection_key"] == "sealed-key-for-recipient"
    assert recipient_collections.json()[0]["role"] == "viewer"

    viewer_upload = client.post(
        "/files/upload-session",
        json={"collection_id": collection["id"], "object_type": "original", "size_bytes": 128},
        headers=auth_header(recipient["access_token"]),
    )
    assert viewer_upload.status_code == 403
