import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/ui/desktop_overlay_card.dart';
import '../core/invites/vault_chat_invite.dart';
import '../core/vault/vault_relay_client.dart';
import '../state/identity_store.dart';
import '../state/chat_store.dart';
import 'thread_screen.dart';

class JoinChatScreen extends StatefulWidget {
  static const route = '/join';
  final String? initialInvite;

  const JoinChatScreen({super.key, this.initialInvite});

  @override
  State<JoinChatScreen> createState() => _JoinChatScreenState();
}

class _JoinChatScreenState extends State<JoinChatScreen> {
  final TextEditingController _inviteController = TextEditingController();
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    final invite = (widget.initialInvite ?? '').trim();
    if (invite.isEmpty) return;
    _inviteController.text = invite;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _joining) return;
      _join();
    });
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  void _join() async {
    if (_joining) return;
    final invite = _inviteController.text.trim();
    if (invite.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Paste an invite first.")));
      return;
    }

    final parsed = VaultChatInvite.parse(invite);
    if (parsed == null || parsed.chatId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That invite doesn't look valid.")),
      );
      return;
    }

    setState(() => _joining = true);
    final joined = await VaultRelayClient.joinGroup(
      groupId: parsed.chatId,
      userId: IdentityStore.userId,
      title: parsed.title,
    );
    if (joined == null) {
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't join that group chat yet.")),
      );
      return;
    }
    final chat = await ChatStore.upsertChatFromInvite(
      chatId: parsed.chatId,
      title: joined.title.isEmpty ? parsed.title : joined.title,
      sharedSecret: parsed.sharedSecret,
    );

    if (!mounted) return;
    setState(() => _joining = false);
    if (useDesktopOverlayCards(context)) {
      await pushOrPresentDesktopCard<void>(
        context,
        settings: RouteSettings(name: '/thread/${chat.id}'),
        maxWidth: 760,
        builder: (_) => ThreadScreen(chatId: chat.id, chatTitle: chat.title),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(chatId: chat.id, chatTitle: chat.title),
      ),
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
      appBar: AppBar(title: const Text("Join Group")),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Join a group",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text("Scan a QR code or paste a group invite."),
                  const SizedBox(height: 14),

                  OutlinedButton.icon(
                    onPressed: () async {
                      final desktopCard = useDesktopOverlayCards(context);
                      final Future<String?> scanFuture = desktopCard
                          ? pushOrPresentDesktopCard<String>(
                              context,
                              settings: const RouteSettings(name: '/join/scan'),
                              maxWidth: 560,
                              builder: (_) => const _ChatInviteScanScreen(),
                            )
                          : Navigator.of(context).push<String>(
                              MaterialPageRoute(
                                builder: (_) => const _ChatInviteScanScreen(),
                              ),
                            );
                      final scanResult = await scanFuture;
                      if (scanResult == null || scanResult.trim().isEmpty) {
                        return;
                      }
                      _inviteController.text = scanResult.trim();
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text("Scan QR code"),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _inviteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Paste invite",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

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
        ),
      ),
    );
  }
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
      appBar: AppBar(title: const Text('Scan Invite')),
      body: MobileScanner(onDetect: _handleDetect),
    );
  }
}
