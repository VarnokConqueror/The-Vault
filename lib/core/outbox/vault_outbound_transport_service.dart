import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/security/local_security_material.dart';
import '../../models/chat_message.dart';
import '../../models/chat_thread.dart';
import '../../state/chat_store.dart';
import '../../state/identity_store.dart';
import '../../state/vault_peer_store.dart';
import '../../state/vault_store.dart';
import '../relay/relay_client.dart';
import '../vault/vault_bridge.dart';
import '../vault/vault_models.dart';
import '../vault/vault_relay_client.dart';
import '../vault/windows_vault_helper_bridge.dart';

enum VaultMessageTransportResult { sent, unavailable, failed }

class VaultOutboundTransportService {
  VaultOutboundTransportService._();

  static final VaultOutboundTransportService instance =
      VaultOutboundTransportService._();

  final VaultBridge _vaultBridge = defaultVaultBridge;
  final Set<String> _vaultSessionReadyPeers = <String>{};

  bool supportsMessage(ChatMessage message) {
    return message.type == ChatMessage.typeText ||
        message.type == ChatMessage.typeSticker ||
        message.type == ChatMessage.typeVoice ||
        message.type == ChatMessage.typeAttachment;
  }

  Future<VaultMessageTransportResult> sendChatMessage(
    ChatMessage message,
  ) async {
    if (!supportsMessage(message)) {
      return VaultMessageTransportResult.failed;
    }
    final chat = ChatStore.getChat(message.chatId);
    if (chat == null) {
      return VaultMessageTransportResult.failed;
    }
    if (message.type == ChatMessage.typeAttachment) {
      return _sendAttachmentMessage(message, chat: chat);
    }
    final relayMessage = await buildRelayMessage(message, chat: chat);
    if (relayMessage == null) {
      return VaultMessageTransportResult.failed;
    }
    return sendRelayMessage(relayMessage, chat: chat);
  }

  Future<VaultMessageTransportResult> sendRelayAction(
    RelayMessage message, {
    bool requireAllDestinations = false,
  }) async {
    final chat = ChatStore.getChat(message.chatId);
    if (chat == null) {
      return VaultMessageTransportResult.failed;
    }
    return sendRelayMessage(
      message,
      chat: chat,
      requireAllDestinations: requireAllDestinations,
    );
  }

  Future<RelayMessage?> buildRelayMessage(
    ChatMessage message, {
    required ChatThread chat,
  }) async {
    if (!supportsMessage(message)) {
      return null;
    }

    String? voiceB64;
    if (message.type == ChatMessage.typeVoice) {
      final path = (message.voicePath ?? '').trim();
      if (path.isEmpty) return null;
      try {
        final file = File(path);
        if (!await file.exists()) {
          return null;
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          return null;
        }
        voiceB64 = base64Encode(bytes);
      } catch (_) {
        return null;
      }
    }

    final directPeerId = (chat.contactId ?? '').trim();
    return RelayMessage(
      id: message.id,
      chatId: message.chatId,
      senderId: message.senderId,
      senderName: IdentityStore.displayName,
      directPeerId: directPeerId.isEmpty ? null : directPeerId,
      type: _relayMessageTypeFor(message),
      body: message.body,
      stickerPackId: message.stickerPackId,
      stickerId: message.stickerId,
      stickerVariant: message.stickerVariant,
      voiceB64: voiceB64,
      voiceMime: message.voiceMime,
      voiceDurationMs: message.voiceDurationMs,
      replyToMessageId: message.replyTo?.messageId,
      replyToSenderId: message.replyTo?.senderId,
      replyToType: message.replyTo?.type,
      replyToPreview: message.replyTo?.previewText,
      createdAt: message.createdAt,
    );
  }

