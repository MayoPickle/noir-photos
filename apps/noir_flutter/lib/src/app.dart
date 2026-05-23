import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'account/account_controller.dart';
import 'auth/auth_controller.dart';
import 'backup/backup_service.dart';
import 'core/api_client.dart';
import 'core/secure_store.dart';
import 'crypto/noir_crypto.dart';
import 'gallery/gallery_constants.dart';
import 'gallery/gallery_controller.dart';
import 'gallery/gallery_display.dart';
import 'search/search_index_service.dart';
import 'sharing/sharing_service.dart';
import 'ui/noir_theme.dart';

class NoirApp extends StatelessWidget {
  const NoirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noir Photos',
      debugShowCheckedModeBanner: false,
      theme: NoirTheme.dark,
      home: const HomeGate(),
    );
  }
}

class HomeGate extends StatelessWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.signedIn) return const AuthScreen();
    return VaultHome(vault: auth.vault!);
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final otp = TextEditingController();
  var registerMode = false;
  var otpRequested = false;
  var recoveryConfirmed = false;
  var passwordHidden = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canSubmit = !auth.busy && (!registerMode || recoveryConfirmed);

    return Scaffold(
      body: _NoirBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth =
                        (MediaQuery.sizeOf(context).width - 48)
                            .clamp(0.0, 1120.0)
                            .toDouble();
                    final wide = availableWidth >= 900;
                    final form = _AuthFormPanel(
                      email: email,
                      password: password,
                      otp: otp,
                      registerMode: registerMode,
                      otpRequested: otpRequested,
                      recoveryConfirmed: recoveryConfirmed,
                      passwordHidden: passwordHidden,
                      busy: auth.busy,
                      error: auth.error,
                      canSubmit: canSubmit,
                      onModeChanged: _changeMode,
                      onRecoveryChanged: (value) =>
                          setState(() => recoveryConfirmed = value),
                      onTogglePassword: () =>
                          setState(() => passwordHidden = !passwordHidden),
                      onStartOtp: _requestOtp,
                      onSubmit: _primaryAuthAction,
                    );

                    if (!wide) {
                      return SizedBox(
                        width: availableWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _AuthHero(compact: true),
                            const SizedBox(height: 18),
                            form,
                          ],
                        ),
                      );
                    }

                    return SizedBox(
                      width: availableWidth,
                      height: 720,
                      child: Stack(
                        children: [
                          const Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            right: 474,
                            child: _AuthHero(),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            width: 456,
                            child: form,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _changeMode(bool value) {
    setState(() {
      registerMode = value;
      otpRequested = false;
      otp.clear();
    });
  }

  Future<void> _requestOtp() async {
    final auth = context.read<AuthController>();
    try {
      await auth.startOtp(
          email.text.trim(), registerMode ? 'register' : 'login');
      if (mounted) {
        setState(() => otpRequested = true);
      }
    } catch (_) {
      // AuthController already exposes the error to the UI.
    }
  }

  Future<void> _primaryAuthAction() async {
    if (!otpRequested) {
      await _requestOtp();
      return;
    }
    await _submitAuth();
  }

  Future<void> _submitAuth() async {
    final auth = context.read<AuthController>();
    try {
      if (registerMode) {
        await auth.register(
            email: email.text.trim(),
            otp: otp.text.trim(),
            password: password.text);
      } else {
        await auth.login(
            email: email.text.trim(),
            otp: otp.text.trim(),
            password: password.text);
      }
    } catch (_) {
      return;
    }
    if (!mounted || auth.recoveryMnemonic == null) return;
    await _showRecoveryPhrase(auth.recoveryMnemonic!);
  }

  Future<void> _showRecoveryPhrase(String phrase) async {
    final words =
        phrase.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Recovery phrase'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This phrase is the only way to recover your vault if you lose access. Store it offline.',
              ),
              const SizedBox(height: 18),
              Container(
                decoration: noirPanelDecoration(
                    color: NoirColors.backgroundElevated,
                    radius: NoirRadii.medium),
                padding: const EdgeInsets.all(14),
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: words.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisExtent: 34,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, index) => SelectableText(
                    '${index + 1}. ${words[index]}',
                    style: const TextStyle(
                        color: NoirColors.text, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _WarningLine(
                  text: 'Never share your recovery phrase with anyone.'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("I've saved it securely"),
          ),
        ],
      ),
    );
  }
}

class VaultHome extends StatefulWidget {
  const VaultHome({required this.vault, super.key});

  final UnlockedVault vault;

  @override
  State<VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends State<VaultHome> {
  GalleryController? gallery;
  AccountController? account;
  var gridMode = true;
  var sortMode = 'newest';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    gallery ??= GalleryController(
      api: context.read<ApiClient>(),
      crypto: context.read<NoirCrypto>(),
      vault: widget.vault,
      searchIndex: SearchIndexService(
        api: context.read<ApiClient>(),
        crypto: context.read<NoirCrypto>(),
        vault: widget.vault,
        store: context.read<SecureStore>(),
        enabled: !kIsWeb,
      ),
    )..refresh();
    account ??= AccountController(api: context.read<ApiClient>());
  }

