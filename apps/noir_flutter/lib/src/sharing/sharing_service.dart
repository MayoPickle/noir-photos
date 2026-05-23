import 'package:sodium/sodium_sumo.dart';

import '../core/api_client.dart';
import '../crypto/noir_crypto.dart';

class SharingService {
  SharingService({required ApiClient api, required NoirCrypto crypto})
      : _api = api,
        _crypto = crypto;

  final ApiClient _api;
  final NoirCrypto _crypto;

  Future<void> shareCollection({
    required String collectionId,
    required SecureKey collectionKey,
    required String recipientEmail,
    String role = 'viewer',
  }) async {
    final recipient = await _api.lookupRecipient(recipientEmail);
    final body = _crypto.shareCollectionBody(
      collectionKey: collectionKey,
      recipientEmail: recipientEmail,
      recipientPublicKey: recipient['public_key'] as String,
      role: role,
    );
    await _api.shareCollection(collectionId, body);
  }
}
