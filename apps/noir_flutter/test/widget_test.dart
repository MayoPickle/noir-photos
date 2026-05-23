import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:noir_flutter/src/app.dart';
import 'package:noir_flutter/src/auth/auth_controller.dart';
import 'package:noir_flutter/src/core/api_client.dart';
import 'package:noir_flutter/src/core/secure_store.dart';
import 'package:noir_flutter/src/crypto/noir_crypto.dart';

void main() {
  late NoirCrypto crypto;

  setUpAll(() async {
    crypto = await NoirCrypto.load();
  });

  testWidgets('renders the modern auth screen', (tester) async {
    final store = SecureStore();
    final api = ApiClient(baseUrl: 'http://localhost:8000', store: store);
    final auth = AuthController(api: api, crypto: crypto, store: store);

    await tester.pumpWidget(
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

    expect(find.text('Noir Photos'), findsWidgets);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Vault password'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('login code'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.textContaining('Vault password decrypts'), findsOneWidget);
    expect(find.textContaining('cannot access my data'), findsNothing);

    await tester.tap(find.text('Register'));
    await tester.pump();
    expect(find.text('Create your encrypted vault'), findsOneWidget);
    expect(find.text('Create vault password'), findsOneWidget);
    expect(find.textContaining('signup code'), findsOneWidget);
    expect(find.textContaining('cannot access my data'), findsOneWidget);

    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('renders the desktop auth layout without overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = SecureStore();
    final api = ApiClient(baseUrl: 'http://localhost:8000', store: store);
    final auth = AuthController(api: api, crypto: crypto, store: store);

    await tester.pumpWidget(
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

    expect(find.text('Noir Photos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the mobile auth layout without overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = SecureStore();
    final api = ApiClient(baseUrl: 'http://localhost:8000', store: store);
    final auth = AuthController(api: api, crypto: crypto, store: store);

    await tester.pumpWidget(
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

    expect(find.text('Noir Photos'), findsWidgets);
    expect(find.text('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
