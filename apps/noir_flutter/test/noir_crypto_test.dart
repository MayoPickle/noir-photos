import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noir_flutter/src/crypto/noir_crypto.dart';

void main() {
  late NoirCrypto crypto;

  setUpAll(() async {
    crypto = await NoirCrypto.load();
  });

  test('creates and unlocks password protected key bundle', () {
    final registration =
        crypto.createRegistrationBundle('correct horse battery staple');
    final unlocked = crypto.unlockFromPassword(
      password: 'correct horse battery staple',
      publicKey: registration.publicKey,
      keyBundle: registration.keyBundle,
    );

    expect(unlocked.accountKeyPair.publicKey,
        registration.vault.accountKeyPair.publicKey);
    expect(
      () => crypto.unlockFromPassword(
        password: 'wrong password',
        publicKey: registration.publicKey,
        keyBundle: registration.keyBundle,
      ),
      throwsA(anything),
    );
  });

  test('encrypts and decrypts metadata and media', () async {
    final registration = crypto.createRegistrationBundle('password');
    final draft =
        crypto.createCollectionDraft(name: 'Camera', vault: registration.vault);
    final media = await crypto.encryptMedia(
      bytes: Uint8List.fromList(utf8.encode('secret pixels')),
      collectionKey: draft.collectionKey,
      metadata: {'filename': 'photo.jpg'},
    );

    final clear = await crypto.decryptMedia(
      ciphertext: media.ciphertext,
      encryptionHeader: media.encryptionHeader,
      encryptedFileKey: media.encryptedFileKey,
      fileKeyNonce: media.fileKeyNonce!,
      collectionKey: draft.collectionKey,
    );
    expect(utf8.decode(clear), 'secret pixels');
  });

  test('seals collection key for a recipient', () {
    final owner = crypto.createRegistrationBundle('owner');
    final recipient = crypto.createRegistrationBundle('recipient');
    final draft =
        crypto.createCollectionDraft(name: 'Shared', vault: owner.vault);
    final body = crypto.shareCollectionBody(
      collectionKey: draft.collectionKey,
      recipientEmail: 'recipient@example.com',
      recipientPublicKey: recipient.publicKey,
    );

    final opened = crypto.openCollectionKey({
      'encrypted_collection_key': body['encrypted_collection_key'],
      'collection_key_nonce': null,
    }, recipient.vault);
    expect(opened.extractBytes(), draft.collectionKey.extractBytes());
  });

  test('encrypts search index payloads without leaking labels or people', () {
    final registration = crypto.createRegistrationBundle('search');
    final encrypted = crypto.encryptSearchIndexPayload({
      'fileId': 'file-id',
      'labels': ['car', 'ocean'],
      'people': [
        {'name': 'Alice'}
      ],
      'imageEmbedding': [0.1, 0.2, 0.3],
    }, registration.vault);

    expect(encrypted.ciphertext, isNot(contains('Alice')));
    expect(encrypted.ciphertext, isNot(contains('car')));

    final clear =
        crypto.decryptSearchIndexPayload(encrypted, registration.vault);
    expect(clear['labels'], ['car', 'ocean']);
    expect((clear['people'] as List).single['name'], 'Alice');
  });
}
