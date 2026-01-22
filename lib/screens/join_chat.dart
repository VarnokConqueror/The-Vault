import 'package:flutter/material.dart';
import '../state/identity_store.dart';

class JoinChatScreen extends StatefulWidget {
  static const route = '/join';

  const JoinChatScreen({super.key});

  @override
  State<JoinChatScreen> createState() => _JoinChatScreenState();
}

class _JoinChatScreenState extends State<JoinChatScreen> {
  final TextEditingController _inviteController = TextEditingController();

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

 void _join() {
    final invite = _inviteController.text.trim();
    if (invite.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Paste an invite first.")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Join flow coming next…")),
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
        title: const Text("Join a chat"),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Join with an invite",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                "Scan a QR code or paste an invite.",
              ),
              const SizedBox(height: 18),

              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("QR scanner coming next…")),
                  );
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text("Scan QR code"),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _inviteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: "Paste invite",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 14),

              FilledButton.icon(
                onPressed: _join,
                icon: const Icon(Icons.lock_open),
                label: const Text("Join"),
              ),

              const Spacer(),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Back"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
