import 'package:flutter/material.dart';
import 'screens/home.dart';
import 'screens/start_chat.dart';
import 'screens/join_chat.dart';
import 'screens/my_chats.dart';
import 'state/chat_store.dart';
import 'state/identity_store.dart';
import 'state/contacts_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatStore.init();
  await IdentityStore.init();
  await ContactsStore.init();
  runApp(const ConquerorsCourtApp());
}

class ConquerorsCourtApp extends StatelessWidget {
  const ConquerorsCourtApp({super.key});

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
      title: "Conqueror's Court",
      debugShowCheckedModeBanner: false,
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