  @override
  Widget build(BuildContext context) {
    final controller = gallery!;
    return ChangeNotifierProvider.value(
      value: controller,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          if (compact) {
            return _MobileVaultScaffold(
              gridMode: gridMode,
              sortMode: sortMode,
              onGridModeChanged: (value) => setState(() => gridMode = value),
              onSortModeChanged: (value) => setState(() => sortMode = value),
              onNewAlbum: _newAlbum,
              onUpload: _pickAndUpload,
              onBackup: _runBackup,
              onAccount: _showAccount,
              onShare: _share,
              onAlbums: _showAlbumsSheet,
            );
          }

          return _DesktopVaultScaffold(
            gridMode: gridMode,
            sortMode: sortMode,
            onGridModeChanged: (value) => setState(() => gridMode = value),
            onSortModeChanged: (value) => setState(() => sortMode = value),
            onNewAlbum: _newAlbum,
            onUpload: _pickAndUpload,
            onBackup: _runBackup,
            onAccount: _showAccount,
            onShare: _share,
          );
        },
      ),
    );
  }

  Future<void> _newAlbum() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New album'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Album name',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      try {
        await gallery!.createAlbum(name.text.trim());
      } catch (_) {}
    }
    name.dispose();
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: true, type: FileType.media);
    if (result == null) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      try {
        await gallery!.uploadBytes(bytes: bytes, filename: file.name);
      } catch (_) {}
    }
  }

  Future<void> _runBackup() async {
    if (kIsWeb) return;
    final apiBaseUrl = context.read<ApiClient>().baseUrl;
    final store = context.read<SecureStore>();
    try {
      await BackupService.initialize(apiBaseUrl: apiBaseUrl);
      final backup = BackupService(store: store, gallery: gallery!);
      await backup.backupMobileLibrary();
    } catch (_) {}
  }

  Future<void> _share(Map<String, dynamic> collection) async {
    if (isLibraryCollection(collection)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a separate album to share photos.'),
        ),
      );
      return;
    }
    final api = context.read<ApiClient>();
    final crypto = context.read<NoirCrypto>();
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Share album'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: email,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Recipient email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Share')),
        ],
      ),
    );
    if (ok != true) {
      email.dispose();
      return;
    }
    final key = gallery!.collectionKeys[collection['id']];
    if (key == null) {
      email.dispose();
      return;
    }
    try {
      await SharingService(api: api, crypto: crypto).shareCollection(
        collectionId: collection['id'] as String,
        collectionKey: key,
        recipientEmail: email.text.trim(),
      );
      await gallery!.refresh();
    } catch (_) {}
    email.dispose();
  }

  Future<void> _showAccount() async {
    final auth = context.read<AuthController>();
    await account!.refresh();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: account!,
        child: AlertDialog(
          title: const Text('Account'),
          content: Consumer<AccountController>(
            builder: (_, value, __) {
              final data = value.account;
              if (data == null) {
                return const SizedBox(
                    width: 320, child: LinearProgressIndicator());
              }
              final user = data['user'] as Map<String, dynamic>;
              final sessions = data['sessions'] as List<dynamic>;
              return SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AccountHero(email: user['email'] as String),
                    const SizedBox(height: 18),
                    _MetricRow(
                      icon: Icons.storage_outlined,
                      label: 'Encrypted storage',
                      value: _bytes(user['storage_used_bytes'] as int?),
                    ),
                    const SizedBox(height: 18),
                    Text('Sessions',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final session in sessions.take(4))
                      _SessionRow(session: (session as Map<String, dynamic>)),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
                onPressed: () => _changePassword(auth),
                child: const Text('Change password')),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await auth.signOut();
              },
              child: const Text('Sign out'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await auth.deleteAccount();
              },
              child: const Text('Delete account',
                  style: TextStyle(color: NoirColors.danger)),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword(AuthController auth) async {
    final password = TextEditingController();
    final recovery = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change password'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'New password',
                    prefixIcon: Icon(Icons.lock_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: recovery,
                decoration: const InputDecoration(
                  labelText: 'Recovery phrase',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await auth.changePassword(password.text, recovery.text.trim());
      } catch (_) {}
    }
    password.dispose();
    recovery.dispose();
  }

  Future<void> _showAlbumsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NoirColors.panel,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: gallery!,
        child: _AlbumsBottomSheet(
          onNewAlbum: () {
            Navigator.pop(context);
            _newAlbum();
          },
          onShare: (collection) {
            Navigator.pop(context);
            _share(collection);
          },
        ),
      ),
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: noirPanelDecoration(
          color: NoirColors.backgroundElevated, radius: NoirRadii.xlarge),
      padding: EdgeInsets.all(compact ? 24 : 34),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          _NoirLogo(size: compact ? 58 : 76),
          const SizedBox(height: 24),
          Text(
            'Noir Photos',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(fontSize: compact ? 32 : 40),
          ),
          const SizedBox(height: 10),
          Text(
            'End-to-end encrypted. Local-first. Your photos. Your vault.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: NoirColors.textMuted, height: 1.35),
          ),
          if (!compact) ...[
            const Spacer(),
            const _EncryptedPhotoMosaic(),
            const SizedBox(height: 26),
            const Row(
              children: [
                Expanded(
                    child: _SecurityPoint(
                        icon: Icons.shield_outlined,
                        title: 'Encrypted on device')),
                SizedBox(width: 14),
                Expanded(
                    child: _SecurityPoint(
                        icon: Icons.key_outlined, title: 'You hold the keys')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthFormPanel extends StatelessWidget {
  const _AuthFormPanel({
    required this.email,
    required this.password,
    required this.otp,
    required this.registerMode,
    required this.otpRequested,
    required this.recoveryConfirmed,
    required this.passwordHidden,
    required this.busy,
    required this.canSubmit,
    required this.onModeChanged,
    required this.onRecoveryChanged,
    required this.onTogglePassword,
    required this.onStartOtp,
    required this.onSubmit,
    this.error,
  });

  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController otp;
  final bool registerMode;
  final bool otpRequested;
  final bool recoveryConfirmed;
  final bool passwordHidden;
  final bool busy;
  final bool canSubmit;
  final String? error;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<bool> onRecoveryChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onStartOtp;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: noirPanelDecoration(
          color: NoirColors.panel, radius: NoirRadii.xlarge),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            registerMode ? 'Create your encrypted vault' : 'Welcome back',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            registerMode
                ? 'Create a vault password. It stays on this device and protects your encrypted keys.'
                : 'Use your email and vault password. We only ask for an email code when confirming the session.',
            style: const TextStyle(color: NoirColors.textMuted, height: 1.35),
          ),
          const SizedBox(height: 22),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Login')),
              ButtonSegment(value: true, label: Text('Register')),
            ],
            selected: {registerMode},
            onSelectionChanged:
                busy ? null : (value) => onModeChanged(value.first),
          ),
          const SizedBox(height: 18),
          const _AuthFlowNote(),
          const SizedBox(height: 14),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            enabled: !busy,
            decoration: const InputDecoration(
                labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: passwordHidden,
            decoration: InputDecoration(
              labelText:
                  registerMode ? 'Create vault password' : 'Vault password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: passwordHidden ? 'Show password' : 'Hide password',
                onPressed: onTogglePassword,
                icon: Icon(passwordHidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: otpRequested
                ? _OtpStep(
                    key: const ValueKey('otp-step'),
                    otp: otp,
                    busy: busy,
                    registerMode: registerMode,
                    onResend: onStartOtp,
                  )
                : _VerificationHint(
                    key: const ValueKey('verification-hint-step'),
                    registerMode: registerMode,
                  ),
          ),
          if (registerMode) ...[
            const SizedBox(height: 12),
            _RecoveryCheck(
              value: recoveryConfirmed,
              onChanged: busy ? null : onRecoveryChanged,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            _ErrorBanner(message: error!),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: canSubmit ? onSubmit : null,
            child: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(otpRequested
                    ? (registerMode
                        ? 'Verify and create account'
                        : 'Verify and sign in')
                    : (registerMode ? 'Create account' : 'Sign in')),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: busy ? null : () => onModeChanged(!registerMode),
            child: Text(registerMode
                ? 'Already have a vault? Sign in'
                : 'New to Noir Photos? Create account'),
          ),
          const SizedBox(height: 12),
          const Center(
            child: _MutedIconText(
                icon: Icons.lock_outline,
                text: 'Encrypted on your device. Only you hold the key.'),
          ),
        ],
      ),
    );
  }
}

class _DesktopVaultScaffold extends StatelessWidget {
  const _DesktopVaultScaffold({
    required this.gridMode,
    required this.sortMode,
    required this.onGridModeChanged,
    required this.onSortModeChanged,
    required this.onNewAlbum,
    required this.onUpload,
    required this.onBackup,
    required this.onAccount,
    required this.onShare,
  });

  final bool gridMode;
  final String sortMode;
  final ValueChanged<bool> onGridModeChanged;
  final ValueChanged<String> onSortModeChanged;
  final VoidCallback onNewAlbum;
  final VoidCallback onUpload;
  final VoidCallback onBackup;
  final VoidCallback onAccount;
  final ValueChanged<Map<String, dynamic>> onShare;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _NoirBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: noirPanelDecoration(
                  color: NoirColors.backgroundElevated,
                  radius: NoirRadii.xlarge),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  SizedBox(
                    width: 286,
                    child: _AlbumSidebar(
                      onNewAlbum: onNewAlbum,
                      onShare: onShare,
                    ),
                  ),
                  const VerticalDivider(),
                  Expanded(
                    child: _VaultDashboard(
                      gridMode: gridMode,
                      sortMode: sortMode,
                      onGridModeChanged: onGridModeChanged,
                      onSortModeChanged: onSortModeChanged,
                      onUpload: onUpload,
                      onBackup: onBackup,
                      onAccount: onAccount,
                      onShare: onShare,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileVaultScaffold extends StatelessWidget {
  const _MobileVaultScaffold({
    required this.gridMode,
    required this.sortMode,
    required this.onGridModeChanged,
    required this.onSortModeChanged,
    required this.onNewAlbum,
    required this.onUpload,
    required this.onBackup,
    required this.onAccount,
    required this.onShare,
    required this.onAlbums,
  });

  final bool gridMode;
  final String sortMode;
  final ValueChanged<bool> onGridModeChanged;
  final ValueChanged<String> onSortModeChanged;
  final VoidCallback onNewAlbum;
  final VoidCallback onUpload;
  final VoidCallback onBackup;
  final VoidCallback onAccount;
  final ValueChanged<Map<String, dynamic>> onShare;
  final VoidCallback onAlbums;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _NoirBackdrop(
        child: SafeArea(
          bottom: false,
          child: _VaultDashboard(
            compact: true,
            gridMode: gridMode,
            sortMode: sortMode,
            onGridModeChanged: onGridModeChanged,
            onSortModeChanged: onSortModeChanged,
            onUpload: onUpload,
            onBackup: onBackup,
            onAccount: onAccount,
            onShare: onShare,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New album',
        backgroundColor: NoirColors.accent,
        foregroundColor: Colors.white,
        onPressed: onNewAlbum,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: NoirColors.backgroundElevated,
        indicatorColor: NoirColors.accentSoft,
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 0) onAlbums();
          if (index == 1) onUpload();
          if (index == 2 && !kIsWeb) onBackup();
          if ((kIsWeb && index == 2) || (!kIsWeb && index == 3)) onAccount();
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Albums'),
          const NavigationDestination(
              icon: Icon(Icons.upload_outlined),
              selectedIcon: Icon(Icons.upload),
              label: 'Upload'),
          if (!kIsWeb)
            const NavigationDestination(
                icon: Icon(Icons.cloud_upload_outlined),
                selectedIcon: Icon(Icons.cloud_upload),
                label: 'Backup'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Account'),
        ],
      ),
    );
  }
}

class _AlbumSidebar extends StatelessWidget {
  const _AlbumSidebar({
    required this.onNewAlbum,
    required this.onShare,
  });

  final VoidCallback onNewAlbum;
  final ValueChanged<Map<String, dynamic>> onShare;

  @override
  Widget build(BuildContext context) {
    final crypto = context.read<NoirCrypto>();
    return Consumer<GalleryController>(
      builder: (_, value, __) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BrandHeader(),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text('Albums',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: NoirColors.textMuted)),
                  ),
                  IconButton(
                    tooltip: 'New album',
                    icon: const Icon(Icons.add),
                    color: NoirColors.accent,
                    onPressed: onNewAlbum,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: value.collections.isEmpty
                    ? _SidebarEmpty(
                        busy: value.busy,
                        hasError: value.error != null,
                      )
                    : ListView.separated(
                        itemCount: value.collections.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, index) {
                          final collection = value.collections[index];
                          final selected =
                              collection['id'] == value.selectedCollectionId;
                          final display = collectionDisplayFor(
                            collection: collection,
                            collectionKeys: value.collectionKeys,
                            crypto: crypto,
                            visibleFileCount:
                                selected ? value.files.length : null,
                          );
                          return _AlbumTile(
                            display: display,
                            selected: selected,
                            onTap: () => value.selectCollection(display.id),
                            onShare: () => onShare(collection),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 14),
              _SecuritySummary(fileCount: value.files.length, busy: value.busy),
            ],
          ),
        );
      },
    );
  }
}