  Future<VaultMessageTransportResult> _sendAttachmentMessage(
    ChatMessage message, {
    required ChatThread chat,
  }) async {
    final attachmentId = (message.attachmentId ?? message.id).trim();
    final encryptedPath = (message.attachmentPath ?? '').trim();
    final name = (message.attachmentName ?? 'Attachment').trim();
    final mime = (message.attachmentMime ?? 'application/octet-stream').trim();
    final plaintextSize = message.attachmentSize;
    if (attachmentId.isEmpty || encryptedPath.isEmpty) {
      return VaultMessageTransportResult.failed;
    }

    final file = File(encryptedPath);
    if (!await file.exists()) {
      return VaultMessageTransportResult.failed;
    }

    Uint8List encryptedBytes;
    Uint8List? mediaKey;
    try {
      encryptedBytes = Uint8List.fromList(await file.readAsBytes());
      if (encryptedBytes.isEmpty) {
        return VaultMessageTransportResult.failed;
      }
      mediaKey = await LocalSecurityMaterial.readAttachmentKey(attachmentId);
      if (mediaKey == null || mediaKey.isEmpty) {
        return VaultMessageTransportResult.failed;
      }
      final sendPlan = await _prepareVaultSendPlan(chat);
      if (sendPlan == null) {
        return VaultMessageTransportResult.unavailable;
      }
      final attachmentKeyB64 = base64Encode(mediaKey);
      final transportHash = sha256.convert(encryptedBytes).toString();
      final totalChunks = (encryptedBytes.length / _attachmentChunkSize)
          .ceil()
          .clamp(1, 999999);

      for (var i = 0; i < totalChunks; i++) {
        final start = i * _attachmentChunkSize;
        final end = (start + _attachmentChunkSize).clamp(
          0,
          encryptedBytes.length,
        );
        final chunk = encryptedBytes.sublist(start, end);
        final chunkMessage = RelayMessage(
          id: '${attachmentId}_$i',
          chatId: message.chatId,
          senderId: message.senderId,
          senderName: IdentityStore.displayName,
          directPeerId: (chat.contactId ?? '').trim().isEmpty
              ? null
              : chat.contactId!.trim(),
          type: RelayMessage.typeAttachmentChunk,
          body: 'Attachment',
          attachmentId: attachmentId,
          attachmentName: name,
          attachmentMime: mime,
          attachmentSize: encryptedBytes.length,
          attachmentChunkIndex: i,
          attachmentChunkCount: totalChunks,
          attachmentChunkB64: base64Encode(chunk),
          attachmentInline: message.attachmentInline,
          replyToMessageId: message.replyTo?.messageId,
          replyToSenderId: message.replyTo?.senderId,
          replyToType: message.replyTo?.type,
          replyToPreview: message.replyTo?.previewText,
          createdAt: DateTime.now(),
        );
        final chunkSent = await _sendRelayMessageWithRetry(
          chunkMessage,
          chat: chat,
          plan: sendPlan,
        );
        if (!chunkSent) {
          return VaultMessageTransportResult.failed;
        }
      }

      final manifestMessage = RelayMessage(
        id: message.id,
        chatId: message.chatId,
        senderId: message.senderId,
        senderName: IdentityStore.displayName,
        directPeerId: (chat.contactId ?? '').trim().isEmpty
            ? null
            : chat.contactId!.trim(),
        type: RelayMessage.typeAttachmentManifest,
        body: 'Attachment: $name',
        attachmentId: attachmentId,
        attachmentName: name,
        attachmentMime: mime,
        attachmentSize: plaintextSize ?? encryptedBytes.length,
        attachmentHash: transportHash,
        attachmentKeyB64: attachmentKeyB64,
        attachmentChunkCount: totalChunks,
        attachmentInline: message.attachmentInline,
        replyToMessageId: message.replyTo?.messageId,
        replyToSenderId: message.replyTo?.senderId,
        replyToType: message.replyTo?.type,
        replyToPreview: message.replyTo?.previewText,
        createdAt: DateTime.now(),
      );
      final manifestSent = await _sendRelayMessageWithRetry(
        manifestMessage,
        chat: chat,
        plan: sendPlan,
      );
      return manifestSent
          ? VaultMessageTransportResult.sent
          : VaultMessageTransportResult.failed;
    } catch (_) {
      return VaultMessageTransportResult.failed;
    } finally {
      mediaKey?.fillRange(0, mediaKey.length, 0);
    }
  }

  Future<VaultMessageTransportResult> sendRelayMessage(
    RelayMessage message, {
    required ChatThread chat,
    bool requireAllDestinations = false,
  }) async {
    final plan = await _prepareVaultSendPlan(chat);
    if (plan == null) {
      return VaultMessageTransportResult.unavailable;
    }
    return _sendRelayMessageWithPlan(
      message,
      plan: plan,
      requireAllDestinations: requireAllDestinations,
    );
  }

