import 'dart:async';
import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';

import '../core/api_client.dart';
import '../crypto/noir_crypto.dart';
import '../search/search_index_service.dart';
import 'gallery_constants.dart';

class GalleryController extends ChangeNotifier {
  GalleryController(
      {required ApiClient api,
      required NoirCrypto crypto,
      required UnlockedVault vault,
      SearchIndexService? searchIndex})
      : _api = api,
        _crypto = crypto,
        _vault = vault,
        _searchIndex = searchIndex;

  final ApiClient _api;
  final NoirCrypto _crypto;
  final UnlockedVault _vault;
  final SearchIndexService? _searchIndex;

  List<Map<String, dynamic>> collections = [];
  List<Map<String, dynamic>> files = [];
  List<Map<String, dynamic>> visibleFiles = [];
  Map<String, SecureKey> collectionKeys = {};
  bool busy = false;
  bool indexingSearch = false;
  int indexedFileCount = 0;
  String? selectedCollectionId;
  String? error;
  String searchQuery = '';

  Future<void> refresh() async {
    await _run(() async {
      final rows = await _api.collections();
      _setCollections(rows.cast<Map<String, dynamic>>());
      if (collections.isEmpty) {
        await _createDefaultLibrary();
      }
      _ensureSelectedCollection();
      await refreshFiles();
    });
  }

  Future<void> createAlbum(String name) async {
    await _run(() async {
      final draft = _crypto.createCollectionDraft(
        name: name,
        vault: _vault,
        collectionType: noirAlbumCollectionType,
      );
      final created = await _api.createCollection(draft.body);
      collections = libraryFirst([created, ...collections]);
      collectionKeys[created['id'] as String] = draft.collectionKey;
      selectedCollectionId = created['id'] as String;
      await refreshFiles();
    });
  }

  Future<void> selectCollection(String collectionId) async {
    selectedCollectionId = collectionId;
    notifyListeners();
    await refreshFiles();
  }

  Future<void> refreshFiles() async {
    final collectionId = selectedCollectionId;
    if (collectionId == null) {
      files = [];
      visibleFiles = [];
      notifyListeners();
      return;
    }
    final rows = await _api.files(collectionId);
    files = rows.cast<Map<String, dynamic>>();
    await _refreshSearchIndex(collectionId);
    await _applySearch();
    notifyListeners();
    _queueMissingIndexBuild(collectionId);
  }

  Future<void> uploadBytes({
    required Uint8List bytes,
    required String filename,
    String mimeType = 'application/octet-stream',
  }) async {
    final collectionId = selectedCollectionId;
    if (collectionId == null) {
      throw StateError('Select a library or album before uploading.');
    }
    final collectionKey = collectionKeys[collectionId];
    if (collectionKey == null) {
      throw StateError('Collection key is not unlocked.');
    }

    await _run(() async {
      final encrypted = await _crypto.encryptMedia(
        bytes: bytes,
        collectionKey: collectionKey,
        metadata: {
          'filename': filename,
          'mimeType': mimeType,
          'uploadedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      final session = await _api.uploadSession(
        collectionId: collectionId,
        objectType: 'original',
        sizeBytes: encrypted.ciphertext.length,
        checksum: encrypted.sha256Hex,
      );
      await _api.putEncryptedObject(
        uploadUrl: session['upload_url'] as String,
        bytes: encrypted.ciphertext,
        headers:
            (session['headers'] as Map<String, dynamic>).cast<String, String>(),
      );
      final committed = await _api.commitFile({
        'collection_id': collectionId,
        'encrypted_metadata': encrypted.encryptedMetadata,
        'metadata_nonce': encrypted.metadataNonce,
        'encrypted_file_key': encrypted.encryptedFileKey,
        'file_key_nonce': encrypted.fileKeyNonce,
        'ciphertext_hash':
            dart_crypto.sha256.convert(encrypted.ciphertext).toString(),
        'original_size': encrypted.originalSize,
        'encrypted_size': encrypted.encryptedSize,
        'objects': [
          {
            'upload_id': session['upload_id'],
            'object_type': 'original',
            'size_bytes': encrypted.ciphertext.length,
            'checksum': encrypted.sha256Hex,
            'encryption_header': encrypted.encryptionHeader,
          }
        ],
      });
      await _searchIndex?.indexUploadedMedia(
        bytes: bytes,
        filename: filename,
        fileId: committed['id'] as String,
        collectionId: collectionId,
      );
      await refreshFiles();
    });
  }

  Future<void> setSearchQuery(String query) async {
    searchQuery = query;
    await _applySearch();
    notifyListeners();
  }

  Future<void> _createDefaultLibrary() async {
    final draft = _crypto.createCollectionDraft(
      name: noirDefaultLibraryName,
      vault: _vault,
      collectionType: noirDefaultLibraryType,
    );
    final created = await _api.createCollection(draft.body);
    collections = libraryFirst([created]);
    collectionKeys = {created['id'] as String: draft.collectionKey};
    selectedCollectionId = created['id'] as String;
  }

  Future<void> _refreshSearchIndex(String collectionId) async {
    try {
      await _searchIndex?.syncRemoteIndexes(collectionId: collectionId);
      indexedFileCount = _searchIndex?.indexedCount ?? 0;
    } catch (_) {
      indexedFileCount = _searchIndex?.indexedCount ?? 0;
    }
  }

  Future<void> _applySearch() async {
    final query = searchQuery.trim();
    if (query.isEmpty || _searchIndex == null) {
      visibleFiles = List<Map<String, dynamic>>.from(files);
      return;
    }
    final matches = await _searchIndex.search(query);
    final byId = <String, Map<String, dynamic>>{};
    for (final file in files) {
      final id = file['id']?.toString();
      if (id != null) byId[id] = file;
    }
    visibleFiles = [
      for (final match in matches)
        if (byId[match.fileId] != null) byId[match.fileId]!,
    ];
  }

  void _queueMissingIndexBuild(String collectionId) {
    final searchIndex = _searchIndex;
    if (kIsWeb || searchIndex == null || indexingSearch) return;
    final hasMissing = files.any((file) {
      final id = file['id']?.toString();
      return id != null && !searchIndex.hasIndexFor(id);
    });
    if (!hasMissing) return;
    final collectionKey = collectionKeys[collectionId];
    if (collectionKey == null) return;
    unawaited(_buildMissingSearchIndexes(collectionKey));
  }

  Future<void> _buildMissingSearchIndexes(SecureKey collectionKey) async {
    indexingSearch = true;
    notifyListeners();
    try {
      await _searchIndex?.indexMissingFiles(
        files: files,
        collectionKey: collectionKey,
      );
      indexedFileCount = _searchIndex?.indexedCount ?? 0;
      await _applySearch();
    } finally {
      indexingSearch = false;
      notifyListeners();
    }
  }

  void _setCollections(List<Map<String, dynamic>> nextCollections) {
    collections = libraryFirst(nextCollections);
    collectionKeys = {
      for (final collection in collections)
        collection['id'] as String:
            _crypto.openCollectionKey(collection, _vault),
    };
  }

  void _ensureSelectedCollection() {
    if (collections.isEmpty) {
      selectedCollectionId = null;
      return;
    }
    final selectedStillExists = collections.any(
      (collection) => collection['id'] == selectedCollectionId,
    );
    if (!selectedStillExists) {
      selectedCollectionId = collections.first['id'] as String;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (err) {
      error = err.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