class _VaultDashboard extends StatelessWidget {
  const _VaultDashboard({
    required this.gridMode,
    required this.sortMode,
    required this.onGridModeChanged,
    required this.onSortModeChanged,
    required this.onUpload,
    required this.onBackup,
    required this.onAccount,
    required this.onShare,
    this.compact = false,
  });

  final bool compact;
  final bool gridMode;
  final String sortMode;
  final ValueChanged<bool> onGridModeChanged;
  final ValueChanged<String> onSortModeChanged;
  final VoidCallback onUpload;
  final VoidCallback onBackup;
  final VoidCallback onAccount;
  final ValueChanged<Map<String, dynamic>> onShare;

  @override
  Widget build(BuildContext context) {
    final crypto = context.read<NoirCrypto>();
    return Consumer<GalleryController>(
      builder: (_, value, __) {
        final selected = _selectedCollection(value);
        final selectedDisplay = selected == null
            ? null
            : collectionDisplayFor(
                collection: selected,
                collectionKeys: value.collectionKeys,
                crypto: crypto,
                visibleFileCount: value.files.length,
              );
        final selectedKey = value.collectionKeys[value.selectedCollectionId];
        final displays = [
          for (var i = 0; i < value.visibleFiles.length; i++)
            fileDisplayFor(
                file: value.visibleFiles[i],
                collectionKey: selectedKey,
                crypto: crypto,
                index: i),
        ]..sort((a, b) {
            if (sortMode == 'name') {
              return a.title.toLowerCase().compareTo(b.title.toLowerCase());
            }
            return 0;
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DashboardHeader(
              compact: compact,
              collection: selectedDisplay,
              hasSelection: selected != null,
              gridMode: gridMode,
              sortMode: sortMode,
              searchQuery: value.searchQuery,
              indexingSearch: value.indexingSearch,
              onGridModeChanged: onGridModeChanged,
              onSortModeChanged: onSortModeChanged,
              onSearchChanged: (query) {
                value.setSearchQuery(query);
              },
              onUpload: onUpload,
              onBackup: onBackup,
              onAccount: onAccount,
              onShare: selected == null || selectedDisplay?.canShare != true
                  ? null
                  : () => onShare(selected),
            ),
            if (value.busy) const LinearProgressIndicator(minHeight: 2),
            if (value.error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24, 12, compact ? 16 : 24, 0),
                child: _ErrorBanner(message: value.error!),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 24, 18, compact ? 14 : 24, 24),
                child: _VaultContent(
                  compact: compact,
                  gridMode: gridMode,
                  collectionsEmpty: value.collections.isEmpty,
                  preparingLibrary: value.collections.isEmpty &&
                      value.busy &&
                      value.error == null,
                  librarySetupFailed:
                      value.collections.isEmpty && value.error != null,
                  searchActive: value.searchQuery.trim().isNotEmpty,
                  files: displays,
                  onNewAlbum: () => _openNewAlbum(context),
                  onRetry: () => context.read<GalleryController>().refresh(),
                  onUpload: selected == null ? null : onUpload,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openNewAlbum(BuildContext context) {
    final state = context.findAncestorStateOfType<_VaultHomeState>();
    state?._newAlbum();
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.compact,
    required this.collection,
    required this.hasSelection,
    required this.gridMode,
    required this.sortMode,
    required this.searchQuery,
    required this.indexingSearch,
    required this.onGridModeChanged,
    required this.onSortModeChanged,
    required this.onSearchChanged,
    required this.onUpload,
    required this.onBackup,
    required this.onAccount,
    required this.onShare,
  });

  final bool compact;
  final CollectionDisplay? collection;
  final bool hasSelection;
  final bool gridMode;
  final String sortMode;
  final String searchQuery;
  final bool indexingSearch;
  final ValueChanged<bool> onGridModeChanged;
  final ValueChanged<String> onSortModeChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onUpload;
  final VoidCallback onBackup;
  final VoidCallback onAccount;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, compact ? 14 : 18,
          compact ? 16 : 24, compact ? 14 : 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NoirColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (compact) ...[
                const _NoirLogo(size: 38),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                            collection?.isLibrary == true
                                ? Icons.photo_library_rounded
                                : Icons.folder_rounded,
                            color: collection == null
                                ? NoirColors.textMuted
                                : NoirColors.accent),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            collection?.title ?? 'Noir Photos',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontSize: compact ? 22 : 28),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      collection == null
                          ? 'Preparing your encrypted library.'
                          : collection!.isLibrary
                              ? '${formatCount(collection!.visibleFileCount ?? 0, 'file', 'files')} - Private library'
                              : '${formatCount(collection!.visibleFileCount ?? 0, 'file', 'files')} - ${collection!.role}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: NoirColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                _CommandButton(
                    icon: Icons.upload_file_outlined,
                    label: 'Upload',
                    onPressed: hasSelection ? onUpload : null),
                const SizedBox(width: 10),
                _CommandButton(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Start backup',
                  onPressed: kIsWeb ? null : onBackup,
                ),
                const SizedBox(width: 10),
                _CommandButton(
                    icon: Icons.person_outline,
                    label: 'Account',
                    onPressed: onAccount),
              ] else
                IconButton(
                    tooltip: 'Account',
                    onPressed: onAccount,
                    icon: const Icon(Icons.person_outline)),
            ],
          ),
          const SizedBox(height: 16),
          _SearchBox(
            query: searchQuery,
            enabled: hasSelection && !kIsWeb,
            indexing: indexingSearch,
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onShare != null)
                _CommandButton(
                    icon: Icons.ios_share, label: 'Share', onPressed: onShare),
              if (compact)
                _CommandButton(
                    icon: Icons.upload_file_outlined,
                    label: 'Upload',
                    onPressed: hasSelection ? onUpload : null),
              _ViewToggle(gridMode: gridMode, onChanged: onGridModeChanged),
              _SortMenu(value: sortMode, onChanged: onSortModeChanged),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({
    required this.query,
    required this.enabled,
    required this.indexing,
    required this.onChanged,
  });

  final String query;
  final bool enabled;
  final bool indexing;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _SearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText:
            kIsWeb ? 'Search on mobile' : 'Search people, places, objects',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: widget.indexing
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged('');
                    },
                    icon: const Icon(Icons.close),
                  ),
      ),
    );
  }
}

