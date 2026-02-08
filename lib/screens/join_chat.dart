import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../state/identity_store.dart';
import '../state/chat_store.dart';
import 'thread_screen.dart';

class JoinChatScreen extends StatefulWidget {
  static const route = '/join';

  const JoinChatScreen({super.key});

  @override
  State<JoinChatScreen> createState() => _JoinChatScreenState();
}

class _JoinChatScreenState extends State<JoinChatScreen> {
  final TextEditingController _inviteController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  void _join() async {
    if (_joining) return;
    final invite = _inviteController.text.trim();
    if (invite.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Paste an invite first.")),
      );
      return;
    }

    final parsed = _parseInvite(invite);
    if (parsed == null || parsed.chatId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That invite doesn't look valid.")),
      );
      return;
    }

    setState(() => _joining = true);
    final chat = await ChatStore.upsertChatFromInvite(
      chatId: parsed.chatId,
      title: parsed.title,
    );

    if (!mounted) return;
    setState(() => _joining = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(
          chatId: chat.id,
          chatTitle: chat.title,
        ),
      ),
    );
  }

  _ChatInvite? _parseInvite(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final chatId =
              (map['chatId'] ?? map['id'] ?? map['chat_id'] ?? '').toString();
          final title = (map['title'] ?? '').toString();
          if (chatId.trim().isNotEmpty) {
            return _ChatInvite(chatId: chatId.trim(), title: title.trim());
          }
        }
      } catch (_) {}
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.hasScheme || trimmed.contains('/'))) {
      final queryId =
          uri.queryParameters['chatId'] ?? uri.queryParameters['id'];
      final title = uri.queryParameters['title'];
      if (queryId != null && queryId.trim().isNotEmpty) {
        return _ChatInvite(chatId: queryId.trim(), title: title?.trim());
      }
      if (uri.pathSegments.isNotEmpty) {
        return _ChatInvite(
          chatId: uri.pathSegments.last.trim(),
          title: title?.trim(),
        );
      }
    }

    return _ChatInvite(chatId: trimmed, title: null);
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
                onPressed: () async {
                  final scanResult = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _ChatInviteScanScreen(),
                    ),
                  );
                  if (scanResult == null || scanResult.trim().isEmpty) {
                    return;
                  }
                  _inviteController.text = scanResult.trim();
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
                onPressed: _joining ? null : _join,
                icon: const Icon(Icons.lock_open),
                label: Text(_joining ? "Joining..." : "Join"),
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

class _ChatInvite {
  final String chatId;
  final String? title;

  const _ChatInvite({required this.chatId, this.title});
}

class _ChatInviteScanScreen extends StatefulWidget {
  const _ChatInviteScanScreen();

  @override
  State<_ChatInviteScanScreen> createState() => _ChatInviteScanScreenState();
}

class _ChatInviteScanScreenState extends State<_ChatInviteScanScreen> {
  bool _hasScanned = false;

  void _handleDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    _hasScanned = true;
    Navigator.pop(context, raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Invite'),
      ),
      body: MobileScanner(
        onDetect: _handleDetect,
      ),
    );
  }
}