  Future<VaultMessageTransportResult> _sendRelayMessageWithPlan(
    RelayMessage message, {
    required _PreparedVaultSendPlan plan,
    bool requireAllDestinations = false,
  }) async {
    try {
      final plaintext = RelayClient.encodePaddedClearPayloadBytes(message);
      final outbound = <VaultOutboundEnvelope>[];
      for (final peerAddress in plan.peerAddresses) {
        final ciphertext = await _encryptVaultPayloadForPeer(
          localAddress: plan.localAddress,
          peerAddress: peerAddress,
          plaintext: plaintext,
        );
        if (ciphertext == null) {
          continue;
        }
        outbound.add(
          VaultOutboundEnvelope(
            destination: peerAddress,
            ciphertext: ciphertext,
          ),
        );
      }

      if (outbound.isEmpty) {
        return VaultMessageTransportResult.unavailable;
      }

      final result = await VaultRelayClient.sendMessages(
        source: plan.localAddress,
        messages: outbound,
        clientMessageId: message.id,
      );
      if (result == null) {
        return VaultMessageTransportResult.failed;
      }
      for (final rejected in result.rejected) {
        _vaultSessionReadyPeers.remove(
          '${rejected.userId}:${rejected.deviceId}',
        );
      }
      if (!result.ok || result.accepted.isEmpty) {
        return VaultMessageTransportResult.failed;
      }
      if (requireAllDestinations && result.accepted.length < outbound.length) {
        return VaultMessageTransportResult.failed;
      }
      return VaultMessageTransportResult.sent;
    } on PlatformException catch (error) {
      if (error.code == 'UNIMPLEMENTED') {
        return VaultMessageTransportResult.unavailable;
      }
      return VaultMessageTransportResult.failed;
    } catch (_) {
      return VaultMessageTransportResult.failed;
    }
  }

