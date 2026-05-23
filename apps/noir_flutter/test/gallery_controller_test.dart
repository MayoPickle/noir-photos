import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noir_flutter/src/core/api_client.dart';
import 'package:noir_flutter/src/core/secure_store.dart';
import 'package:noir_flutter/src/crypto/noir_crypto.dart';
import 'package:noir_flutter/src/gallery/gallery_constants.dart';
import 'package:noir_flutter/src/gallery/gallery_controller.dart';
import 'package:noir_flutter/src/gallery/gallery_display.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoirCrypto crypto;
  late UnlockedVault vault;

  setUpAll(() async {
    crypto = await NoirCrypto.load();
    vault = crypto.createRegistrationBundle('gallery password').vault;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('creates and selects a default Library for empty accounts', () async {
    final createdBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/collections') {
        return http.Response(jsonEncode([]), 200);
      }
      if (request.method == 'POST' && request.url.path == '/collections') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        createdBodies.add(body);
        return http.Response(
          jsonEncode(_collectionFromBody(id: 'library-id', body: body)),
          201,
        );
      }
      if (request.method == 'GET' && request.url.path == '/files') {
        expect(request.url.queryParameters['collection_id'], 'library-id');
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('not found', 404);
    });
    final controller = _controller(client, crypto, vault);

    await controller.refresh();

    expect(createdBodies, hasLength(1));
    expect(createdBodies.single['collection_type'], noirDefaultLibraryType);
    expect(controller.collections, hasLength(1));
    expect(controller.collections.single['id'], 'library-id');
    expect(controller.selectedCollectionId, 'library-id');
    expect(controller.collectionKeys, contains('library-id'));

    final clear = crypto.decryptJson(
      EncryptedPayload(
        ciphertext: createdBodies.single['encrypted_name'] as String,
        nonce: createdBodies.single['name_nonce'] as String,
      ),
      controller.collectionKeys['library-id']!,
    ) as Map<String, dynamic>;
    expect(clear['name'], noirDefaultLibraryName);
  });

  test('keeps existing collections and sorts Library first', () async {
    final albumDraft = crypto.createCollectionDraft(
      name: 'Trips',
      vault: vault,
      collectionType: noirAlbumCollectionType,
    );
    final libraryDraft = crypto.createCollectionDraft(
      name: noirDefaultLibraryName,
      vault: vault,
      collectionType: noirDefaultLibraryType,
    );
    final createdBodies = <Map<String, dynamic>>[];
    final existingCollections = [
      _collectionFromBody(id: 'album-id', body: albumDraft.body),
      _collectionFromBody(id: 'library-id', body: libraryDraft.body),
    ];
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/collections') {
        return http.Response(jsonEncode(existingCollections), 200);
      }
      if (request.method == 'POST' && request.url.path == '/collections') {
        createdBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('unexpected create', 500);
      }
      if (request.method == 'GET' && request.url.path == '/files') {
        expect(request.url.queryParameters['collection_id'], 'library-id');
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('not found', 404);
    });
    final controller = _controller(client, crypto, vault);

    await controller.refresh();

    expect(createdBodies, isEmpty);
    expect(controller.collections.first['id'], 'library-id');
    expect(controller.selectedCollectionId, 'library-id');

    final display = collectionDisplayFor(
      collection: controller.collections.first,
      collectionKeys: controller.collectionKeys,
      crypto: crypto,
    );
    expect(display.title, noirDefaultLibraryName);
    expect(display.isLibrary, isTrue);
    expect(display.isShared, isFalse);
    expect(display.canShare, isFalse);
  });

  test('creates user albums as shareable album collections', () async {
    final createdBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/collections') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        createdBodies.add(body);
        return http.Response(
          jsonEncode(_collectionFromBody(id: 'album-id', body: body)),
          201,
        );
      }
      if (request.method == 'GET' && request.url.path == '/files') {
        expect(request.url.queryParameters['collection_id'], 'album-id');
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('not found', 404);
    });
    final controller = _controller(client, crypto, vault);

    await controller.createAlbum('Family');

    expect(createdBodies, hasLength(1));
    expect(createdBodies.single['collection_type'], noirAlbumCollectionType);
    expect(controller.selectedCollectionId, 'album-id');

    final display = collectionDisplayFor(
      collection: controller.collections.single,
      collectionKeys: controller.collectionKeys,
      crypto: crypto,
    );
    expect(display.title, 'Family');
    expect(display.isLibrary, isFalse);
    expect(display.canShare, isTrue);
  });
}

GalleryController _controller(
  http.Client client,
  NoirCrypto crypto,
  UnlockedVault vault,
) {
  return GalleryController(
    api: ApiClient(
      baseUrl: 'http://noir.test',
      store: SecureStore(),
      httpClient: client,
    ),
    crypto: crypto,
    vault: vault,
  );
}

Map<String, dynamic> _collectionFromBody({
  required String id,
  required Map<String, dynamic> body,
}) {
  return {
    'id': id,
    'owner_id': 'owner-id',
    'encrypted_name': body['encrypted_name'],
    'name_nonce': body['name_nonce'],
    'collection_type': body['collection_type'],
    'encrypted_metadata': body['encrypted_metadata'],
    'role': 'owner',
    'encrypted_collection_key': body['encrypted_collection_key'],
    'collection_key_nonce': body['collection_key_nonce'],
    'members': const [],
  };
}
