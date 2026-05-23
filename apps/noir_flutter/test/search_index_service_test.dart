import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noir_flutter/src/core/secure_store.dart';
import 'package:noir_flutter/src/crypto/noir_crypto.dart';
import 'package:noir_flutter/src/search/search_index_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoirCrypto crypto;
  late UnlockedVault vault;

  setUpAll(() async {
    crypto = await NoirCrypto.load();
    vault = crypto.createRegistrationBundle('search password').vault;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('ranks semantic object queries and named people locally', () async {
    final service = SearchIndexService(
      crypto: crypto,
      vault: vault,
      store: SecureStore(),
      embeddingEngine: const _FakeEmbeddingEngine(),
    );

    await service.indexUploadedMedia(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'red-car.jpg',
      fileId: 'car-file',
      collectionId: 'collection-id',
    );
    await service.indexUploadedMedia(
      bytes: Uint8List.fromList([4, 5, 6]),
      filename: 'alice-portrait.jpg',
      fileId: 'alice-file',
      collectionId: 'collection-id',
    );

    final carMatches = await service.search('汽车');
    expect(carMatches.first.fileId, 'car-file');

    final personMatches = await service.search('Alice');
    expect(personMatches.first.fileId, 'alice-file');
    expect(personMatches.first.reason, 'person');
  });

  test(
      'loads encrypted local cache and treats model version changes as rebuilds',
      () async {
    final store = SecureStore();
    final firstDevice = SearchIndexService(
      crypto: crypto,
      vault: vault,
      store: store,
      embeddingEngine: const _FakeEmbeddingEngine(modelVersion: 'fake-v1'),
    );
    await firstDevice.indexUploadedMedia(
      bytes: Uint8List.fromList([7, 8, 9]),
      filename: 'red-car.jpg',
      fileId: 'car-file',
      collectionId: 'collection-id',
    );

    final secondDevice = SearchIndexService(
      crypto: crypto,
      vault: vault,
      store: store,
      embeddingEngine: const _FakeEmbeddingEngine(modelVersion: 'fake-v1'),
    );
    await secondDevice.syncRemoteIndexes();
    expect((await secondDevice.search('car')).single.fileId, 'car-file');

    final upgradedModel = SearchIndexService(
      crypto: crypto,
      vault: vault,
      store: store,
      embeddingEngine: const _FakeEmbeddingEngine(modelVersion: 'fake-v2'),
    );
    await upgradedModel.syncRemoteIndexes();
    expect(upgradedModel.hasIndexFor('car-file'), isFalse);
    expect(await upgradedModel.search('car'), isEmpty);
  });
}

class _FakeEmbeddingEngine implements SearchEmbeddingEngine {
  const _FakeEmbeddingEngine({this.modelVersion = 'fake-v1'});

  @override
  final String modelVersion;

  @override
  Future<SearchImageAnalysis> analyzeImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final lower = filename.toLowerCase();
    if (lower.contains('alice')) {
      return const SearchImageAnalysis(
        imageEmbedding: [1, 0],
        labels: ['person'],
        people: [
          SearchPerson(
            clusterId: 'person-alice',
            name: 'alice',
            embedding: [1, 0],
          )
        ],
      );
    }
    return const SearchImageAnalysis(
      imageEmbedding: [0, 1],
      labels: ['car', 'red'],
    );
  }

  @override
  Future<List<double>> embedText(String query) async {
    final lower = query.toLowerCase();
    if (lower.contains('alice')) return const [1, 0];
    if (lower.contains('car') || lower.contains('汽车')) return const [0, 1];
    return const [0, 0];
  }
}