class _VaultContent extends StatelessWidget {
  const _VaultContent({
    required this.compact,
    required this.gridMode,
    required this.collectionsEmpty,
    required this.preparingLibrary,
    required this.librarySetupFailed,
    required this.searchActive,
    required this.files,
    required this.onNewAlbum,
    required this.onRetry,
    required this.onUpload,
  });

  final bool compact;
  final bool gridMode;
  final bool collectionsEmpty;
  final bool preparingLibrary;
  final bool librarySetupFailed;
  final bool searchActive;
  final List<FileDisplay> files;
  final VoidCallback onNewAlbum;
  final VoidCallback onRetry;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    if (collectionsEmpty) {
      if (preparingLibrary) {
        return const _EmptyVaultState(
          icon: Icons.photo_library_outlined,
          title: 'Preparing your encrypted library...',
          body:
              'Noir is creating a private Library so uploads have a safe default destination.',
          actionLabel: 'Preparing',
          onAction: null,
        );
      }
      return _EmptyVaultState(
        icon: librarySetupFailed
            ? Icons.warning_amber_rounded
            : Icons.photo_library_outlined,
        title: librarySetupFailed
            ? 'Library setup needs attention.'
            : 'Preparing your encrypted library...',
        body: librarySetupFailed
            ? 'Noir could not create your private Library. Retry setup or create an album manually.'
            : 'Your private Library is the default destination for encrypted uploads.',
        actionLabel: librarySetupFailed ? 'Try again' : 'New album',
        onAction: librarySetupFailed ? onRetry : onNewAlbum,
      );
    }
    if (files.isEmpty) {
      return _EmptyVaultState(
        icon: searchActive ? Icons.search_off : Icons.image_outlined,
        title: searchActive
            ? 'No private search matches.'
            : 'No encrypted files yet.',
        body: searchActive
            ? 'Try a different phrase once this device finishes building its local index.'
            : 'Upload photos or media to encrypt them locally before they leave your device.',
        actionLabel: searchActive ? 'Clear search' : 'Upload',
        onAction: searchActive
            ? () {
                context.read<GalleryController>().setSearchQuery('');
              }
            : onUpload,
      );
    }
    if (!gridMode) {
      return ListView.separated(
        itemCount: files.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) => _EncryptedFileRow(file: files[index]),
      );
    }
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 170 : 230,
        mainAxisExtent: compact ? 198 : 232,
        mainAxisSpacing: compact ? 10 : 14,
        crossAxisSpacing: compact ? 10 : 14,
      ),
      itemCount: files.length,
      itemBuilder: (_, index) => _EncryptedFileCard(file: files[index]),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.display,
    required this.selected,
    required this.onTap,
    required this.onShare,
  });

  final CollectionDisplay display;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? NoirColors.panelHover : Colors.transparent,
      borderRadius: BorderRadius.circular(NoirRadii.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(NoirRadii.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _FolderIcon(
                shared: display.isShared,
                library: display.isLibrary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            selected ? NoirColors.text : NoirColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      display.isLibrary
                          ? 'Private library'
                          : display.isShared
                              ? 'Shared - ${display.role}'
                              : display.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: NoirColors.textSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (display.visibleFileCount != null)
                Text(
                  '${display.visibleFileCount}',
                  style: const TextStyle(
                      color: NoirColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                )
              else if (!display.canShare)
                const Tooltip(
                  message: 'Private library',
                  child: Icon(Icons.lock_outline,
                      color: NoirColors.textSubtle, size: 18),
                )
              else
                IconButton(
                  tooltip: 'Share',
                  visualDensity: VisualDensity.compact,
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EncryptedFileCard extends StatelessWidget {
  const _EncryptedFileCard({required this.file});

  final FileDisplay file;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: noirPanelDecoration(
          color: NoirColors.panelSoft, radius: NoirRadii.medium),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _EncryptedThumbnail(seed: file.paletteIndex),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${file.sizeLabel} - ${file.subtitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: NoirColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                _HashTag(hash: file.hashPrefix),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EncryptedFileRow extends StatelessWidget {
  const _EncryptedFileRow({required this.file});

  final FileDisplay file;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: noirPanelDecoration(
          color: NoirColors.panelSoft, radius: NoirRadii.medium),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SizedBox(
              width: 76,
              height: 62,
              child: _EncryptedThumbnail(seed: file.paletteIndex)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${file.sizeLabel} - ${file.subtitle}',
                    style: const TextStyle(color: NoirColors.textMuted)),
              ],
            ),
          ),
          _HashTag(hash: file.hashPrefix),
        ],
      ),
    );
  }
}

