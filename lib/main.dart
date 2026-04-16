import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/push/push_service.dart';
import 'core/navigation/pending_deep_link_store.dart';
import 'core/vault/vault_mailbox_sync_service.dart';
import 'models/vault_theme.dart';
import 'screens/contact_link_screen.dart';
import 'screens/home.dart';
import 'screens/start_chat.dart';
import 'screens/join_chat.dart';
import 'screens/my_chats.dart';
import 'state/chat_store.dart';
import 'state/chat_category_store.dart';
import 'state/chat_unread_store.dart';
import 'state/identity_store.dart';
import 'state/contacts_store.dart';
import 'state/message_store.dart';
import 'state/chat_appearance_store.dart';
import 'state/contact_appearance_store.dart';
import 'state/push_store.dart';
import 'state/push_runtime_store.dart';
import 'state/security_store.dart';
import 'state/date_time_format_store.dart';
import 'state/text_scale_store.dart';
import 'state/vault_theme_store.dart';
import 'state/voice_notes_store.dart';
import 'state/call_policy_store.dart';
import 'state/sticker_store.dart';
import 'state/media_policy_store.dart';
import 'state/read_receipts_store.dart';
import 'state/vault_store.dart';
import 'core/calls/call_service.dart';
import 'core/ui/orientation_lock.dart';
import 'core/ui/desktop_shell_service.dart';
import 'core/ui/vault_splash_screen.dart';
import 'core/media/media_cipher.dart';

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

bool get _usesTestBinding {
  final bindingName = WidgetsBinding.instance.runtimeType.toString();
  return bindingName.contains('AutomatedTestWidgetsFlutterBinding') ||
      bindingName.contains('LiveTestWidgetsFlutterBinding');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(700, 720),
      minimumSize: Size(620, 560),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const VaultBootstrapApp());
}

Future<void> _bootstrapApp() async {
  if ((Platform.isAndroid || Platform.isIOS) && !_isFlutterTest) {
    try {
      await Firebase.initializeApp();
      PushRuntimeStore.setFirebaseReady(true, status: 'Ready');
    } catch (error) {
      debugPrint('[Push] Firebase init failed: $error');
      PushRuntimeStore.setFirebaseReady(false, status: 'Init failed');
      PushRuntimeStore.markRelayFailure(
        'Firebase unavailable',
        error: 'Firebase init failed: $error',
      );
    }
  } else {
    PushRuntimeStore.setFirebaseReady(
      false,
      status: 'Not used on this platform',
    );
  }
  await ChatStore.init();
  await ChatCategoryStore.init();
  await ChatUnreadStore.init();
  await IdentityStore.init();
  await VaultStore.init();
  await ContactsStore.init();
  await MessageStore.init();
  await ChatAppearanceStore.init();
  await ContactAppearanceStore.init();
  await PushStore.init();
  await VoiceNotesStore.init();
  await StickerStore.init();
  await SecurityStore.init();
  await ReadReceiptsStore.init();
  await MediaCipher.init();
  await MediaPolicyStore.init();
  await CallPolicyStore.init();
  await VaultThemeStore.init();
  await DateTimeFormatStore.init();
  await TextScaleStore.init();
}

Future<void> _runBootstrapSequence() async {
  await Future.wait<void>([
    _bootstrapApp(),
    Future<void>.delayed(const Duration(milliseconds: 1700)),
  ]);
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class VaultBootstrapApp extends StatefulWidget {
  const VaultBootstrapApp({super.key});

  @override
  State<VaultBootstrapApp> createState() => _VaultBootstrapAppState();
}

class _VaultBootstrapAppState extends State<VaultBootstrapApp> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _runBootstrapSequence();
  }

  void _retryBootstrap() {
    setState(() {
      _bootstrapFuture = _runBootstrapSequence();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.dark,
            theme: ThemeData.dark(useMaterial3: true),
            home: const VaultSplashScreen(),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.dark,
            theme: ThemeData.dark(useMaterial3: true),
            home: VaultSplashScreen(
              errorMessage: '${snapshot.error}',
              onRetry: _retryBootstrap,
            ),
          );
        }
        return const ConquerorsCourtApp();
      },
    );
  }
}

class ConquerorsCourtApp extends StatefulWidget {
  const ConquerorsCourtApp({super.key});

  @override
  State<ConquerorsCourtApp> createState() => _ConquerorsCourtAppState();
}

