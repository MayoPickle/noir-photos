import '../core/secure_store.dart';
import '../gallery/gallery_controller.dart';

class BackupService {
  BackupService(
      {required SecureStore store, required GalleryController gallery});

  static Future<void> initialize({required String apiBaseUrl}) async {}

  Future<int> backupMobileLibrary({int limit = 250}) async => 0;
}