class _EncryptedThumbnail extends StatelessWidget {
  const _EncryptedThumbnail({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final palettes = [
      const [Color(0xff514447), Color(0xff1a202a), Color(0xff8a5f45)],
      const [Color(0xff20313a), Color(0xff0c1118), Color(0xff617f87)],
      const [Color(0xff3e402d), Color(0xff10151a), Color(0xff84724d)],
      const [Color(0xff463547), Color(0xff10151f), Color(0xff827185)],
      const [Color(0xff213041), Color(0xff0a1018), Color(0xff366e8c)],
    ];
    final palette = palettes[seed.abs() % palettes.length];
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
          ),
        ),
        Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(NoirRadii.medium),
              border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
            ),
            child:
                const Icon(Icons.lock_outline, color: Colors.white, size: 24),
          ),
        ),
        const Positioned(
          left: 10,
          bottom: 10,
          child: Icon(Icons.verified_user_outlined,
              color: NoirColors.accent, size: 18),
        ),
        const Positioned(
          right: 8,
          top: 8,
          child: Icon(Icons.more_vert, color: Colors.white, size: 18),
        ),
      ],
    );
  }
}

class _AlbumsBottomSheet extends StatelessWidget {
  const _AlbumsBottomSheet({
    required this.onNewAlbum,
    required this.onShare,
  });

