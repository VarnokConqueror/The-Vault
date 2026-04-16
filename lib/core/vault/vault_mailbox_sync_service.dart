import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../state/chat_store.dart';
import '../../state/chat_unread_store.dart';
import '../../state/identity_store.dart';
import '../../state/message_store.dart';
import '../../state/vault_store.dart';
import '../media/incoming_attachment_ingest.dart';
import '../push/push_service.dart';
import '../relay/relay_client.dart';
import '../voice_notes/voice_note_storage.dart';
import 'direct_thread_routing.dart';
import 'vault_bridge.dart';
import 'vault_models.dart';
import 'vault_relay_client.dart';

class VaultMailboxSyncService {
  static const Duration _pollInterval = Duration(seconds: 2);
  static final VaultBridge _vaultBridge = defaultVaultBridge;
  static final Set<String> _vaultSessionReadyPeers = <String>{};
  static final Set<String> _sentDeliveredReceiptIds = <String>{};

  static bool _initialized = false;
  static bool _active = false;
  static bool _polling = false;
  static bool _suppressStartupDeliveredReceipts = false;
  static Timer? _pollTimer;

  static bool get ownsDeviceMailboxPolling => _initialized && _active;
  static bool get isRunning => ownsDeviceMailboxPolling;

  static bool get isInitialized => _initialized;
  static bool get isActive => _initialized && _active;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _active = true;
    _suppressStartupDeliveredReceipts = _shouldSuppressStartupReceipts;
    unawaited(pollNow());
  }

  static void resume() {
    if (!_initialized) return;
    _active = true;
    _suppressStartupDeliveredReceipts = _shouldSuppressStartupReceipts;
    unawaited(pollNow());
  }

  static void pause() {
    _active = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static Future<void> pollNow() async {
    if (!_initialized || !_active || _polling) return;
    _polling = true;
    try {
      await _pollMailbox();
    } finally {
      _polling = false;
      _scheduleNextPoll();
    }
  }

  static void _scheduleNextPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_initialized || !_active) return;
    _pollTimer = Timer(_pollInterval, () {
      unawaited(pollNow());
    });
  }

  static Future<void> _pollMailbox() async {
    await VaultStore.ensureReady(bridge: _vaultBridge);
    final localAddress = VaultStore.localAddress;
    final mailboxId = VaultStore.deviceMailboxId.trim();
    if (localAddress == null || mailboxId.isEmpty) {
      return;
    }

    var hydratedMailbox = false;
    final suppressDeliveredReceiptsThisPoll = _suppressStartupDeliveredReceipts;
    final mailbox = await VaultRelayClient.fetchMailbox(mailboxId: mailboxId);
    hydratedMailbox = true;
    if (mailbox == null || mailbox.envelopes.isEmpty) {
      if (hydratedMailbox) {
        _suppressStartupDeliveredReceipts = false;
      }
      return;
    }

    final existing = MessageStore.messages;
    final knownIds = existing.map((message) => message.id).toSet();
    final knownSignatures = existing.map(_messageSignature).toSet();
    final ackIds = <String>[];

    for (final envelope in mailbox.envelopes) {
      if (knownIds.contains(envelope.envelopeId)) {
        ackIds.add(envelope.envelopeId);
        continue;
      }

      RelayDecodeResult decodeResult;
      try {
        decodeResult = await _decodeVaultEnvelope(
          localAddress: localAddress,
          envelope: envelope,
        );
      } on PlatformException catch (error) {
        if (error.code == 'UNIMPLEMENTED') {
          return;
        }
        debugPrint('[VaultSync] decrypt failed: ${error.message}');
        continue;
      } catch (error) {
        debugPrint('[VaultSync] decrypt failed: $error');
        continue;
      }

      final relayMessage = decodeResult.message;
      if (relayMessage == null) {
        ackIds.add(envelope.envelopeId);
        continue;
      }

      final resolvedChatId = await _resolveIncomingChatId(
        relayMessage,
        source: envelope.source,
      );
      final signature = _relaySignature(
        relayMessage,
        chatIdOverride: resolvedChatId,
      );
      if (knownSignatures.contains(signature)) {
        ackIds.add(envelope.envelopeId);
        continue;
      }

      final type = relayMessage.type.trim().isEmpty
          ? RelayMessage.typeText
          : relayMessage.type.trim();

      if (type == RelayMessage.typeReceipt) {
        await MessageStore.applyReceipt(
          chatId: resolvedChatId,
          messageId: (relayMessage.receiptMessageId ?? '').trim(),
          kind: (relayMessage.receiptKind ?? '').trim(),
          receiptAt: relayMessage.createdAt,
        );
        knownSignatures.add(signature);
        ackIds.add(envelope.envelopeId);
        continue;
      }
      if (type == RelayMessage.typeReaction) {
        await MessageStore.applyReaction(
          chatId: resolvedChatId,
          messageId: (relayMessage.reactionTargetMessageId ?? '').trim(),
          senderId: relayMessage.senderId,
          emoji: (relayMessage.reactionEmoji ?? '').trim(),
          action: (relayMessage.reactionAction ?? '').trim(),
          reactedAt: relayMessage.createdAt,
        );
        knownSignatures.add(signature);
        ackIds.add(envelope.envelopeId);
        continue;
      }

      ChatMessage? added;
      IncomingAttachmentIngestResult? attachmentIngest;
      final replyTo = _replyPreviewFromRelay(relayMessage);
      if (type == RelayMessage.typeVoice &&
          (relayMessage.voiceB64 ?? '').trim().isNotEmpty) {
        String? voicePath;
        try {
          final bytes = base64Decode(relayMessage.voiceB64!.trim());
          voicePath = await VoiceNoteStorage.storeBytes(
            id: envelope.envelopeId,
            bytes: bytes,
            mime: relayMessage.voiceMime,
          );
        } catch (_) {}
        if (voicePath != null && voicePath.trim().isNotEmpty) {
          added = await MessageStore.addIncomingMessage(
            chatId: resolvedChatId,
            senderId: relayMessage.senderId,
            body: relayMessage.body,
            createdAt: relayMessage.createdAt,
            id: envelope.envelopeId,
            type: ChatMessage.typeVoice,
            voicePath: voicePath,
            voiceMime: relayMessage.voiceMime,
            voiceDurationMs: relayMessage.voiceDurationMs,
            replyTo: replyTo,
          );
        }
      } else if (type == RelayMessage.typeSticker) {
        added = await MessageStore.addIncomingMessage(
          chatId: resolvedChatId,
          senderId: relayMessage.senderId,
          body: relayMessage.body,
          createdAt: relayMessage.createdAt,
          id: envelope.envelopeId,
          type: ChatMessage.typeSticker,
          stickerPackId: relayMessage.stickerPackId,
          stickerId: relayMessage.stickerId,
          stickerVariant: relayMessage.stickerVariant,
          replyTo: replyTo,
        );
      } else if (type == RelayMessage.typeAttachmentChunk) {
        attachmentIngest = await _handleIncomingAttachmentChunk(
          relayMessage,
          resolvedChatId: resolvedChatId,
        );
        added = attachmentIngest.message;
      } else if (type == RelayMessage.typeAttachmentManifest) {
        attachmentIngest = await _handleIncomingAttachmentManifest(
          relayMessage,
          resolvedChatId: resolvedChatId,
        );
        added = attachmentIngest.message;
      } else {
        added = await MessageStore.addIncomingMessage(
          chatId: resolvedChatId,
          senderId: relayMessage.senderId,
          body: relayMessage.body,
          createdAt: relayMessage.createdAt,
          id: envelope.envelopeId,
          replyTo: replyTo,
        );
      }
      if (attachmentIngest != null && !attachmentIngest.shouldAck) {
        continue;
      }

      if (added != null) {
        knownIds.add(envelope.envelopeId);
        if (!_isSelfSender(relayMessage.senderId) &&
            !suppressDeliveredReceiptsThisPoll) {
          final incomingMessageId = relayMessage.id.trim().isEmpty
              ? envelope.envelopeId
              : relayMessage.id.trim();
          unawaited(
            _sendDeliveredReceipt(
              source: envelope.source,
              resolvedChatId: resolvedChatId,
              messageId: incomingMessageId,
            ),
          );
        }
        final incomingMessageId = relayMessage.id.trim().isEmpty
            ? envelope.envelopeId
            : relayMessage.id.trim();
        final shouldNotify = await ChatUnreadStore.recordIncomingMessage(
          chatId: resolvedChatId,
          senderId: relayMessage.senderId,
          messageId: incomingMessageId,
        );
        if (shouldNotify && _supportsDesktopNotifications) {
          final chat = ChatStore.getChat(resolvedChatId);
          final senderName = relayMessage.senderName.trim();
          final fallbackTitle = chat?.title.trim() ?? '';
          final title = senderName.isNotEmpty
              ? senderName
              : (fallbackTitle.isNotEmpty ? fallbackTitle : 'The Vault');
          await PushService.showDesktopMessageNotification(
            mailboxId: resolvedChatId,
            title: title,
            body: _desktopPreviewForMessage(relayMessage),
            senderId: relayMessage.senderId,
            senderName: relayMessage.senderName,
            threadChatId: resolvedChatId,
          );
        }
      }
      knownSignatures.add(signature);
      ackIds.add(envelope.envelopeId);
    }

    if (ackIds.isNotEmpty) {
      await VaultRelayClient.ackMailbox(
        mailboxId: mailboxId,
        envelopeIds: ackIds,
      );
    }
    if (hydratedMailbox) {
      _suppressStartupDeliveredReceipts = false;
    }
  }

  static bool get _supportsDesktopNotifications =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get _shouldSuppressStartupReceipts =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static String _desktopPreviewForMessage(RelayMessage relayMessage) {
    final type = relayMessage.type.trim().toLowerCase();
    if (type == RelayMessage.typeVoice) return 'Voice note';
    if (type == RelayMessage.typeSticker) return 'Sticker';
    if (type == RelayMessage.typeAttachmentChunk ||
        type == RelayMessage.typeAttachmentManifest) {
      final mime = (relayMessage.attachmentMime ?? '').trim().toLowerCase();
      if (mime.startsWith('image/')) return 'Photo';
      if (mime.startsWith('video/')) return 'Video';
      final name = (relayMessage.attachmentName ?? '').trim();
      return name.isEmpty ? 'Attachment' : name;
    }
    final body = relayMessage.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return body.isEmpty ? 'New message' : body;
  }

  static bool _isSelfSender(String senderId) {
    final sender = senderId.trim();
    if (sender.isEmpty || sender == 'local') return true;
    final publicId = IdentityStore.publicId.trim();
    if (publicId.isNotEmpty && sender == publicId) return true;
    final userId = IdentityStore.userId.trim();
    return userId.isNotEmpty && sender == userId;
  }

  static String _vaultPeerKey(VaultAddress address) =>
      '${address.userId}:${address.deviceId}';

  static bool _isVaultBridgeRecoverableError(PlatformException error) {
    return error.code == 'vault_no_session' ||
        error.code == 'vault_invalid_key_id' ||
        error.code == 'vault_reused_base_key' ||
        error.code == 'vault_bridge_error';
  }

  static Future<bool> _ensureVaultSession({
    required VaultAddress localAddress,
    required VaultAddress peerAddress,
  }) async {
    final peerKey = _vaultPeerKey(peerAddress);
    if (_vaultSessionReadyPeers.contains(peerKey)) {
      return true;
    }

    final bundle = await VaultRelayClient.fetchPreKeyBundle(peerAddress);
    if (bundle == null) {
      return false;
    }

    try {
      await _vaultBridge.processPreKeyBundle(
        localAddress: localAddress,
        bundle: bundle,
      );
    } on PlatformException catch (error) {
      if (error.code == 'UNIMPLEMENTED') {
        return false;
      }
      rethrow;
    }

    _vaultSessionReadyPeers.add(peerKey);
    return true;
  }

  static Future<VaultCiphertext?> _encryptVaultPayloadForPeer({
    required VaultAddress localAddress,
    required VaultAddress peerAddress,
    required List<int> plaintext,
  }) async {
    final sessionReady = await _ensureVaultSession(
      localAddress: localAddress,
      peerAddress: peerAddress,
    );
    if (!sessionReady) {
      return null;
    }

    Future<VaultCiphertext> encryptOnce() {
      return _vaultBridge.encrypt(
        localAddress: localAddress,
        destination: peerAddress,
        plaintext: plaintext,
      );
    }

    try {
      return await encryptOnce();
    } on PlatformException catch (error) {
      if (error.code == 'UNIMPLEMENTED') {
        return null;
      }
      if (!_isVaultBridgeRecoverableError(error)) {
        rethrow;
      }
      if (error.code == 'vault_bridge_error') {
        try {
          await _vaultBridge.reset();
        } catch (_) {}
      }
      final peerKey = _vaultPeerKey(peerAddress);
      _vaultSessionReadyPeers.remove(peerKey);
      try {
        await _vaultBridge.archiveSession(
          localAddress: localAddress,
          remoteAddress: peerAddress,
        );
      } on PlatformException catch (archiveError) {
        if (archiveError.code == 'UNIMPLEMENTED') {
          return null;
        }
      } catch (_) {}
      final retriedSession = await _ensureVaultSession(
        localAddress: localAddress,
        peerAddress: peerAddress,
      );
      if (!retriedSession) {
        return null;
      }
      return encryptOnce();
    }
  }

  static Future<void> _sendDeliveredReceipt({
    required VaultAddress source,
    required String resolvedChatId,
    required String messageId,
  }) async {
    final localAddress = VaultStore.localAddress;
    if (localAddress == null) return;
    final cleanMessageId = messageId.trim();
    if (cleanMessageId.isEmpty) return;
    final receiptKey = '${source.userId}:${source.deviceId}|$cleanMessageId';
    if (_sentDeliveredReceiptIds.contains(receiptKey)) return;
    final receiptDigest = sha256
        .convert(
          utf8.encode(
            'receipt|delivered|$resolvedChatId|${IdentityStore.publicId.trim()}|${source.userId}|${source.deviceId}|$cleanMessageId',
          ),
        )
        .toString();

    final receipt = RelayMessage(
      id: 'rcpt_$receiptDigest',
      chatId: resolvedChatId,
      senderId: IdentityStore.publicId.trim().isEmpty
          ? 'local'
          : IdentityStore.publicId.trim(),
      senderName: IdentityStore.displayName,
      directPeerId: source.userId.trim().isEmpty ? null : source.userId.trim(),
      type: RelayMessage.typeReceipt,
      body: '',
      receiptKind: RelayMessage.receiptKindDelivered,
      receiptMessageId: cleanMessageId,
      createdAt: DateTime.now(),
    );

    try {
      final plaintext = RelayClient.encodeClearPayloadBytes(receipt);
      final ciphertext = await _encryptVaultPayloadForPeer(
        localAddress: localAddress,
        peerAddress: source,
        plaintext: plaintext,
      );
      if (ciphertext == null) return;
      final result = await VaultRelayClient.sendMessages(
        source: localAddress,
        messages: [
          VaultOutboundEnvelope(destination: source, ciphertext: ciphertext),
        ],
        clientMessageId: receipt.id,
      );
      if (result == null || !result.ok || result.accepted.isEmpty) {
        return;
      }
      _sentDeliveredReceiptIds.add(receiptKey);
      if (_sentDeliveredReceiptIds.length > 1000) {
        _sentDeliveredReceiptIds.remove(_sentDeliveredReceiptIds.first);
      }
    } on PlatformException catch (error) {
      if (error.code != 'UNIMPLEMENTED') {
        debugPrint('[VaultSync] delivered receipt failed: ${error.message}');
      }
    } catch (error) {
      debugPrint('[VaultSync] delivered receipt failed: $error');
    }
  }

  static Future<RelayDecodeResult> _decodeVaultEnvelope({
    required VaultAddress localAddress,
    required VaultInboundEnvelope envelope,
  }) async {
    final clearBytes = await _vaultBridge.decrypt(
      localAddress: localAddress,
      envelope: envelope,
    );
    return RelayClient.decodePayloadBytes(
      Uint8List.fromList(clearBytes),
      fallbackCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        envelope.serverTimestampMs,
      ),
      fallbackEnvelopeId: envelope.envelopeId,
      encrypted: true,
    );
  }

  static Future<String> _resolveIncomingChatId(
    RelayMessage relayMessage, {
    required VaultAddress source,
  }) async {
    return resolveIncomingVaultChatId(
      rawChatId: relayMessage.chatId,
      directPeerHint: relayMessage.directPeerId ?? '',
      senderId: relayMessage.senderId,
      senderName: relayMessage.senderName,
      sourceUserId: source.userId,
      sourceAddress: source,
      fallbackChatId: relayMessage.chatId,
    );
  }

  static Future<IncomingAttachmentIngestResult> _handleIncomingAttachmentChunk(
    RelayMessage relayMessage, {
    required String resolvedChatId,
  }) async {
    return IncomingAttachmentIngest.ingestChunk(
      relayMessage,
      resolvedChatId: resolvedChatId,
    );
  }

  static Future<IncomingAttachmentIngestResult>
  _handleIncomingAttachmentManifest(
    RelayMessage relayMessage, {
    required String resolvedChatId,
  }) async {
    return IncomingAttachmentIngest.ingestManifest(
      relayMessage,
      resolvedChatId: resolvedChatId,
    );
  }

  static MessageReplyPreview? _replyPreviewFromRelay(
    RelayMessage relayMessage,
  ) {
    final messageId = (relayMessage.replyToMessageId ?? '').trim();
    final senderId = (relayMessage.replyToSenderId ?? '').trim();
    if (messageId.isEmpty || senderId.isEmpty) {
      return null;
    }
    final replyType = (relayMessage.replyToType ?? '').trim();
    return MessageReplyPreview(
      messageId: messageId,
      senderId: senderId,
      type: replyType.isEmpty ? ChatMessage.typeText : replyType,
      previewText: (relayMessage.replyToPreview ?? '').trim(),
    );
  }

  static String _messageSignature(ChatMessage message) {
    final stamp = message.createdAt.millisecondsSinceEpoch;
    final type = message.type.trim().isEmpty
        ? ChatMessage.typeText
        : message.type.trim();
    final dur = message.voiceDurationMs ?? 0;
    final sticker = message.isSticker
        ? '${message.stickerPackId}|${message.stickerId}|${message.stickerVariant ?? ''}'
        : '';
    final attachment = message.isAttachment
        ? '${message.attachmentId}|${message.attachmentName}|${message.attachmentSize ?? 0}'
        : '';
    return '${message.chatId}|${message.senderId}|$stamp|$type|$dur|$sticker|$attachment|${message.body}';
  }

  static String _relaySignature(
    RelayMessage message, {
    String? chatIdOverride,
  }) {
    final stamp = message.createdAt.millisecondsSinceEpoch;
    final chatId = (chatIdOverride ?? message.chatId).trim();
    final type = message.type.trim().isEmpty
        ? RelayMessage.typeText
        : message.type.trim();
    final dur = message.voiceDurationMs ?? 0;
    final voiceLen = (message.voiceB64 ?? '').length;
    final sticker =
        '${message.stickerPackId ?? ''}|${message.stickerId ?? ''}|${message.stickerVariant ?? ''}';
    final attachment =
        '${message.attachmentId ?? ''}|${message.attachmentChunkIndex ?? -1}|${message.attachmentChunkCount ?? -1}|${message.attachmentHash ?? ''}';
    final receipt =
        '${message.receiptKind ?? ''}|${message.receiptMessageId ?? ''}';
    final reply =
        '${message.replyToMessageId ?? ''}|${message.replyToSenderId ?? ''}|${message.replyToPreview ?? ''}';
    final reaction =
        '${message.reactionTargetMessageId ?? ''}|${message.reactionEmoji ?? ''}|${message.reactionAction ?? ''}';
    return '$chatId|${message.senderId}|$stamp|$type|$dur|$voiceLen|$sticker|$attachment|$receipt|$reply|$reaction|${message.body}';
  }
}
