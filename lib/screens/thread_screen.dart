import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/message_store.dart';
import '../state/identity_store.dart';
import '../state/push_store.dart';
import '../state/chat_appearance_store.dart';
import '../state/contact_appearance_store.dart';
import '../state/security_store.dart';
import '../models/chat_message.dart';
import '../core/relay/relay_client.dart';
import '../core/tones/tone_storage.dart';

class ThreadScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final String? contactId;

  const ThreadScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    this.contactId,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  static const Color _pink = Color(0xFFFF2DAA);
  static const Color _incomingFill = Color(0xFF2A0A39);
  static const Color _screenBg = Color(0xFF140019);
  static const Color _overlayTint = Color(0xFF1A0024);

  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;
  bool _polling = false;
  int _pollDelayMs = 2000;

  int _lastRenderedCount = -1;
  String _lastRenderedLastId = '';
  int _lastMessageCount = 0;
  bool _didInitialScrollToBottom = false;
  bool _scrollToBottomScheduled = false;

  @override
  void initState() {
    super.initState();
    if (RelayClient.logSuccess) {
      debugPrint('[Relay] ThreadScreen init chatId=${widget.chatId}');
    }
    _scheduleNextPoll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _audioPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(Duration(milliseconds: _pollDelayMs), _pollRelay);
  }

  Future<void> _pollRelay() async {
    if (_polling) return;
    _polling = true;
    var ok = false;
    try {
      final mailbox = await RelayClient.fetchMailbox(mailboxId: widget.chatId);
      if (mailbox == null) {
        if (RelayClient.logSuccess) {
          debugPrint('[Relay] poll mailbox=${widget.chatId} -> fetch failed');
        }
        return;
      }
      ok = true;

      if (RelayClient.logSuccess) {
        debugPrint(
          '[Relay] poll mailbox=${widget.chatId} -> envelopes=${mailbox.envelopes.length}',
        );
      }
      if (mailbox.envelopes.isEmpty) {
        return;
      }

      final existing = MessageStore.getMessagesForChat(widget.chatId);
      final knownIds = existing.map((m) => m.id).toSet();
      final known = existing.map(_messageSignature).toSet();
      final byId = <String, ChatMessage>{for (final m in existing) m.id: m};
      final myId = IdentityStore.publicId.trim();
      bool isSelfSender(String senderId) {
        final s = senderId.trim();
        if (s.isEmpty) return false;
        if (s == 'local') return true;
        return myId.isNotEmpty && s == myId;
      }

      final ackIds = <String>[];

      var decodedOk = 0;
      var decodedFailed = 0;
      var mismatchChat = 0;
      String? mismatchExample;
      var dupId = 0;
      var dupSig = 0;
      var skipSelfAck = 0;
      var stored = 0;
      var receivedFromOther = false;

      for (final envelope in mailbox.envelopes) {
        if (knownIds.contains(envelope.envelopeId)) {
          dupId += 1;
          final local = byId[envelope.envelopeId];
          if (local != null && isSelfSender(local.senderId)) {
            // Shared mailbox: don't ack our own outbound envelope, or other
            // participants may miss it before they poll.
            skipSelfAck += 1;
            continue;
          }
          ackIds.add(envelope.envelopeId);
          continue;
        }
        final relayMessage = RelayClient.decodePayload(envelope);
        if (relayMessage == null) {
          decodedFailed += 1;
          ackIds.add(envelope.envelopeId);
          continue;
        }
        decodedOk += 1;
        if (relayMessage.chatId != widget.chatId) {
          mismatchChat += 1;
          mismatchExample ??= relayMessage.chatId;
          ackIds.add(envelope.envelopeId);
          continue;
        }
        final isSelf = isSelfSender(relayMessage.senderId);
        final signature = _relaySignature(relayMessage);
        if (known.contains(signature)) {
          dupSig += 1;
          if (isSelf) {
            skipSelfAck += 1;
            continue;
          }
          ackIds.add(envelope.envelopeId);
          continue;
        }
        final added = await MessageStore.addIncomingMessage(
          chatId: relayMessage.chatId,
          senderId: relayMessage.senderId,
          body: relayMessage.body,
          createdAt: relayMessage.createdAt,
          id: envelope.envelopeId,
        );
        if (added != null) {
          stored += 1;
          if (!isSelf) {
            receivedFromOther = true;
          }
        }
        known.add(signature);
        knownIds.add(envelope.envelopeId);
        if (isSelf) {
          skipSelfAck += 1;
          continue;
        }
        ackIds.add(envelope.envelopeId);
      }

      if (RelayClient.logSuccess) {
        final mismatchNote = mismatchExample == null
            ? ''
            : ' mismatchExample=$mismatchExample';
        debugPrint(
          '[Relay] poll mailbox=${widget.chatId} decoded=$decodedOk decodeFailed=$decodedFailed stored=$stored ack=${ackIds.length} dupId=$dupId dupSig=$dupSig skipSelfAck=$skipSelfAck mismatchChat=$mismatchChat$mismatchNote',
        );
      }

      if (receivedFromOther) {
        await _playNotificationTone();
      }

      final ackOk = await RelayClient.ackEnvelopes(
        mailboxId: widget.chatId,
        envelopeIds: ackIds,
      );
      if (RelayClient.logSuccess) {
        debugPrint(
          '[Relay] poll mailbox=${widget.chatId} -> ackOk=$ackOk ack=${ackIds.length}',
        );
      }
    } catch (error) {
      if (RelayClient.logSuccess) {
        debugPrint('[Relay] poll mailbox=${widget.chatId} exception: $error');
      }
      // Best-effort only.
    } finally {
      _polling = false;
      if (mounted) {
        _handleBackoff(success: ok);
        _scheduleNextPoll();
      }
    }
  }

  void _handleBackoff({required bool success}) {
    if (success) {
      _pollDelayMs = 2000;
      return;
    }
    final nextDelay = _pollDelayMs * 2;
    _pollDelayMs = nextDelay.clamp(2000, 30000).toInt();
  }

  String _messageSignature(ChatMessage message) {
    final stamp = message.createdAt.millisecondsSinceEpoch;
    return '${message.chatId}|${message.senderId}|$stamp|${message.body}';
  }

  String _relaySignature(RelayMessage message) {
    final stamp = message.createdAt.millisecondsSinceEpoch;
    return '${message.chatId}|${message.senderId}|$stamp|${message.body}';
  }

  String? _resolveToneUri() {
    final chatTone =
        ChatAppearanceStore.getForChat(widget.chatId)?.toneUri?.trim();
    if (chatTone != null && chatTone.isNotEmpty) {
      return chatTone;
    }

    final contactId = widget.contactId?.trim();
    if (contactId == null || contactId.isEmpty) return null;
    final contactTone =
        ContactAppearanceStore.getForContact(contactId)?.toneUri?.trim();
    if (contactTone != null && contactTone.isNotEmpty) {
      return contactTone;
    }

    return null;
  }

  Future<void> _playNotificationTone() async {
    final toneUri = _resolveToneUri();
    if (toneUri == null || toneUri.trim().isEmpty) return;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    try {
      await _audioPlayer.play(DeviceFileSource(toneUri));
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final senderId = IdentityStore.publicId.trim().isEmpty
        ? 'local'
        : IdentityStore.publicId;

    final message = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: text,
    );

    if (message == null) return;
    RelayClient.sendMessage(
      RelayMessage(
        id: message.id,
        chatId: message.chatId,
        senderId: message.senderId,
        senderName: IdentityStore.displayName,
        body: message.body,
        createdAt: message.createdAt,
      ),
    );

    _controller.clear();
    if (!mounted) return;
    setState(() {});
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final muted = PushStore.isMuted(widget.chatId);
        final chatAppearance = ChatAppearanceStore.getForChat(widget.chatId);
        final chatToneUri = chatAppearance?.toneUri?.trim();
        final chatToneName = chatAppearance?.toneName?.trim();
        final contactId = widget.contactId?.trim();
        final contactAppearance = (contactId == null || contactId.isEmpty)
            ? null
            : ContactAppearanceStore.getForContact(contactId);
        final contactToneUri = contactAppearance?.toneUri?.trim();
        final contactToneName = contactAppearance?.toneName?.trim();
        final hasChatTone = chatToneUri != null && chatToneUri.isNotEmpty;
        final hasContactTone = !hasChatTone &&
            contactToneUri != null &&
            contactToneUri.isNotEmpty;
        final hasAnyTone = hasChatTone || hasContactTone;
        String shortTone(String uri) {
          final trimmed = uri.trim();
          if (trimmed.isEmpty) return '';
          final withoutQuery = trimmed.split('?').first;
          final parts = withoutQuery
              .split(RegExp(r'[\\\\/]+'))
              .where((p) => p.isNotEmpty)
              .toList();
          return parts.isEmpty ? trimmed : parts.last;
        }
        final effectiveToneName = hasChatTone
            ? (chatToneName ?? shortTone(chatToneUri))
            : hasContactTone
                ? (contactToneName ?? shortTone(contactToneUri))
                : 'Default';
        final toneSubtitle = hasChatTone
            ? effectiveToneName
            : hasContactTone
                ? '$effectiveToneName (from contact)'
                : 'Default';
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                title: const Text('Copy Invite'),
                subtitle: const Text('Share this chat with another device'),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _buildInvitePayload()),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite copied')),
                    );
                  }
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
              ListTile(
                title: const Text('Show Invite QR'),
                onTap: () async {
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                  await Future<void>.delayed(const Duration(milliseconds: 120));
                  if (!mounted) return;
                  await _showInviteQr();
                },
              ),
              ListTile(
                title: const Text('Set Background'),
                onTap: () async {
                  final result = await SecurityStore.runWithAutoLockSuppressed(
                    () => FilePicker.platform.pickFiles(type: FileType.image),
                  );
                  final path = result?.files.single.path;
                  if (path != null) {
                    await ChatAppearanceStore.setBackground(
                      widget.chatId,
                      path,
                    );
                  }
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
              ListTile(
                title: const Text('Clear Background'),
                onTap: () async {
                  await ChatAppearanceStore.setBackground(widget.chatId, null);
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
              ListTile(
                title: const Text('Notification Tone'),
                subtitle: Text(toneSubtitle),
                trailing: hasAnyTone
                    ? IconButton(
                        tooltip: 'Preview tone',
                        icon: const Icon(Icons.play_arrow_rounded),
                        onPressed: _playNotificationTone,
                      )
                    : null,
                onTap: () async {
                  final result = await SecurityStore.runWithAutoLockSuppressed(
                    () => FilePicker.platform.pickFiles(
                      type: FileType.audio,
                      withData: true,
                    ),
                  );
                  final file = result?.files.single;
                  if (file != null) {
                    final stored = await ToneStorage.storePickedTone(
                      key: 'chat_${widget.chatId}',
                      file: file,
                    );
                    if (stored != null) {
                      await ChatAppearanceStore.setTone(
                        widget.chatId,
                        stored.uri,
                        name: stored.name,
                      );
                    }
                  }
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
              if (hasChatTone)
                ListTile(
                  title: const Text('Clear Custom Tone'),
                  subtitle: const Text('Revert to contact/default'),
                  onTap: () async {
                    await ChatAppearanceStore.setTone(widget.chatId, null);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
              const Divider(height: 1),
              ListTile(
                title: Text(
                  muted ? 'Unmute Push Notifications' : 'Mute Push Notifications',
                ),
                subtitle: Text(
                  muted
                      ? 'Notifications enabled for this chat'
                      : 'No system notifications for this chat',
                ),
                onTap: () async {
                  final navigator = Navigator.of(sheetContext);
                  final messenger = ScaffoldMessenger.of(context);
                  await PushStore.setMuted(widget.chatId, !muted);
                  if (sheetContext.mounted) {
                    navigator.pop();
                  }
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        !muted ? 'Chat muted' : 'Chat unmuted',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _buildInvitePayload() {
    final payload = <String, dynamic>{
      'type': 'cc-chat',
      'chatId': widget.chatId,
      'title': widget.chatTitle,
    };
    return jsonEncode(payload);
  }

  Future<void> _showInviteQr() async {
    final payload = _buildInvitePayload();
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Chat Invite'),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Scan to join this chat.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final s = local.toIso8601String();
    return s.replaceFirst('T', ' ').split('.').first;
  }

  String _snip(String text, {int max = 60}) {
    final collapsed = text.replaceAll('\n', ' ').trim();
    if (collapsed.length <= max) return collapsed;
    return '${collapsed.substring(0, max)}...';
  }

  void _logRenderedMessages(List<ChatMessage> messages) {
    if (!RelayClient.logSuccess) return;
    final count = messages.length;
    final lastId = messages.isEmpty ? '' : messages.last.id;
    if (count == _lastRenderedCount && lastId == _lastRenderedLastId) return;
    _lastRenderedCount = count;
    _lastRenderedLastId = lastId;

    if (messages.isEmpty) {
      debugPrint(
        '[Relay] ThreadScreen render chatId=${widget.chatId} messages=0',
      );
      return;
    }
    final last = messages.last;
    debugPrint(
      '[Relay] ThreadScreen render chatId=${widget.chatId} messages=$count lastId=${last.id} lastAt=${last.createdAt.toIso8601String()} lastSender=${last.senderId} lastBody="${_snip(last.body)}"',
    );
  }

  void _scheduleScrollToBottom({
    required bool jump,
    required bool onlyIfNearBottom,
  }) {
    if (_scrollToBottomScheduled) return;
    _scrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomScheduled = false;
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final p = _scrollController.position;
      if (!p.hasPixels) return;
      if (onlyIfNearBottom) {
        // Don't yank the user down if they scrolled up to read history.
        final nearBottom = (p.maxScrollExtent - p.pixels) <= 200;
        if (!nearBottom) return;
      }
      if (jump) {
        _scrollController.jumpTo(p.maxScrollExtent);
        return;
      }
      _scrollController.animateTo(
        p.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleStickyScroll(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      _lastMessageCount = 0;
      _didInitialScrollToBottom = false;
      return;
    }

    if (!_didInitialScrollToBottom) {
      // Chat UX: open at the latest message, not at the top of history.
      _didInitialScrollToBottom = true;
      _lastMessageCount = messages.length;
      _scheduleScrollToBottom(jump: true, onlyIfNearBottom: false);
      return;
    }

    final count = messages.length;
    final grew = count > _lastMessageCount;
    _lastMessageCount = count;
    if (!grew) return;

    // Keep pinned to the bottom while the user is already "at the bottom".
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenBg,
      appBar: AppBar(
        title: Text(widget.chatTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: ChatAppearanceStore.appearancesNotifier,
        builder: (context, _, __) {
          final appearance = ChatAppearanceStore.getForChat(widget.chatId);
          final backgroundUri = appearance?.backgroundUri?.trim();

          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: _screenBg),
                ),
              ),
              if (backgroundUri != null && backgroundUri.isNotEmpty)
                Positioned.fill(
                  child: Image.file(
                    File(backgroundUri),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Positioned.fill(
                child: Container(color: _overlayTint.withValues(alpha: 0.65)),
              ),
              Column(
                children: [
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: MessageStore.messagesNotifier,
                      builder: (context, _, __) {
                        final messages = MessageStore.getMessagesForChat(
                          widget.chatId,
                        );
                        _logRenderedMessages(messages);
                        _handleStickyScroll(messages);

                        if (messages.isEmpty) {
                          return const Center(child: Text('No messages yet'));
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMe =
                                message.senderId == IdentityStore.publicId ||
                                message.senderId == 'local';
                            final bubbleColor = isMe ? _pink : _incomingFill;
                            final bubbleBorder = isMe
                                ? null
                                : Border.all(color: _pink, width: 1.2);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.74,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: BorderRadius.circular(16),
                                      border: bubbleBorder,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isMe
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          message.body,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTime(message.createdAt),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _pink,
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                              ),
                              child: const Text('Send'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