  final VoidCallback onNewAlbum;
  final ValueChanged<Map<String, dynamic>> onShare;

  @override
  Widget build(BuildContext context) {
    final crypto = context.read<NoirCrypto>();
    return Consumer<GalleryController>(
      builder: (_, value, __) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Albums',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: 'New album',
                      onPressed: onNewAlbum,
                      icon: const Icon(Icons.add)),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: value.collections.isEmpty
                    ? _SidebarEmpty(
                        busy: value.busy,
                        hasError: value.error != null,
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: value.collections.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final collection = value.collections[index];
                          final selected =
                              collection['id'] == value.selectedCollectionId;
                          final display = collectionDisplayFor(
                            collection: collection,
                            collectionKeys: value.collectionKeys,
                            crypto: crypto,
                            visibleFileCount:
                                selected ? value.files.length : null,
                          );
                          return _AlbumTile(
                            display: display,
                            selected: selected,
                            onTap: () {
                              value.selectCollection(display.id);
                              Navigator.pop(context);
                            },
                            onShare: () => onShare(collection),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic>? _selectedCollection(GalleryController value) {
  if (value.collections.isEmpty) return null;
  for (final collection in value.collections) {
    if (collection['id'] == value.selectedCollectionId) return collection;
  }
  return value.collections.first;
}

class _NoirBackdrop extends StatelessWidget {
  const _NoirBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff07111b), NoirColors.background],
        ),
      ),
      child: child,
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _NoirLogo(size: 42),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Noir Photos',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
      ],
    );
  }
}

