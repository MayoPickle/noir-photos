import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:workmanager/workmanager.dart';

import '../auth/auth_controller.dart';
import '../core/api_client.dart';
import '../core/secure_store.dart';
import '../crypto/noir_crypto.dart';
import '../gallery/gallery_controller.dart';

const noirBackupTask = 'noir.photos.backup';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final crypto = await NoirCrypto.load();
    final store = SecureStore();
    final api = ApiClient(
      baseUrl: inputData?['baseUrl'] as String? ?? 'http://localhost:8000',
      store: store,
    );
    final auth = AuthController(api: api, crypto: crypto, store: store);
    await auth.restore();
    final vault = auth.vault;
    if (vault == null) return true;
    final gallery = GalleryController(api: api, crypto: crypto, vault: vault);
    await gallery.refresh();
    final backup = BackupService(store: store, gallery: gallery);
    await backup.backupMobileLibrary(limit: 50);
    return true;
  });
}

class BackupService {
  BackupService(
      {required SecureStore store, required GalleryController gallery})
      : _store = store,
        _gallery = gallery;

  final SecureStore _store;
  final GalleryController _gallery;

  static Future<void> initialize({required String apiBaseUrl}) async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      noirBackupTask,
      noirBackupTask,
      frequency: const Duration(hours: 6),
      constraints: Constraints(networkType: NetworkType.unmetered),
      inputData: {'baseUrl': apiBaseUrl},
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  Future<int> backupMobileLibrary({int limit = 250}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      await PhotoManager.openSetting();
      return 0;
    }
    final uploaded = await _uploadedAssetIds();
    final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common, onlyAll: true);
    if (paths.isEmpty) return 0;
    final assets = await paths.first.getAssetListPaged(page: 0, size: limit);
    var count = 0;
    for (final asset in assets) {
      if (uploaded.contains(asset.id)) continue;
      final bytes = await _assetBytes(asset);
      if (bytes == null || bytes.isEmpty) continue;
      await _gallery.uploadBytes(
        bytes: bytes,
        filename: asset.title ?? '${asset.id}.bin',
        mimeType: asset.mimeType ?? 'application/octet-stream',
      );
      uploaded.add(asset.id);
      count++;
    }
    await _saveUploadedAssetIds(uploaded);
    return count;
  }

  Future<Uint8List?> _assetBytes(AssetEntity asset) async {
    if (asset.type == AssetType.video) {
      final file = await asset.originFile;
      return file?.readAsBytes();
    }
    return asset.originBytes;
  }

  Future<Set<String>> _uploadedAssetIds() async {
    final raw = await _store.readString('noir.backup.uploadedAssetIds');
    if (raw == null) return <String>{};
    return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
  }

  Future<void> _saveUploadedAssetIds(Set<String> ids) async {
    await _store.writeString(
        'noir.backup.uploadedAssetIds', jsonEncode(ids.toList()..sort()));
  }
}
