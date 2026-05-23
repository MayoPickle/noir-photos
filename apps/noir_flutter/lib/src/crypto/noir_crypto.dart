import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:sodium/sodium_sumo.dart';

String b64(Uint8List bytes) => base64Encode(bytes);
Uint8List unb64(String value) => base64Decode(value);

class WrappedKey {
  const WrappedKey({required this.ciphertext, required this.nonce});

  final String ciphertext;
  final String nonce;

  Map<String, dynamic> toJson() => {'ciphertext': ciphertext, 'nonce': nonce};

  static WrappedKey fromJson(Map<String, dynamic> json) {
    return WrappedKey(
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
    );
  }
}

class UnlockedVault {
  UnlockedVault({required this.masterKey, required this.accountKeyPair});

  final SecureKey masterKey;
  final KeyPair accountKeyPair;

  Map<String, dynamic> toLocalJson() => {
        'publicKey': b64(accountKeyPair.publicKey),
        'masterKey': b64(masterKey.extractBytes()),
        'privateKey': b64(accountKeyPair.secretKey.extractBytes()),
      };

  void dispose() {
    masterKey.dispose();
    accountKeyPair.dispose();
  }
}

class RegistrationCryptoBundle {
  RegistrationCryptoBundle({
    required this.publicKey,
    required this.keyBundle,
    required this.recoveryMnemonic,
    required this.vault,
  });

  final String publicKey;
  final Map<String, dynamic> keyBundle;
  final String recoveryMnemonic;
  final UnlockedVault vault;
}

class EncryptedPayload {
  const EncryptedPayload({required this.ciphertext, required this.nonce});

  final String ciphertext;
  final String nonce;

  Map<String, dynamic> toJson() => {'ciphertext': ciphertext, 'nonce': nonce};
}

class EncryptedCollectionDraft {
  EncryptedCollectionDraft({
    required this.collectionKey,
    required this.body,
  });

  final SecureKey collectionKey;
  final Map<String, dynamic> body;
}

class EncryptedMedia {
  EncryptedMedia({
    required this.ciphertext,
    required this.encryptionHeader,
    required this.encryptedMetadata,
    required this.metadataNonce,
    required this.encryptedFileKey,
    required this.fileKeyNonce,
    required this.sha256Hex,
    required this.originalSize,
    required this.encryptedSize,
  });

  final Uint8List ciphertext;
  final String encryptionHeader;
  final Map<String, dynamic> encryptedMetadata;
  final String metadataNonce;
  final String encryptedFileKey;
  final String? fileKeyNonce;
  final String sha256Hex;
  final int originalSize;
  final int encryptedSize;
}

class NoirCrypto {
  NoirCrypto(this.sodium);

  final SodiumSumo sodium;

  static Future<NoirCrypto> load() async =>
      NoirCrypto(await SodiumSumoInit.init());

  RegistrationCryptoBundle createRegistrationBundle(String password) {
    final masterKey = sodium.crypto.secretBox.keygen();
    final accountKeyPair = sodium.crypto.box.keyPair();
    final mnemonic = bip39.generateMnemonic(strength: 256);
    final recoveryKey = _recoveryKeyFromMnemonic(mnemonic);
    final salt = sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes);
    final opsLimit = sodium.crypto.pwhash.opsLimitModerate;
    final memLimit = sodium.crypto.pwhash.memLimitModerate;
    final passwordKey = derivePasswordKey(
        password: password, salt: salt, opsLimit: opsLimit, memLimit: memLimit);

