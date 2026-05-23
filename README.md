# Noir Photos

Noir Photos is a local-first, end-to-end encrypted photo library inspired by Ente's encryption architecture. The client encrypts all photos, thumbnails, album names, metadata, and shared collection keys before anything is sent to the server. The FastAPI service stores only encrypted blobs, encrypted key bundles, encrypted metadata, and the minimum account/sync metadata needed to operate the app.

## Monorepo Layout

- `apps/noir_flutter` - Flutter client source for iOS, Android, and Web.
- `services/api` - FastAPI backend with PostgreSQL metadata and MinIO object storage.
- `docker-compose.yml` - Local Postgres, MinIO, and API stack.

## Local Backend

```bash
cp .env.example .env
docker compose up --build
```

The API will be available at `http://localhost:8000`. In development, email OTP codes are logged by FastAPI and are not sent through SMTP.

## Flutter Client

This workspace does not vendor generated native runners. After installing Flutter, generate platform folders once:

```bash
cd apps/noir_flutter
flutter create . --platforms=ios,android,web
flutter pub get
dart run sodium:update_web --sumo
flutter run
```

The checked-in `lib/`, `test/`, `web/index.html`, and `pubspec.yaml` contain the application implementation and dependency contract.

## Security Model

- The password never leaves the client.
- The client derives a key encryption key with Argon2id via libsodium.
- `masterKey`, `recoveryKey`, `collectionKey`, and `fileKey` are 256-bit random keys.
- Small keys are wrapped with `crypto_secretbox`.
- Files are encrypted in chunks with `crypto_secretstream_xchacha20poly1305`.
- Shared albums wrap the `collectionKey` with the recipient's `crypto_box` public key.
- The server cannot decrypt file bytes, filenames, EXIF, collection names, thumbnails, or shared collection keys.
- Search indexes are generated and queried on the client. People labels, object labels, face data, and image/text embeddings are encrypted with the user's `masterKey` before sync; the server stores only opaque search-index ciphertext and never runs semantic search.