class _ConquerorsCourtAppState extends State<ConquerorsCourtApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Default orientation: portrait-only. Specific screens (chat/media) can
    // temporarily opt into landscape via OrientationLockScope.
    unawaited(OrientationLock.push(OrientationLock.portraitOnly));
    WidgetsBinding.instance.addObserver(this);
    SecurityStore.lockedNotifier.addListener(_handleLockChange);
    CallService.init(navigatorKey: appNavigatorKey);
    if (!_isFlutterTest && !_usesTestBinding) {
      PushService.init(navigatorKey: appNavigatorKey);
      unawaited(VaultStore.bootstrap());
      unawaited(VaultMailboxSyncService.init());
      unawaited(DesktopShellService.init());
    }
  }

  @override
  void dispose() {
    unawaited(OrientationLock.pop());
    SecurityStore.lockedNotifier.removeListener(_handleLockChange);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(DesktopShellService.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final keepDesktopMailboxAlive =
        !kIsWeb && Platform.isWindows && state != AppLifecycleState.detached;
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
      return;
    }
    if (SecurityStore.autoLockSuppressed || !SecurityStore.isAppLockEnabled) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached ||
          state == AppLifecycleState.hidden) {
        if (!keepDesktopMailboxAlive) {
          VaultMailboxSyncService.pause();
        }
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (!keepDesktopMailboxAlive) {
        VaultMailboxSyncService.pause();
      }
      SecurityStore.lock();
    }
  }

  Future<void> _handleAppResumed() async {
    await ChatUnreadStore.reloadFromDisk();
    PushService.resync();
    VaultMailboxSyncService.resume();
    await DesktopShellService.syncUnreadCount();
  }

  void _handleLockChange() {
    if (SecurityStore.isLocked) {
      appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/',
        (route) => false,
      );
    }
  }

  bool _isBlockedRoute(String? name) {
    // Until a Title is claimed, only Home is allowed.
    // This prevents bypass via deep links or future routes.
    final normalized = _normalizedRouteName(name);
    return normalized != '/' && normalized != ContactLinkScreen.route;
  }

  bool _isRestorableDeepLinkRoute(String? name) {
    return _normalizedRouteName(name) == ContactLinkScreen.route;
  }

  String _normalizedRouteName(String? rawName) {
    final name = (rawName ?? '').trim();
    if (name.isEmpty) return '/';

    final uri = Uri.tryParse(name);
    if (uri != null) {
      if (uri.hasScheme) {
        if (uri.path.trim().isNotEmpty) {
          return uri.path.trim();
        }
        if (uri.host.trim().isNotEmpty) {
          return '/${uri.host.trim()}';
        }
      }
      if (uri.path.trim().isNotEmpty) {
        return uri.path.trim();
      }
    }

    final queryIndex = name.indexOf('?');
    if (queryIndex >= 0) {
      final pathOnly = name.substring(0, queryIndex).trim();
      return pathOnly.isEmpty ? '/' : pathOnly;
    }
    return name;
  }

  String? _initialInviteForRoute(String? rawName) {
    final name = (rawName ?? '').trim();
    if (name.isEmpty) return null;
    final uri = Uri.tryParse(name);
    if (uri == null) return null;
    final hasInviteData =
        uri.queryParameters.containsKey('chatId') ||
        uri.queryParameters.containsKey('id') ||
        uri.queryParameters.containsKey('sharedSecret') ||
        uri.queryParameters.containsKey('key');
    if (!hasInviteData) return null;
    if (uri.hasScheme) {
      return uri.toString();
    }
    return name;
  }

  Route<dynamic> _routeFor(String? rawName) {
    final name = _normalizedRouteName(rawName);
    switch (name) {
      case '/start':
        return MaterialPageRoute(builder: (_) => const StartChatScreen());
      case '/join':
        return MaterialPageRoute(
          builder: (_) =>
              JoinChatScreen(initialInvite: _initialInviteForRoute(rawName)),
        );
      case '/contact':
        return MaterialPageRoute(
          builder: (_) => ContactLinkScreen(initialLink: rawName),
        );
      case '/chats':
        return MaterialPageRoute(builder: (_) => const MyChatsScreen());
      case '/':
      default:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VaultThemeConfig>(
      valueListenable: VaultThemeStore.themeNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<double>(
          valueListenable: TextScaleStore.scaleNotifier,
          builder: (context, textScale, __) {
            return MaterialApp(
              title: "The Vault",
              debugShowCheckedModeBanner: false,
              navigatorKey: appNavigatorKey,
              themeMode: ThemeMode.dark,
              theme: VaultThemeStore.themeData(),
              builder: (context, child) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              initialRoute: !kIsWeb ? '/chats' : '/',
              onGenerateRoute: (settings) {
                final name = settings.name;

                if (SecurityStore.isLocked && name != '/') {
                  if (_isRestorableDeepLinkRoute(name)) {
                    PendingDeepLinkStore.set(name);
                  }
                  return _routeFor('/');
                }

                final hasCustom = IdentityStore.usernameCustom;
                final blocked = _isBlockedRoute(name);

                if (!hasCustom && blocked) {
                  return _routeFor('/');
                }

                return _routeFor(name);
              },
            );
          },
        );
      },
    );
  }
}
