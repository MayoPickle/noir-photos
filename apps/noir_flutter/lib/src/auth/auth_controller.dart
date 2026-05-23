import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';

import '../core/api_client.dart';
import '../core/secure_store.dart';
import '../crypto/noir_crypto.dart';

class AuthController extends ChangeNotifier {
  AuthController(
      {required ApiClient api,
      required NoirCrypto crypto,
      required SecureStore store})
      : _api = api,
        _crypto = crypto,
        _store = store;

  final ApiClient _api;
  final NoirCrypto _crypto;
  final SecureStore _store;

  Map<String, dynamic>? user;
  UnlockedVault? vault;
  String? recoveryMnemonic;
  bool busy = false;
  String? error;

  bool get signedIn => user != null && vault != null;

  Future<void> restore() async {
    final storedUser = await _store.readUser();
    final storedVault = await _store.readVault();
    if (storedUser == null || storedVault == null) return;
    user = storedUser;
    vault = UnlockedVault(
      masterKey: SecureKey.fromList(
          _crypto.sodium, unb64(storedVault['masterKey'] as String)),
      accountKeyPair: KeyPair(
        publicKey: unb64(storedVault['publicKey'] as String),
        secretKey: SecureKey.fromList(
            _crypto.sodium, unb64(storedVault['privateKey'] as String)),
      ),
    );
    notifyListeners();
  }

  Future<void> startOtp(String email, String purpose) async {
    await _run(() => _api.startOtp(email, purpose));
  }

  Future<void> register(
      {required String email,
      required String otp,
      required String password}) async {
    await _run(() async {
      final bundle = _crypto.createRegistrationBundle(password);
      final response = await _api.register(
        email: email,
        otp: otp,
        publicKey: bundle.publicKey,
        keyBundle: bundle.keyBundle,
        device: _device(),
      );
      recoveryMnemonic = bundle.recoveryMnemonic;
      user = response['user'] as Map<String, dynamic>;
      vault = bundle.vault;
      await _store.saveSession(
          token: response['access_token'] as String, user: user!);
      await _store.saveVault(vault!.toLocalJson());
    });
  }

  Future<void> login(
      {required String email,
      required String otp,
      required String password}) async {
    await _run(() async {
      final response =
          await _api.login(email: email, otp: otp, device: _device());
      final signedUser = response['user'] as Map<String, dynamic>;
      final unlocked = _crypto.unlockFromPassword(
        password: password,
        publicKey: signedUser['public_key'] as String,
        keyBundle: signedUser['key_bundle'] as Map<String, dynamic>,
      );
      user = signedUser;
      vault = unlocked;
      await _store.saveSession(
          token: response['access_token'] as String, user: user!);
      await _store.saveVault(vault!.toLocalJson());
    });
  }

  Future<void> changePassword(String newPassword, String recoveryPhrase) async {
    final unlocked = vault;
    if (unlocked == null) return;
    await _run(() async {
      final keyBundle = _crypto.rewrapForNewPassword(
        vault: unlocked,
        newPassword: newPassword,
        recoveryMnemonic: recoveryPhrase,
      );
      await _api.changePassword(keyBundle);
      user = {...user!, 'key_bundle': keyBundle};
      await _store.saveSession(token: (await _store.readToken())!, user: user!);
    });
  }

  Future<void> deleteAccount() async {
    await _run(() async {
      await _api.deleteAccount();
      await signOut(localOnly: true);
    });
  }

  Future<void> signOut({bool localOnly = false}) async {
    vault?.dispose();
    vault = null;
    user = null;
    recoveryMnemonic = null;
    await _store.clear();
    notifyListeners();
  }

  Map<String, dynamic> _device() {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    return {
      'name': 'Noir Photos $platform',
      'platform': platform,
      'app_version': '0.1.0'
    };
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