  Future<bool> _sendRelayMessageWithRetry(
    RelayMessage message, {
    required ChatThread chat,
    required _PreparedVaultSendPlan plan,
  }) async {
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 450),
      Duration(milliseconds: 1100),
    ];
    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      final delay = retryDelays[attempt];
      if (delay > Duration.zero) {
        if (!kIsWeb && Platform.isWindows && defaultVaultBridgeConfigured) {
          try {
            await WindowsVaultHelperBridge.restartHelper();
          } catch (_) {}
        }
        await Future<void>.delayed(delay);
      }
      final result = await _sendRelayMessageWithPlan(
        message,
        plan: plan,
        requireAllDestinations: false,
      );
      if (result == VaultMessageTransportResult.sent) {
        return true;
      }
    }
    return false;
  }

  Future<_PreparedVaultSendPlan?> _prepareVaultSendPlan(ChatThread chat) async {
    await VaultStore.ensureReady();
    final localAddress = VaultStore.localAddress;
    if (localAddress == null) return null;
    final peerAddresses = chat.isDirectThread
        ? await _resolveDirectVaultPeerAddressesWithRetry(
            localAddress: localAddress,
            contactId: chat.contactId,
          )
        : await _resolveVaultGroupPeerAddresses(
            localAddress: localAddress,
            chat: chat,
          );
    final filteredAddresses = peerAddresses
        .where(
          (peerAddress) =>
              peerAddress.userId != localAddress.userId ||
              peerAddress.deviceId != localAddress.deviceId,
        )
        .toList(growable: false);
    if (filteredAddresses.isEmpty) {
      return null;
    }
    return _PreparedVaultSendPlan(
      localAddress: localAddress,
      peerAddresses: filteredAddresses,
    );
  }

  Future<List<VaultAddress>> _resolveDirectVaultPeerAddressesWithRetry({
    required VaultAddress localAddress,
    required String? contactId,
  }) async {
    var addresses = await _resolveVaultPeerAddresses(
      localAddress: localAddress,
      contactId: contactId,
    );
    if (addresses.isNotEmpty) {
      return addresses;
    }
    for (final delay in const <Duration>[
      Duration(milliseconds: 700),
      Duration(milliseconds: 1400),
    ]) {
      await Future<void>.delayed(delay);
      addresses = await _resolveVaultPeerAddresses(
        localAddress: localAddress,
        contactId: contactId,
      );
      if (addresses.isNotEmpty) {
        return addresses;
      }
    }
    return addresses;
  }

  Future<List<VaultAddress>> _resolveVaultPeerAddresses({
    required VaultAddress localAddress,
    required String? contactId,
  }) async {
    final cleanContactId = (contactId ?? '').trim();
    if (cleanContactId.isEmpty) return const <VaultAddress>[];

    final addresses = <VaultAddress>[];
    final seenKeys = <String>{};
    final devicesResponse = await VaultRelayClient.fetchDevices(cleanContactId);
    if (devicesResponse != null) {
      final remoteAddresses = devicesResponse.devices
          .map((device) => device.address)
          .toList(growable: false);
      if (devicesResponse.identityChanged) {
        await _handleVaultIdentityChange(
          localAddress: localAddress,
          userId: cleanContactId,
          remoteAddresses: remoteAddresses,
        );
      }
      for (final remoteAddress in remoteAddresses) {
        _appendVaultPeerAddress(
          addresses: addresses,
          seenKeys: seenKeys,
          address: remoteAddress,
        );
      }
      if (addresses.isNotEmpty) {
        return addresses;
      }
    }

    _appendVaultPeerAddress(
      addresses: addresses,
      seenKeys: seenKeys,
      address: await VaultPeerStore.getForContact(cleanContactId),
    );
    return addresses;
  }

  Future<void> _handleVaultIdentityChange({
    required VaultAddress localAddress,
    required String userId,
    required List<VaultAddress> remoteAddresses,
  }) async {
    final prefix = '${userId.trim()}:';
    _vaultSessionReadyPeers.removeWhere((key) => key.startsWith(prefix));
    for (final remoteAddress in remoteAddresses) {
      try {
        await _vaultBridge.archiveSession(
          localAddress: localAddress,
          remoteAddress: remoteAddress,
        );
      } on PlatformException catch (error) {
        if (error.code == 'UNIMPLEMENTED') {
          return;
        }
      } catch (_) {}
    }
  }

  void _appendVaultPeerAddress({
    required List<VaultAddress> addresses,
    required Set<String> seenKeys,
    required VaultAddress? address,
  }) {
    if (address == null) return;
    final peerKey = _vaultPeerKey(address);
    if (peerKey == null || !seenKeys.add(peerKey)) {
      return;
    }
    addresses.add(address);
  }

  Future<List<VaultAddress>> _resolveVaultGroupPeerAddresses({
    required VaultAddress localAddress,
    required ChatThread chat,
  }) async {
    final ready = await _ensureVaultGroupReady(chat);
    if (!ready) {
      return const <VaultAddress>[];
    }
    final response = await VaultRelayClient.fetchGroupDevices(chat.id);
    if (response == null) {
      return const <VaultAddress>[];
    }
    return response.devices
        .map((device) => device.address)
        .where(
          (address) =>
              address.userId != localAddress.userId ||
              address.deviceId != localAddress.deviceId,
        )
        .toList(growable: false);
  }

  Future<bool> _ensureVaultGroupReady(ChatThread chat) async {
    if (chat.isDirectThread) {
      return true;
    }
    final userId = IdentityStore.userId.trim();
    if (userId.isEmpty) {
      return false;
    }
    final response = await VaultRelayClient.ensureGroup(
      groupId: chat.id,
      title: chat.title,
      creatorUserId: userId,
    );
    return response != null;
  }

  Future<bool> _ensureVaultSession({
    required VaultAddress localAddress,
    required VaultAddress peerAddress,
  }) async {
    final peerKey = _vaultPeerKey(peerAddress);
    if (peerKey == null) return false;
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

  Future<VaultCiphertext?> _encryptVaultPayloadForPeer({
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
        rethrow;
      }
      if (!_isVaultSessionRetryableError(error)) {
        rethrow;
      }
      if (error.code == 'vault_bridge_error') {
        try {
          await _vaultBridge.reset();
        } catch (_) {}
      }
      final peerKey = _vaultPeerKey(peerAddress);
      if (peerKey != null) {
        _vaultSessionReadyPeers.remove(peerKey);
      }
      try {
        await _vaultBridge.archiveSession(
          localAddress: localAddress,
          remoteAddress: peerAddress,
        );
      } on PlatformException catch (archiveError) {
        if (archiveError.code == 'UNIMPLEMENTED') {
          rethrow;
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

  String? _vaultPeerKey(VaultAddress address) {
    final userId = address.userId.trim();
    if (userId.isEmpty) return null;
    return '$userId:${address.deviceId}';
  }

  bool _isVaultSessionRetryableError(PlatformException error) {
    return error.code == 'vault_no_session' ||
        error.code == 'vault_invalid_key_id' ||
        error.code == 'vault_reused_base_key' ||
        error.code == 'vault_bridge_error';
  }

  String _relayMessageTypeFor(ChatMessage message) {
    if (message.type == ChatMessage.typeSticker) {
      return RelayMessage.typeSticker;
    }
    if (message.type == ChatMessage.typeVoice) {
      return RelayMessage.typeVoice;
    }
    if (message.type == ChatMessage.typeAttachment) {
      return RelayMessage.typeAttachmentManifest;
    }
    return RelayMessage.typeText;
  }
}

class _PreparedVaultSendPlan {
  const _PreparedVaultSendPlan({
    required this.localAddress,
    required this.peerAddresses,
  });

  final VaultAddress localAddress;
  final List<VaultAddress> peerAddresses;
}

const int _attachmentChunkSize = 48 * 1024;
