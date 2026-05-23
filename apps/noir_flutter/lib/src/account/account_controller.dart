import 'package:flutter/foundation.dart';

import '../core/api_client.dart';

class AccountController extends ChangeNotifier {
  AccountController({required ApiClient api}) : _api = api;

  final ApiClient _api;

  Map<String, dynamic>? account;
  bool busy = false;
  String? error;

  Future<void> refresh() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      account = await _api.me();
    } catch (err) {
      error = err.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
