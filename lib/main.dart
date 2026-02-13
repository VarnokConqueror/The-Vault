import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/push/push_service.dart';
import 'screens/home.dart';
import 'screens/start_chat.dart';
import 'screens/join_chat.dart';
import 'screens/my_chats.dart';
import 'state/chat_store.dart';
import 'state/identity_store.dart';
import 'state/contacts_store.dart';
import 'state/message_store.dart';
import 'state/chat_appearance_store.dart';
import 'state/contact_appearance_store.dart';
import 'state/push_store.dart';
import 'state/security_store.dart';
import 'state/voice_notes_store.dart';
import 'state/call_policy_store.dart';
import 'state/sticker_store.dart';
import 'state/media_policy_store.dart';
import 'state/read_receipts_store.dart';
import 'core/calls/call_service.dart';
import 'core/ui/orientation_lock.dart';
import 'core/media/media_cipher.dart';

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid && !_isFlutterTest) {
    await Firebase.initializeApp();
  }
  await ChatStore.init();
  await IdentityStore.init();
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
  runApp(const ConquerorsCourtApp());
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

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
    if (!_isFlutterTest) {
      PushService.init(navigatorKey: appNavigatorKey);
    }
  }

  @override
  void dispose() {
    unawaited(OrientationLock.pop());
    SecurityStore.lockedNotifier.removeListener(_handleLockChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (SecurityStore.autoLockSuppressed) return;
    if (state == AppLifecycleState.resumed) {
      PushService.resync();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      SecurityStore.lock();
    }
  }

  void _handleLockChange() {
    if (SecurityStore.isLocked) {
      appNavigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  bool _isBlockedRoute(String? name) {
  // Until a Title is claimed, only Home is allowed.
  // This prevents bypass via deep links or future routes.
  return name != null && name != '/';
}

  Route<dynamic> _routeFor(String? name) {
    switch (name) {
      case '/start':
        return MaterialPageRoute(builder: (_) => const StartChatScreen());
      case '/join':
        return MaterialPageRoute(builder: (_) => const JoinChatScreen());
      case '/chats':
        return MaterialPageRoute(builder: (_) => const MyChatsScreen());
      case '/':
      default:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "The Vault",
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFAD2FFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0014),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16001F),
          foregroundColor: Color(0xFFF5E1FF),
          centerTitle: true,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: Color(0xFFF5E1FF),
            fontWeight: FontWeight.w900,
          ),
          titleMedium: TextStyle(
            color: Color(0xFFE1A7FF),
          ),
          bodyMedium: TextStyle(
            color: Color(0xFFEBD3F5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF24002E),
            foregroundColor: const Color(0xFFF5E1FF),
            elevation: 3,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFD38CFF),
          ),
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final name = settings.name;

        if (SecurityStore.isLocked && name != '/') {
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
  }
}

