import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../core/api_client.dart';
import '../core/secure_store.dart';
import '../crypto/noir_crypto.dart';

const noirSearchModelVersion = 'mobileclip-s0-local-v1';

class SearchPerson {
  const SearchPerson({
    required this.clusterId,
    this.name,
    this.embedding = const [],
    this.faceBoxes = const [],
  });

  final String clusterId;
  final String? name;
  final List<double> embedding;
  final List<Map<String, dynamic>> faceBoxes;

  Map<String, dynamic> toJson() => {
        'clusterId': clusterId,
        if (name != null) 'name': name,
        'embedding': embedding,
        'faceBoxes': faceBoxes,
      };

  static SearchPerson fromJson(Map<String, dynamic> json) => SearchPerson(
        clusterId: json['clusterId']?.toString() ?? '',
        name: json['name']?.toString(),
        embedding: _doubleList(json['embedding']),
        faceBoxes: [
          for (final box in json['faceBoxes'] as List<dynamic>? ?? const [])
            if (box is Map<String, dynamic>) box
        ],
      );
}

class SearchImageAnalysis {
  const SearchImageAnalysis({
    required this.imageEmbedding,
    this.labels = const [],
    this.people = const [],
  });

  final List<double> imageEmbedding;
  final List<String> labels;
  final List<SearchPerson> people;
}

class SearchIndexEntry {
  const SearchIndexEntry({
    required this.fileId,
    required this.collectionId,
    required this.modelVersion,
    required this.imageEmbedding,
    required this.indexedAt,
    this.labels = const [],
    this.people = const [],
  });