class _NoirLogo extends StatelessWidget {
  const _NoirLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        color: NoirColors.accentSoft,
        border: Border.all(color: NoirColors.accent.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
              color: NoirColors.accent.withValues(alpha: 0.28), blurRadius: 24),
        ],
      ),
      child:
          Icon(Icons.lock_outline, color: NoirColors.cyan, size: size * 0.55),
    );
  }
}

class _EncryptedPhotoMosaic extends StatelessWidget {
  const _EncryptedPhotoMosaic();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 156,
      child: Row(
        children: [
          for (var index = 0; index < 3; index++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NoirRadii.medium),
                child: _EncryptedThumbnail(seed: index),
              ),
            ),
            if (index != 2) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _SecurityPoint extends StatelessWidget {
  const _SecurityPoint({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: noirPanelDecoration(
          color: NoirColors.panelSoft, radius: NoirRadii.medium),
      child: Row(
        children: [
          Icon(icon, color: NoirColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _AuthFlowNote extends StatelessWidget {
  const _AuthFlowNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirColors.accentSoft.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(NoirRadii.medium),
        border: Border.all(color: NoirColors.accent.withValues(alpha: 0.32)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: NoirColors.accent, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vault password decrypts your photo keys locally. Email verification protects the server session without sending your password.',
              style: TextStyle(color: NoirColors.textMuted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationHint extends StatelessWidget {
  const _VerificationHint({
    super.key,
    required this.registerMode,
  });

  final bool registerMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirColors.panelSoft,
        borderRadius: BorderRadius.circular(NoirRadii.medium),
        border: Border.all(color: NoirColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mark_email_unread_outlined,
              color: NoirColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              registerMode
                  ? 'Next, we will email a signup code to verify this address.'
                  : 'Next, we will email a login code to verify this session.',
              style: const TextStyle(color: NoirColors.textMuted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpStep extends StatelessWidget {
  const _OtpStep({
    super.key,
    required this.otp,
    required this.busy,
    required this.registerMode,
    required this.onResend,
  });

  final TextEditingController otp;
  final bool busy;
  final bool registerMode;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: otp,
          enabled: !busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: registerMode ? 'Signup code' : 'Login code',
            prefixIcon: const Icon(Icons.verified_user_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : onResend,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Resend code'),
          ),
        ),
      ],
    );
  }
}

class _RecoveryCheck extends StatelessWidget {
  const _RecoveryCheck({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(NoirRadii.medium),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
              value: value,
              onChanged: onChanged == null
                  ? null
                  : (next) => onChanged!(next ?? false)),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'I understand that Noir Photos cannot access my data or recovery phrase.',
                style: TextStyle(color: NoirColors.textMuted, height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton(
      {required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.gridMode, required this.onChanged});

  final bool gridMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: NoirColors.lineStrong),
        borderRadius: BorderRadius.circular(NoirRadii.medium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleIcon(
            tooltip: 'Grid view',
            icon: Icons.grid_view_rounded,
            selected: gridMode,
            onTap: () => onChanged(true),
          ),
          _ToggleIcon(
            tooltip: 'List view',
            icon: Icons.view_list_rounded,
            selected: !gridMode,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NoirRadii.small),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? NoirColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(NoirRadii.small),
          ),
          child: Icon(icon,
              color: selected ? NoirColors.accent : NoirColors.textMuted,
              size: 20),
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: NoirColors.lineStrong),
        borderRadius: BorderRadius.circular(NoirRadii.medium),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: NoirColors.panel,
          borderRadius: BorderRadius.circular(NoirRadii.medium),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: const [
            DropdownMenuItem(value: 'newest', child: Text('Newest')),
            DropdownMenuItem(value: 'name', child: Text('Name')),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class _SecuritySummary extends StatelessWidget {
  const _SecuritySummary({required this.fileCount, required this.busy});

  final int fileCount;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: noirPanelDecoration(
          color: NoirColors.panelSoft, radius: NoirRadii.medium),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: NoirColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  busy ? 'Syncing securely' : 'All good',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: NoirColors.success, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${formatCount(fileCount, 'file', 'files')} in the selected vault. Metadata stays encrypted.',
            style: const TextStyle(color: NoirColors.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _EmptyVaultState extends StatelessWidget {
  const _EmptyVaultState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: BoxDecoration(
            color: NoirColors.panel.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(NoirRadii.large),
            border:
                Border.all(color: NoirColors.line, style: BorderStyle.solid),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: NoirColors.textMuted, size: 54),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: NoirColors.textMuted, height: 1.45)),
              const SizedBox(height: 20),
              if (onAction == null)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionLabel == 'Upload'
                      ? Icons.upload_file_outlined
                      : actionLabel == 'Try again'
                          ? Icons.refresh_rounded
                          : Icons.add),
                  label: Text(actionLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NoirRadii.medium),
        border: Border.all(color: NoirColors.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: NoirColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: NoirColors.text))),
        ],
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.warning_amber_rounded,
            color: NoirColors.warning, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(text, style: const TextStyle(color: NoirColors.warning))),
      ],
    );
  }
}

class _MutedIconText extends StatelessWidget {
  const _MutedIconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: NoirColors.textMuted, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: NoirColors.textMuted, fontSize: 12)),
        ),
      ],
    );
  }
}