    try {
      final wrappedMaster = wrapKey(masterKey, passwordKey);
      final wrappedPrivate =
          wrapBytes(accountKeyPair.secretKey.extractBytes(), masterKey);
      final recoveryWrappedMaster = wrapKey(masterKey, recoveryKey);
      final keyBundle = {
        'version': 1,
        'kdf': {
          'name': 'argon2id',
          'salt': b64(salt),
          'opsLimit': opsLimit,
          'memLimit': memLimit,
          'algorithm': 'argon2id13',
        },
        'encryptedMasterKey': wrappedMaster.toJson(),
        'encryptedPrivateKey': wrappedPrivate.toJson(),
        'recovery': {
          'type': 'bip39-256',
          'encryptedMasterKey': recoveryWrappedMaster.toJson(),
        },
      };
      return RegistrationCryptoBundle(
        publicKey: b64(accountKeyPair.publicKey),
        keyBundle: keyBundle,
        recoveryMnemonic: mnemonic,
        vault:
            UnlockedVault(masterKey: masterKey, accountKeyPair: accountKeyPair),
      );
    } finally {
      passwordKey.dispose();
      recoveryKey.dispose();
    }
  }

  SecureKey derivePasswordKey({
    required String password,
    required Uint8List salt,
    required int opsLimit,
    required int memLimit,
  }) {
    return sodium.crypto.pwhash(
      outLen: sodium.crypto.secretBox.keyBytes,
      password: Int8List.fromList(utf8.encode(password)),
      salt: salt,
      opsLimit: opsLimit,
      memLimit: memLimit,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  }

  UnlockedVault unlockFromPassword({
    required String password,
    required String publicKey,
    required Map<String, dynamic> keyBundle,
  }) {
    final kdf = keyBundle['kdf'] as Map<String, dynamic>;
    final passwordKey = derivePasswordKey(
      password: password,
      salt: unb64(kdf['salt'] as String),
      opsLimit: kdf['opsLimit'] as int,
      memLimit: kdf['memLimit'] as int,
    );
    try {
      final masterKey = unwrapKey(
          WrappedKey.fromJson(
              keyBundle['encryptedMasterKey'] as Map<String, dynamic>),
          passwordKey);
      final privateKeyBytes = unwrapBytes(
          WrappedKey.fromJson(
              keyBundle['encryptedPrivateKey'] as Map<String, dynamic>),
          masterKey);
      final privateKey = SecureKey.fromList(sodium, privateKeyBytes);
      return UnlockedVault(
        masterKey: masterKey,
        accountKeyPair:
            KeyPair(publicKey: unb64(publicKey), secretKey: privateKey),
      );
    } finally {
      passwordKey.dispose();
    }
  }

  Map<String, dynamic> rewrapForNewPassword({
    required UnlockedVault vault,
    required String newPassword,
    required String recoveryMnemonic,
  }) {
    final salt = sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes);
    final opsLimit = sodium.crypto.pwhash.opsLimitModerate;
    final memLimit = sodium.crypto.pwhash.memLimitModerate;
    final passwordKey = derivePasswordKey(
        password: newPassword,
        salt: salt,
        opsLimit: opsLimit,
        memLimit: memLimit);
    final recoveryKey = _recoveryKeyFromMnemonic(recoveryMnemonic);
    try {
      return {
        'version': 1,
        'kdf': {
          'name': 'argon2id',
          'salt': b64(salt),
          'opsLimit': opsLimit,
          'memLimit': memLimit,
          'algorithm': 'argon2id13',
        },
        'encryptedMasterKey': wrapKey(vault.masterKey, passwordKey).toJson(),
        'encryptedPrivateKey': wrapBytes(
                vault.accountKeyPair.secretKey.extractBytes(), vault.masterKey)
            .toJson(),
        'recovery': {
          'type': 'bip39-256',
          'encryptedMasterKey': wrapKey(vault.masterKey, recoveryKey).toJson(),
        },
      };
    } finally {
      passwordKey.dispose();
      recoveryKey.dispose();
    }
  }

  WrappedKey wrapKey(SecureKey keyToWrap, SecureKey wrappingKey) =>
      wrapBytes(keyToWrap.extractBytes(), wrappingKey);

  WrappedKey wrapBytes(Uint8List bytes, SecureKey wrappingKey) {
    final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
    final ciphertext = sodium.crypto.secretBox
        .easy(message: bytes, nonce: nonce, key: wrappingKey);
    return WrappedKey(ciphertext: b64(ciphertext), nonce: b64(nonce));
  }

  SecureKey unwrapKey(WrappedKey wrapped, SecureKey wrappingKey) {
    return SecureKey.fromList(sodium, unwrapBytes(wrapped, wrappingKey));
  }

  Uint8List unwrapBytes(WrappedKey wrapped, SecureKey wrappingKey) {
    return sodium.crypto.secretBox.openEasy(
      cipherText: unb64(wrapped.ciphertext),
      nonce: unb64(wrapped.nonce),
      key: wrappingKey,
    );
  }

  EncryptedPayload encryptJson(Object value, SecureKey key) {
    final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
    final message = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    final ciphertext =
        sodium.crypto.secretBox.easy(message: message, nonce: nonce, key: key);
    return EncryptedPayload(ciphertext: b64(ciphertext), nonce: b64(nonce));
  }

  dynamic decryptJson(EncryptedPayload payload, SecureKey key) {
    final clear = sodium.crypto.secretBox.openEasy(
      cipherText: unb64(payload.ciphertext),
      nonce: unb64(payload.nonce),
      key: key,
    );
    return jsonDecode(utf8.decode(clear));
  }

  EncryptedPayload encryptSearchIndexPayload(
    Map<String, dynamic> payload,
    UnlockedVault vault,
  ) =>
      encryptJson(payload, vault.masterKey);

  Map<String, dynamic> decryptSearchIndexPayload(
    EncryptedPayload payload,
    UnlockedVault vault,
  ) {
    final clear = decryptJson(payload, vault.masterKey);
    if (clear is Map<String, dynamic>) return clear;
    throw const FormatException('Search index payload must be a JSON object.');
  }

  EncryptedCollectionDraft createCollectionDraft({
    required String name,
    required UnlockedVault vault,
    String collectionType = 'album',
  }) {
    final collectionKey = sodium.crypto.secretBox.keygen();
    final encryptedName = encryptJson({'name': name}, collectionKey);
    final ownerWrappedKey = wrapKey(collectionKey, vault.masterKey);
    return EncryptedCollectionDraft(
      collectionKey: collectionKey,
      body: {
        'encrypted_name': encryptedName.ciphertext,
        'name_nonce': encryptedName.nonce,
        'encrypted_collection_key': ownerWrappedKey.ciphertext,
        'collection_key_nonce': ownerWrappedKey.nonce,
        'collection_type': collectionType,
        'encrypted_metadata': null,
      },
    );
  }

  SecureKey openCollectionKey(
      Map<String, dynamic> collection, UnlockedVault vault) {
    final ciphertext = collection['encrypted_collection_key'] as String;
    final nonce = collection['collection_key_nonce'] as String?;
    if (nonce == null || nonce.isEmpty) {
      final bytes = sodium.crypto.box.sealOpen(
        cipherText: unb64(ciphertext),
        publicKey: vault.accountKeyPair.publicKey,
        secretKey: vault.accountKeyPair.secretKey,
      );
      return SecureKey.fromList(sodium, bytes);
    }
    return unwrapKey(
        WrappedKey(ciphertext: ciphertext, nonce: nonce), vault.masterKey);
  }

  Map<String, dynamic> shareCollectionBody({
    required SecureKey collectionKey,
    required String recipientEmail,
    required String recipientPublicKey,
    String role = 'viewer',
  }) {
    final sealed = sodium.crypto.box.seal(
      message: collectionKey.extractBytes(),
      publicKey: unb64(recipientPublicKey),
    );
    return {
      'recipient_email': recipientEmail,
      'encrypted_collection_key': b64(sealed),
      'collection_key_nonce': null,
      'role': role,
    };
  }

  Future<EncryptedMedia> encryptMedia({
    required Uint8List bytes,
    required SecureKey collectionKey,
    required Map<String, dynamic> metadata,
  }) async {
    final fileKey = sodium.crypto.secretStream.keygen();
    try {
      final encryptedChunks = await sodium.crypto.secretStream
          .pushChunked(
            messageStream: Stream<List<int>>.value(bytes),
            key: fileKey,
            chunkSize: 64 * 1024,
          )
          .toList();
      final allBytes =
          Uint8List.fromList(encryptedChunks.expand((chunk) => chunk).toList());
      final headerBytes = sodium.crypto.secretStream.headerBytes;
      final header = Uint8List.fromList(allBytes.take(headerBytes).toList());
      final body = Uint8List.fromList(allBytes.skip(headerBytes).toList());
      final encryptedMetadata = encryptJson(metadata, collectionKey);
      final encryptedFileKey = wrapKey(fileKey, collectionKey);
      return EncryptedMedia(
        ciphertext: body,
        encryptionHeader: b64(header),
        encryptedMetadata: encryptedMetadata.toJson(),
        metadataNonce: encryptedMetadata.nonce,
        encryptedFileKey: encryptedFileKey.ciphertext,
        fileKeyNonce: encryptedFileKey.nonce,
        sha256Hex: dart_crypto.sha256.convert(body).toString(),
        originalSize: bytes.length,
        encryptedSize: body.length,
      );
    } finally {
      fileKey.dispose();
    }
  }

  Future<Uint8List> decryptMedia({
    required Uint8List ciphertext,
    required String encryptionHeader,
    required String encryptedFileKey,
    required String fileKeyNonce,
    required SecureKey collectionKey,
  }) async {
    final fileKey = unwrapKey(
        WrappedKey(ciphertext: encryptedFileKey, nonce: fileKeyNonce),
        collectionKey);
    try {
      final combined =
          Uint8List.fromList([...unb64(encryptionHeader), ...ciphertext]);
      final chunks = await sodium.crypto.secretStream
          .pullChunked(
            cipherStream: Stream<List<int>>.value(combined),
            key: fileKey,
            chunkSize: 64 * 1024,
          )
          .toList();
      return Uint8List.fromList(chunks.expand((chunk) => chunk).toList());
    } finally {
      fileKey.dispose();
    }
  }

  SecureKey _recoveryKeyFromMnemonic(String mnemonic) {
    final entropyHex = bip39.mnemonicToEntropy(mnemonic);
    return SecureKey.fromList(sodium, _hexToBytes(entropyHex));
  }

  Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
