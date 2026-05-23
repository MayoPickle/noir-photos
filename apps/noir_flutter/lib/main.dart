import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app.dart';
import 'src/auth/auth_controller.dart';
import 'src/core/api_client.dart';
import 'src/core/secure_store.dart';
import 'src/crypto/noir_crypto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final crypto = await NoirCrypto.load();
  final store = SecureStore();
  final api = ApiClient(
    baseUrl: const String.fromEnvironment('NOIR_API_URL',
        defaultValue: 'http://localhost:8000'),
    store: store,
  );
  final auth = AuthController(api: api, crypto: crypto, store: store);
  await auth.restore();
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: crypto),
        Provider.value(value: api),
        Provider.value(value: store),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: const NoirApp(),
    ),
  );
}