class _FolderIcon extends StatelessWidget {
  const _FolderIcon({required this.shared, required this.library});

  final bool shared;
  final bool library;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 30,
      decoration: BoxDecoration(
        color: library
            ? NoirColors.accent
            : shared
                ? const Color(0xff70d68c)
                : const Color(0xff6da4ff),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(
          library
              ? Icons.photo_library_outlined
              : shared
                  ? Icons.people_alt_outlined
                  : Icons.folder_outlined,
          size: 18,
          color: NoirColors.background),
    );
  }
}

class _HashTag extends StatelessWidget {
  const _HashTag({required this.hash});

  final String hash;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NoirColors.backgroundElevated,
        borderRadius: BorderRadius.circular(NoirRadii.small),
        border: Border.all(color: NoirColors.line),
      ),
      child: Text(
        hash.isEmpty ? 'sealed' : hash,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: NoirColors.textMuted, fontSize: 11, fontFeatures: []),
      ),
    );
  }
}

class _SidebarEmpty extends StatelessWidget {
  const _SidebarEmpty({required this.busy, required this.hasError});

  final bool busy;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        hasError
            ? 'Library setup needs attention.'
            : busy
                ? 'Preparing Library...'
                : 'Preparing your encrypted library.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: NoirColors.textMuted),
      ),
    );
  }
}

class _AccountHero extends StatelessWidget {
  const _AccountHero({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: noirPanelDecoration(
          color: NoirColors.panelSoft, radius: NoirRadii.medium),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const _NoirLogo(size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Local-first encrypted account',
                    style: TextStyle(color: NoirColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: NoirColors.accent),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: const TextStyle(color: NoirColors.textMuted))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final platform = session['platform']?.toString() ?? 'unknown';
    final deviceName = session['device_name']?.toString() ?? platform;
    final created = session['created_at']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.devices_outlined,
              size: 18, color: NoirColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(deviceName, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              created,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NoirColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

String _bytes(int? bytes) {
  if (bytes == null) return '0 B';
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