  final String fileId;
  final String collectionId;
  final String modelVersion;
  final List<double> imageEmbedding;
  final List<String> labels;
  final List<SearchPerson> people;
  final DateTime indexedAt;

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'fileId': fileId,
        'collectionId': collectionId,
        'modelVersion': modelVersion,
        'imageEmbedding': imageEmbedding,
        'labels': labels,
        'people': [for (final person in people) person.toJson()],
        'indexedAt': indexedAt.toUtc().toIso8601String(),
      };

  static SearchIndexEntry fromJson(Map<String, dynamic> json) =>
      SearchIndexEntry(
        fileId: json['fileId'] as String,
        collectionId: json['collectionId'] as String,
        modelVersion: json['modelVersion'] as String,
        imageEmbedding: _doubleList(json['imageEmbedding']),
        labels: [
          for (final label in json['labels'] as List<dynamic>? ?? const [])
            label.toString(),
        ],
        people: [
          for (final person in json['people'] as List<dynamic>? ?? const [])
            if (person is Map<String, dynamic>) SearchPerson.fromJson(person),
        ],
        indexedAt: DateTime.tryParse(json['indexedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

class SearchMatch {
  const SearchMatch({
    required this.fileId,
    required this.score,
    required this.reason,
  });

  final String fileId;
  final double score;
  final String reason;
}

abstract class SearchEmbeddingEngine {
  String get modelVersion;

  Future<SearchImageAnalysis> analyzeImage({
    required Uint8List bytes,
    required String filename,
  });

  Future<List<double>> embedText(String query);
}

class DeterministicSearchEmbeddingEngine implements SearchEmbeddingEngine {
  const DeterministicSearchEmbeddingEngine({this.dimensions = 48});

  final int dimensions;

  @override
  String get modelVersion => noirSearchModelVersion;

  @override
  Future<SearchImageAnalysis> analyzeImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final text =
        '$filename ${utf8.decode(bytes.take(4096).toList(), allowMalformed: true)}';
    final tokens = _tokens(text);
    return SearchImageAnalysis(
      imageEmbedding: _embedding(tokens),
      labels: tokens.take(16).toList(),
      people: _peopleFromText(text),
    );
  }

  @override
  Future<List<double>> embedText(String query) async =>
      _embedding(_tokens(query));

  List<double> _embedding(List<String> tokens) {
    final vector = List<double>.filled(dimensions, 0);
    for (final token in tokens) {
      final hash = _hash(token);
      final index = hash.abs() % dimensions;
      final sign = hash.isEven ? 1.0 : -1.0;
      vector[index] += sign;
    }
    return _normalise(vector);
  }

  List<SearchPerson> _peopleFromText(String text) {
    final lower = text.toLowerCase();
    final people = <SearchPerson>[];
    final pattern = RegExp(r'person[:_-]([a-z0-9]+)');
    for (final match in pattern.allMatches(lower)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) continue;
      people.add(
        SearchPerson(
          clusterId: 'person-$name',
          name: name,
          embedding: _embedding([name]),
        ),
      );
    }
    return people;
  }

  List<String> _tokens(String value) {
    final lower = value.toLowerCase();
    final tokens = <String>[];
    for (final match in RegExp(r'[a-z0-9]+').allMatches(lower)) {
      _addCanonical(tokens, match.group(0)!);
    }
    if (lower.contains('汽车') || lower.contains('车')) tokens.add('car');
    if (lower.contains('海边') || lower.contains('海')) tokens.add('ocean');
    if (lower.contains('红色') || lower.contains('红')) tokens.add('red');
    if (lower.contains('人物') || lower.contains('人脸')) tokens.add('person');
    return tokens.toSet().toList(growable: false);
  }

  void _addCanonical(List<String> tokens, String token) {
    const synonyms = {
      'auto': 'car',
      'automobile': 'car',
      'vehicle': 'car',
      'truck': 'car',
      'beach': 'ocean',
      'sea': 'ocean',
      'coast': 'ocean',
      'shore': 'ocean',
      'face': 'person',
      'human': 'person',
      'people': 'person',
    };
    tokens.add(synonyms[token] ?? token);
  }
}

class SearchIndexService {
  SearchIndexService({
    required NoirCrypto crypto,
    required UnlockedVault vault,
    required SecureStore store,
    ApiClient? api,
    SearchEmbeddingEngine? embeddingEngine,
    this.enabled = true,
  })  : _crypto = crypto,
        _vault = vault,
        _store = store,
        _api = api,
        _embeddingEngine =
            embeddingEngine ?? const DeterministicSearchEmbeddingEngine();

  final NoirCrypto _crypto;
  final UnlockedVault _vault;
  final SecureStore _store;
  final ApiClient? _api;
  final SearchEmbeddingEngine _embeddingEngine;
  final bool enabled;

  final Map<String, SearchIndexEntry> _entries = {};
  final Map<String, Map<String, dynamic>> _encryptedRows = {};

  String get modelVersion => _embeddingEngine.modelVersion;

  int get indexedCount => _entries.length;

  bool hasIndexFor(String fileId) =>
      _entries.containsKey(_entryKey(fileId, modelVersion));

  Future<void> syncRemoteIndexes({String? collectionId}) async {
    if (!enabled) return;
    await _loadLocalCache();
    if (_api == null) return;
    final rows = await _api.searchIndexes(
        collectionId: collectionId, modelVersion: modelVersion);
    if (collectionId == null) {
      _encryptedRows
          .removeWhere((_, row) => row['model_version'] == modelVersion);
    } else {
      _encryptedRows.removeWhere(
        (_, row) =>
            row['model_version'] == modelVersion &&
            row['collection_id'] == collectionId,
      );
    }
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        _encryptedRows[_rowKey(row)] = row;
      }
    }
    _loadEntriesFromRows(_encryptedRows.values);
    await _saveLocalCache();
  }

  Future<SearchIndexEntry?> indexUploadedMedia({
    required Uint8List bytes,
    required String filename,
    required String fileId,
    required String collectionId,
  }) async {
    if (!enabled) return null;
    final analysis =
        await _embeddingEngine.analyzeImage(bytes: bytes, filename: filename);
    final entry = SearchIndexEntry(
      fileId: fileId,
      collectionId: collectionId,
      modelVersion: modelVersion,
      imageEmbedding: analysis.imageEmbedding,
      labels: analysis.labels,
      people: analysis.people,
      indexedAt: DateTime.now().toUtc(),
    );
    await _storeEntry(entry);
    return entry;
  }

  Future<int> indexMissingFiles({
    required List<Map<String, dynamic>> files,
    required SecureKey collectionKey,
  }) async {
    if (!enabled || _api == null) return 0;
    var indexed = 0;
    for (final file in files) {
      final fileId = file['id']?.toString();
      if (fileId == null || hasIndexFor(fileId)) continue;
      try {
        final downloadable = await _api.downloadFile(fileId);
        final objects = downloadable['objects'] as List<dynamic>? ?? const [];
        final original = objects.cast<Map<String, dynamic>?>().firstWhere(
              (obj) =>
                  obj?['object_type'] == 'original' &&
                  obj?['download_url'] != null,
              orElse: () => null,
            );
        if (original == null) continue;
        final encryptedBytes =
            await _api.getEncryptedObject(original['download_url'] as String);
        final fileKeyNonce = downloadable['file_key_nonce']?.toString();
        if (fileKeyNonce == null || fileKeyNonce.isEmpty) continue;
        final clear = await _crypto.decryptMedia(
          ciphertext: encryptedBytes,
          encryptionHeader: original['encryption_header'] as String,
          encryptedFileKey: downloadable['encrypted_file_key'] as String,
          fileKeyNonce: fileKeyNonce,
          collectionKey: collectionKey,
        );
        await indexUploadedMedia(
          bytes: clear,
          filename:
              _filenameFromMetadata(downloadable, collectionKey) ?? fileId,
          fileId: fileId,
          collectionId: downloadable['collection_id'] as String,
        );
        indexed += 1;
      } catch (_) {
        continue;
      }
    }
    return indexed;
  }

  Future<List<SearchMatch>> search(String query) async {
    if (!enabled || query.trim().isEmpty) return const [];
    final queryEmbedding = await _embeddingEngine.embedText(query);
    final queryTokens = _queryTokens(query);
    final matches = <SearchMatch>[];
    for (final entry in _entries.values) {
      if (entry.modelVersion != modelVersion) continue;
      var score = _cosine(queryEmbedding, entry.imageEmbedding);
      var reason = 'visual';

      for (final label in entry.labels) {
        if (queryTokens.contains(label.toLowerCase())) {
          if (score < 0.92) {
            score = 0.92;
            reason = 'label';
          }
        }
      }
      for (final person in entry.people) {
        final name = person.name?.toLowerCase();
        if (name != null &&
            name.isNotEmpty &&
            query.toLowerCase().contains(name)) {
          score = 1.2;
          reason = 'person';
        }
      }
      if (score > 0.05) {
        matches.add(
            SearchMatch(fileId: entry.fileId, score: score, reason: reason));
      }
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  Future<void> _storeEntry(SearchIndexEntry entry) async {
    final encrypted = _crypto.encryptSearchIndexPayload(entry.toJson(), _vault);
    final body = {
      'file_id': entry.fileId,
      'collection_id': entry.collectionId,
      'model_version': entry.modelVersion,
      'encrypted_payload': encrypted.ciphertext,
      'payload_nonce': encrypted.nonce,
    };
    final row = _api == null
        ? {
            'id': 'local-${entry.fileId}-${entry.modelVersion}',
            'user_id': 'local',
            ...body,
            'created_at': entry.indexedAt.toIso8601String(),
            'updated_at': entry.indexedAt.toIso8601String(),
          }
        : await _api.upsertSearchIndex(body);
    _encryptedRows[_rowKey(row)] = row;
    _entries[_entryKey(entry.fileId, entry.modelVersion)] = entry;
    await _saveLocalCache();
  }

  Future<void> _loadLocalCache() async {
    final raw = await _store.readString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    final rows = jsonDecode(raw) as List<dynamic>;
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        _encryptedRows[_rowKey(row)] = row;
      }
    }
    _loadEntriesFromRows(_encryptedRows.values);
  }

  Future<void> _saveLocalCache() async {
    await _store.writeString(
      _cacheKey,
      jsonEncode(_encryptedRows.values.toList()),
    );
  }

  void _loadEntriesFromRows(Iterable<Map<String, dynamic>> rows) {
    _entries.clear();
    for (final row in rows) {
      if (row['model_version'] != modelVersion) continue;
      try {
        final clear = _crypto.decryptSearchIndexPayload(
          EncryptedPayload(
            ciphertext: row['encrypted_payload'] as String,
            nonce: row['payload_nonce'] as String,
          ),
          _vault,
        );
        final entry = SearchIndexEntry.fromJson(clear);
        _entries[_entryKey(entry.fileId, entry.modelVersion)] = entry;
      } catch (_) {
        continue;
      }
    }
  }

  String? _filenameFromMetadata(
      Map<String, dynamic> file, SecureKey collectionKey) {
    try {
      final encryptedMetadata =
          file['encrypted_metadata'] as Map<String, dynamic>;
      final clear = _crypto.decryptJson(
        EncryptedPayload(
          ciphertext: encryptedMetadata['ciphertext'] as String,
          nonce:
              (file['metadata_nonce'] ?? encryptedMetadata['nonce']) as String,
        ),
        collectionKey,
      );
      if (clear is Map<String, dynamic>) return clear['filename']?.toString();
    } catch (_) {
      return null;
    }
    return null;
  }

  String get _cacheKey => 'noir.searchIndex.cache.$modelVersion';

  String _rowKey(Map<String, dynamic> row) =>
      _entryKey(row['file_id'] as String, row['model_version'] as String);

  String _entryKey(String fileId, String modelVersion) =>
      '$fileId::$modelVersion';

  List<String> _queryTokens(String query) =>
      const DeterministicSearchEmbeddingEngine()._tokens(query);
}

List<double> _doubleList(Object? value) => [
      for (final item in value as List<dynamic>? ?? const [])
        if (item is num) item.toDouble(),
    ];

List<double> _normalise(List<double> vector) {
  final magnitude =
      math.sqrt(vector.fold<double>(0, (sum, value) => sum + value * value));
  if (magnitude == 0) return vector;
  return [for (final value in vector) value / magnitude];
}

double _cosine(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final length = math.min(a.length, b.length);
  var dot = 0.0;
  var aMagnitude = 0.0;
  var bMagnitude = 0.0;
  for (var i = 0; i < length; i++) {
    dot += a[i] * b[i];
    aMagnitude += a[i] * a[i];
    bMagnitude += b[i] * b[i];
  }
  if (aMagnitude == 0 || bMagnitude == 0) return 0;
  return dot / (math.sqrt(aMagnitude) * math.sqrt(bMagnitude));
}

int _hash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
