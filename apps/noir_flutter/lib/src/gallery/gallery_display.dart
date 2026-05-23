import 'package:sodium/sodium_sumo.dart';

import '../crypto/noir_crypto.dart';
import 'gallery_constants.dart';

class CollectionDisplay {
  const CollectionDisplay({
    required this.id,
    required this.title,
    required this.role,
    required this.memberCount,
    required this.isShared,
    required this.isLibrary,
    required this.canShare,
    this.visibleFileCount,
  });

  final String id;
  final String title;
  final String role;
  final int memberCount;
  final bool isShared;
  final bool isLibrary;
  final bool canShare;
  final int? visibleFileCount;
}

class FileDisplay {
  const FileDisplay({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.sizeLabel,
    required this.hashPrefix,
    required this.paletteIndex,
  });

  final String id;
  final String title;
  final String subtitle;
  final String sizeLabel;
  final String hashPrefix;
  final int paletteIndex;
}

CollectionDisplay collectionDisplayFor({
  required Map<String, dynamic> collection,
  required Map<String, SecureKey> collectionKeys,
  required NoirCrypto crypto,
  int? visibleFileCount,
}) {
  final id = collection['id']?.toString() ?? '';
  final members = collection['members'] as List<dynamic>? ?? const [];
  final role = collection['role']?.toString() ?? 'viewer';
  final isLibrary = isLibraryCollection(collection);
  final key = collectionKeys[id];
  var title = isLibrary ? noirDefaultLibraryName : 'Encrypted album';

  if (key != null) {
    title = _decryptCollectionName(collection, key, crypto) ?? title;
  }

  return CollectionDisplay(
    id: id,
    title: title,
    role: _titleCase(role),
    memberCount: members.length,
    isShared: !isLibrary && (role != 'owner' || members.length > 1),
    isLibrary: isLibrary,
    canShare: !isLibrary && role == 'owner',
    visibleFileCount: visibleFileCount,
  );
}

FileDisplay fileDisplayFor({
  required Map<String, dynamic> file,
  required SecureKey? collectionKey,
  required NoirCrypto crypto,
  required int index,
}) {
  final hash = file['ciphertext_hash']?.toString() ?? '';
  final encryptedSize = file['encrypted_size'] as int?;
  final originalSize = file['original_size'] as int?;
  final metadata = collectionKey == null
      ? null
      : _decryptFileMetadata(file, collectionKey, crypto);
  final filename = metadata?['filename']?.toString();
  final uploadedAt = metadata?['uploadedAt']?.toString();

  return FileDisplay(
    id: file['id']?.toString() ?? 'file-$index',
    title: filename == null || filename.trim().isEmpty
        ? 'Encrypted file ${index + 1}'
        : filename,
    subtitle: _formatUploadedAt(uploadedAt),
    sizeLabel: _formatBytes(originalSize ?? encryptedSize),
    hashPrefix: hash.length >= 12 ? hash.substring(0, 12) : hash,
    paletteIndex: _paletteSeed(hash, index),
  );
}

String formatCount(int count, String singular, String plural) {
  return '$count ${count == 1 ? singular : plural}';
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String? _decryptCollectionName(
    Map<String, dynamic> collection, SecureKey key, NoirCrypto crypto) {
  try {
    final payload = EncryptedPayload(
      ciphertext: collection['encrypted_name'] as String,
      nonce: collection['name_nonce'] as String,
    );
    final clear = crypto.decryptJson(payload, key);
    if (clear is Map<String, dynamic>) {
      final name = clear['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, dynamic>? _decryptFileMetadata(
    Map<String, dynamic> file, SecureKey key, NoirCrypto crypto) {
  try {
    final encryptedMetadata =
        file['encrypted_metadata'] as Map<String, dynamic>;
    final payload = EncryptedPayload(
      ciphertext: encryptedMetadata['ciphertext'] as String,
      nonce: (file['metadata_nonce'] ?? encryptedMetadata['nonce']) as String,
    );
    final clear = crypto.decryptJson(payload, key);
    if (clear is Map<String, dynamic>) return clear;
  } catch (_) {
    return null;
  }
  return null;
}

String _formatUploadedAt(String? value) {
  if (value == null || value.isEmpty) return 'Encrypted metadata';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return 'Encrypted metadata';
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return 'Uploaded ${local.year}-$month-$day';
}

String _formatBytes(int? bytes) {
  if (bytes == null) return 'Unknown size';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value = value / 1024;
    unit += 1;
  }
  final precision = unit == 0 || value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unit]}';
}

int _paletteSeed(String hash, int fallback) {
  if (hash.isEmpty) return fallback;
  return hash.codeUnits.fold<int>(0, (value, code) => value + code) + fallback;
}
