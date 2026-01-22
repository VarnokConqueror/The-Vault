import 'package:flutter/material.dart';
import '../state/chat_store.dart';
import '../state/identity_store.dart';
import '../screens/contacts_screen.dart';
import '../screens/profile_screen.dart';
import 'chat_screen.dart';

class StartChatScreen extends StatefulWidget {
  const StartChatScreen({super.key});

  @override
  State<StartChatScreen> createState() => _StartChatScreenState();
}

class _StartChatScreenState extends State<StartChatScreen> {
  final _titleController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _create(BuildContext context) async {
    if (_creating) return;
    setState(() => _creating = true);
    final chat = await ChatStore.createChat(title: _titleController.text.trim());

    if (!context.mounted) return;
    setState(() => _creating = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Logic-only gate... prevents bypass via direct pushes / MaterialPageRoute.
    if (!IdentityStore.usernameCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open a Chat'),
        actions: [
          IconButton(
            tooltip: 'Contacts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactsScreen()),
            ),
            icon: const Icon(Icons.contacts_outlined),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Name the Chamber (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(context),
              decoration: const InputDecoration(
                hintText: 'Leave blank for Council Chamber...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _creating ? null : () => _create(context),
              child: const Text('Open Chamber'),
            ),
          ],
        ),
      ),
    );
  }
}




