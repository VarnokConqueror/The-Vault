import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:record/record.dart';
import 'package:lottie/lottie.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import 'package:emoji_extension/emoji_extension.dart' as emoji;
import 'package:video_player/video_player.dart';

import '../state/message_store.dart';
import '../state/identity_store.dart';
import '../state/contacts_store.dart';
import '../state/push_store.dart';
import '../state/voice_notes_store.dart';
import '../state/sticker_store.dart';
import '../state/media_policy_store.dart';
import '../state/chat_appearance_store.dart';
import '../state/contact_appearance_store.dart';
import '../state/chat_store.dart';
import '../state/chat_unread_store.dart';
import '../state/date_time_format_store.dart';
import '../state/security_store.dart';
import '../state/read_receipts_store.dart';
import '../state/vault_store.dart';
import '../state/vault_peer_store.dart';
import '../state/vault_theme_store.dart';
import '../models/chat_appearance.dart';
import '../models/chat_message.dart';
import '../core/invites/vault_chat_invite.dart';
import '../core/relay/relay_client.dart';
import '../core/vault/direct_thread_routing.dart';
import '../core/vault/vault_bridge.dart';
import '../core/vault/vault_models.dart';
import '../core/vault/vault_relay_client.dart';
import '../core/vault/windows_vault_helper_bridge.dart';
import '../core/tones/tone_storage.dart';
import '../core/voice_notes/voice_note_storage.dart';
import '../core/calls/call_service.dart';
import '../core/ui/desktop_overlay_card.dart';
import '../state/call_policy_store.dart';
import '../core/ui/orientation_lock.dart';
import '../core/ui/vault_emoji_sticker_picker_sheet.dart';
import '../core/stickers/animated_emoji.dart';
import '../core/stickers/sticker_catalog.dart';
import '../core/stickers/sticker_cache.dart';
import '../core/media/media_storage.dart';
import '../core/media/incoming_attachment_ingest.dart';
import '../core/media/media_cipher.dart';
import '../core/media/device_media_picker.dart';
import '../core/security/replay_protection_store.dart';
import '../core/vault/vault_mailbox_sync_service.dart';
import 'giphy_search_screen.dart';
import '../core/calls/call_mailbox.dart';

enum _VaultTransportResult { sent, unavailable, failed }

class _PreparedVaultSendPlan {
  const _PreparedVaultSendPlan({
    required this.localAddress,
    required this.peerAddresses,
  });

  final VaultAddress localAddress;
  final List<VaultAddress> peerAddresses;
}

class ThreadScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final String? contactId;
  final bool embedded;

  const ThreadScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    this.contactId,
    this.embedded = false,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  static const Uuid _uuid = Uuid();
  static const int _attachmentChunkSize = 32 * 1024;
  static final VaultBridge _vaultBridge = defaultVaultBridge;
  static const List<String> _mediaExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'mp4',
    'mov',
    'mkv',
    'webm',
  ];

  bool get _desktopVaultBridgeUnavailable =>
      !kIsWeb &&
      (Platform.isLinux ||
          Platform.isMacOS ||
          (Platform.isWindows && !defaultVaultBridgeConfigured));

  Color get _pink => VaultThemeStore.activePalette.accent;
  Color get _incomingFill => VaultThemeStore.activePalette.surfaceAlt;
  Color get _screenBg => VaultThemeStore.activePalette.background;
  Color get _text => VaultThemeStore.activePalette.text;
  Color get _textSoft => VaultThemeStore.activePalette.textSoft;
  Color get _buttonText => VaultThemeStore.activePalette.buttonText;
  Color get _overlayTint =>
      Color.lerp(
        VaultThemeStore.activePalette.background,
        VaultThemeStore.activePalette.surface,
        0.45,
      ) ??
      VaultThemeStore.activePalette.surface;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _voicePlayer = AudioPlayer();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;
  Timer? _scrollSettleTimer;
  bool _polling = false;
  int _pollDelayMs = 2000;
  DateTime? _lastSendFailureAt;

  StreamSubscription<void>? _voiceCompleteSub;
  StreamSubscription<PlayerState>? _voiceStateSub;
  String? _playingVoiceMessageId;
  bool _voiceIsPlaying = false;

  bool _isRecordingVoice = false;
  String? _recordingVoiceId;
  String? _recordingVoiceMime;
  String? _recordingVoicePath;
  DateTime? _recordingVoiceStartedAt;
  Timer? _recordingVoiceTimer;
  int _recordingVoiceSeconds = 0;
  bool _recordingSizeCheckInProgress = false;
  bool _recordingAutoStopped = false;

  String? _pendingVoiceDraftId;
  String? _pendingVoiceDraftPath;
  String? _pendingVoiceDraftMime;
  int? _pendingVoiceDraftDurationMs;
  ChatMessage? _replyingToMessage;

  int _lastRenderedCount = -1;
  String _lastRenderedLastId = '';
  int _lastMessageCount = 0;
  String _lastStickyLastId = '';
  bool _didInitialScrollToBottom = false;
  bool _scrollToBottomScheduled = false;
  final Map<String, GlobalKey> _messageRowKeys = <String, GlobalKey>{};
  final Set<String> _sentDeliveredReceiptIds = <String>{};
  final Set<String> _sentReadReceiptIds = <String>{};
  final Set<String> _selfReceiptEnvelopeIds = <String>{};
  final Set<String> _vaultSessionReadyPeers = <String>{};
  final Map<String, Future<Uint8List?>> _attachmentPreviewBytes =
      <String, Future<Uint8List?>>{};
  final Map<String, Future<Uint8List?>> _attachmentThumbnailBytes =
      <String, Future<Uint8List?>>{};
  bool _readReceiptSweepScheduled = false;

  @override
  void initState() {
    super.initState();
    if (RelayClient.logSuccess) {
      debugPrint('[Relay] ThreadScreen init chatId=${widget.chatId}');
    }
    _scrollController.addListener(_handleScrollPositionChanged);
    ChatUnreadStore.trackChatOpen(widget.chatId);
    ReadReceiptsStore.sendReadReceiptsNotifier.addListener(
      _handleReadReceiptPrefChanged,
    );
    SecurityStore.screenshotsAllowedNotifier.addListener(
      _applyScreenshotProtection,
    );
    _applyScreenshotProtection();
    _configureTonePlayer();
    _configureVoicePlayer();
    unawaited(VaultStore.ensureReady());
    if (_threadOwnsVaultMailboxPolling) {
      _scheduleNextPoll();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markThreadReadIfNearBottom();
      _scheduleVisibleReadReceiptSweep();
    });
  }

  @override
  void didUpdateWidget(covariant ThreadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId == widget.chatId) return;
    ChatUnreadStore.noteChatClosed(oldWidget.chatId);
    ChatUnreadStore.trackChatOpen(widget.chatId);
    _pollTimer?.cancel();
    _lastMessageCount = 0;
    _lastStickyLastId = '';
    _didInitialScrollToBottom = false;
    _scrollToBottomScheduled = false;
    _readReceiptSweepScheduled = false;
    _messageRowKeys.clear();
    _sentDeliveredReceiptIds.clear();
    _sentReadReceiptIds.clear();
    _selfReceiptEnvelopeIds.clear();
    _attachmentPreviewBytes.clear();
    _attachmentThumbnailBytes.clear();
    if (_threadOwnsVaultMailboxPolling) {
      _scheduleNextPoll();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markThreadReadIfNearBottom();
      _scheduleVisibleReadReceiptSweep();
    });
  }

  Future<void> _configureTonePlayer() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      // Use notification audio routing/volume (not media), so "notification tone"
      // behaves like a notification.
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _configureVoicePlayer() async {
    try {
      await _voicePlayer.setVolume(1.0);
      await _voicePlayer.setReleaseMode(ReleaseMode.stop);
      await _voicePlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
    } catch (_) {}

    _voiceCompleteSub?.cancel();
    _voiceCompleteSub = _voicePlayer.onPlayerComplete.listen((_) {
      _handleVoicePlaybackComplete();
    });

    _voiceStateSub?.cancel();
    _voiceStateSub = _voicePlayer.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (!mounted) return;
      if (_voiceIsPlaying != playing) {
        setState(() => _voiceIsPlaying = playing);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.removeListener(_handleScrollPositionChanged);
    ChatUnreadStore.noteChatClosed(widget.chatId);
    ReadReceiptsStore.sendReadReceiptsNotifier.removeListener(
      _handleReadReceiptPrefChanged,
    );
    _controller.dispose();
    _composerFocusNode.dispose();
    _audioPlayer.dispose();
    _voiceCompleteSub?.cancel();
    _voiceCompleteSub = null;
    _voiceStateSub?.cancel();
    _voiceStateSub = null;
    _recordingVoiceTimer?.cancel();
    _recordingVoiceTimer = null;
    _scrollSettleTimer?.cancel();
    _scrollSettleTimer = null;
    try {
      unawaited(_voiceRecorder.cancel());
    } catch (_) {}
    unawaited(_voiceRecorder.dispose());
    SecurityStore.screenshotsAllowedNotifier.removeListener(
      _applyScreenshotProtection,
    );
    _voicePlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleReadReceiptPrefChanged() {
    if (ReadReceiptsStore.sendReadReceipts) {
      _scheduleVisibleReadReceiptSweep();
    }
  }

  Future<void> _applyScreenshotProtection() async {
    final allowed = SecurityStore.screenshotsAllowedNotifier.value;
    if (allowed) {
      await _allowScreenCapture();
    } else {
      await _preventScreenCapture();
    }
  }

  Future<void> _preventScreenCapture() async {
    try {
      if (!kIsWeb &&
          (Platform.isAndroid ||
              Platform.isIOS ||
              Platform.isMacOS ||
              Platform.isWindows ||
              Platform.isLinux)) {
        await ScreenProtector.protectDataLeakageOn();
      }
    } catch (_) {}
  }

  Future<void> _allowScreenCapture() async {
    try {
      if (!kIsWeb &&
          (Platform.isAndroid ||
              Platform.isIOS ||
              Platform.isMacOS ||
              Platform.isWindows ||
              Platform.isLinux)) {
        await ScreenProtector.protectDataLeakageOff();
      }
    } catch (_) {}
  }

  void _scheduleNextPoll() {
    if (!_threadOwnsVaultMailboxPolling) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer(Duration(milliseconds: _pollDelayMs), _pollRelay);
  }

  String _currentSenderId() {
    final publicId = IdentityStore.publicId.trim();
    return publicId.isEmpty ? 'local' : publicId;
  }

  bool _isSelfSender(String senderId) {
    final s = senderId.trim();
    if (s.isEmpty) return false;
    if (s == 'local') return true;
    final publicId = IdentityStore.publicId.trim();
    if (publicId.isNotEmpty && s == publicId) return true;
    final userId = IdentityStore.userId.trim();
    return userId.isNotEmpty && s == userId;
  }

  bool _isOutgoingMessage(ChatMessage message) =>
      _isSelfSender(message.senderId);

  bool get _prefersDeviceAlbumPicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String? _chatSharedSecret() => ChatStore.sharedSecretFor(widget.chatId);
  bool get _usesLegacyRelayMailbox =>
      !_isDirectMessageThread && (_chatSharedSecret()?.isNotEmpty ?? false);

  bool get _isDirectMessageThread => (widget.contactId ?? '').trim().isNotEmpty;

  bool get _usesVaultGroupTransport => !_isDirectMessageThread;

  bool get _threadOwnsVaultMailboxPolling =>
      _usesLegacyRelayMailbox ||
      !VaultMailboxSyncService.ownsDeviceMailboxPolling;

  String? _contactIdForVaultPeer() {
    final contactId = widget.contactId?.trim();
    if (contactId == null || contactId.isEmpty) return null;
    return contactId;
  }

  String? _outgoingDirectPeerId() {
    final contactId = widget.contactId?.trim();
    if (contactId == null || contactId.isEmpty) return null;
    return contactId;
  }

  String _directCallMailboxId() {
    final contactId = (widget.contactId ?? '').trim();
    if (contactId.isEmpty) return widget.chatId;
    return directCallMailboxId(
      localUserId: IdentityStore.userId,
      peerUserId: contactId,
    );
  }

  RelayMessage _buildRelayMessage({
    required String id,
    required String chatId,
    required String senderId,
    required String senderName,
    required String body,
    required DateTime createdAt,
    String type = RelayMessage.typeText,
    String? stickerPackId,
    String? stickerId,
    String? stickerVariant,
    String? attachmentId,
    String? attachmentName,
    String? attachmentMime,
    int? attachmentSize,
    String? attachmentHash,
    String? attachmentKeyB64,
    int? attachmentChunkIndex,
    int? attachmentChunkCount,
    String? attachmentChunkB64,
    bool? attachmentInline,
    String? voiceB64,
    String? voiceMime,
    int? voiceDurationMs,
    MessageReplyPreview? replyTo,
    String? receiptKind,
    String? receiptMessageId,
    String? reactionEmoji,
    String? reactionTargetMessageId,
    String? reactionAction,
  }) {
    return RelayMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      directPeerId: _outgoingDirectPeerId(),
      type: type,
      body: body,
      stickerPackId: stickerPackId,
      stickerId: stickerId,
      stickerVariant: stickerVariant,
      attachmentId: attachmentId,
      attachmentName: attachmentName,
      attachmentMime: attachmentMime,
      attachmentSize: attachmentSize,
      attachmentHash: attachmentHash,
      attachmentKeyB64: attachmentKeyB64,
      attachmentChunkIndex: attachmentChunkIndex,
      attachmentChunkCount: attachmentChunkCount,
      attachmentChunkB64: attachmentChunkB64,
      attachmentInline: attachmentInline,
      voiceB64: voiceB64,
      voiceMime: voiceMime,
      voiceDurationMs: voiceDurationMs,
      replyToMessageId: replyTo?.messageId,
      replyToSenderId: replyTo?.senderId,
      replyToType: replyTo?.type,
      replyToPreview: replyTo?.previewText,
      receiptKind: receiptKind,
      receiptMessageId: receiptMessageId,
      reactionEmoji: reactionEmoji,
      reactionTargetMessageId: reactionTargetMessageId,
      reactionAction: reactionAction,
      createdAt: createdAt,
    );
  }

  Future<String> _resolveIncomingChatId(
    RelayMessage relayMessage, {
    VaultAddress? source,
  }) async {
    return resolveIncomingVaultChatId(
      rawChatId: relayMessage.chatId,
      directPeerHint: relayMessage.directPeerId ?? '',
      senderId: relayMessage.senderId,
      senderName: relayMessage.senderName,
      sourceUserId: source?.userId,
      currentContactId: widget.contactId,
      currentChatTitle: widget.chatTitle,
      sourceAddress: source,
      fallbackChatId: widget.chatId,
    );
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

  Future<List<VaultAddress>> _resolveVaultPeerAddresses({
    VaultAddress? localAddress,
  }) async {
    final contactId = _contactIdForVaultPeer();
    if (contactId == null) return const <VaultAddress>[];

    final addresses = <VaultAddress>[];
    final seenKeys = <String>{};
    final devicesResponse = await VaultRelayClient.fetchDevices(contactId);
    if (devicesResponse != null) {
      final remoteAddresses = devicesResponse.devices
          .map((device) => device.address)
          .toList(growable: false);
      if (devicesResponse.identityChanged && localAddress != null) {
        await _handleVaultIdentityChange(
          localAddress: localAddress,
          userId: contactId,
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
      address: await VaultPeerStore.getForContact(contactId),
    );
    return addresses;
  }

  Future<List<VaultAddress>> _resolveDirectVaultPeerAddressesWithRetry({
    required VaultAddress localAddress,
  }) async {
    var addresses = await _resolveVaultPeerAddresses(
      localAddress: localAddress,
    );
    if (addresses.isNotEmpty) {
      return addresses;
    }
    for (final delay in const <Duration>[
      Duration(milliseconds: 700),
      Duration(milliseconds: 1400),
    ]) {
      await Future<void>.delayed(delay);
      addresses = await _resolveVaultPeerAddresses(localAddress: localAddress);
      if (addresses.isNotEmpty) {
        return addresses;
      }
    }
    return addresses;
  }

  Future<bool> _ensureVaultGroupReady() async {
    if (!_usesVaultGroupTransport) {
      return true;
    }
    final userId = IdentityStore.userId.trim();
    if (userId.isEmpty) {
      return false;
    }
    final response = await VaultRelayClient.ensureGroup(
      groupId: widget.chatId,
      title: widget.chatTitle,
      creatorUserId: userId,
    );
    return response != null;
  }

  Future<List<VaultAddress>> _resolveVaultGroupPeerAddresses({
    required VaultAddress localAddress,
  }) async {
    final ready = await _ensureVaultGroupReady();
    if (!ready) {
      return const <VaultAddress>[];
    }
    final response = await VaultRelayClient.fetchGroupDevices(widget.chatId);
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

  Future<_PreparedVaultSendPlan?> _prepareVaultSendPlan() async {
    await VaultStore.ensureReady();
    final localAddress = VaultStore.localAddress;
    if (localAddress == null) return null;
    final peerAddresses = _isDirectMessageThread
        ? await _resolveDirectVaultPeerAddressesWithRetry(
            localAddress: localAddress,
          )
        : await _resolveVaultGroupPeerAddresses(localAddress: localAddress);
    final filteredAddresses = peerAddresses
        .where((peerAddress) {
          return peerAddress.userId != localAddress.userId ||
              peerAddress.deviceId != localAddress.deviceId;
        })
        .toList(growable: false);
    if (filteredAddresses.isEmpty) {
      return null;
    }
    return _PreparedVaultSendPlan(
      localAddress: localAddress,
      peerAddresses: filteredAddresses,
    );
  }

  Future<_VaultTransportResult> _sendVaultMessage(
    RelayMessage message, {
    _PreparedVaultSendPlan? plan,
    bool requireAllDestinations = false,
  }) async {
    final resolvedPlan = plan ?? await _prepareVaultSendPlan();
    if (resolvedPlan == null) return _VaultTransportResult.unavailable;

    try {
      final plaintext = RelayClient.encodePaddedClearPayloadBytes(message);
      final outbound = <VaultOutboundEnvelope>[];
      for (final peerAddress in resolvedPlan.peerAddresses) {
        final ciphertext = await _encryptVaultPayloadForPeer(
          localAddress: resolvedPlan.localAddress,
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
        return _VaultTransportResult.unavailable;
      }

      final result = await VaultRelayClient.sendMessages(
        source: resolvedPlan.localAddress,
        messages: outbound,
        clientMessageId: message.id,
      );
      if (result == null) {
        return _VaultTransportResult.failed;
      }
      for (final rejected in result.rejected) {
        _vaultSessionReadyPeers.remove(
          '${rejected.userId}:${rejected.deviceId}',
        );
      }
      if (!result.ok || result.accepted.isEmpty) {
        return _VaultTransportResult.failed;
      }
      if (requireAllDestinations && result.accepted.length < outbound.length) {
        return _VaultTransportResult.failed;
      }
      return _VaultTransportResult.sent;
    } on PlatformException catch (error) {
      if (error.code == 'UNIMPLEMENTED') {
        return _VaultTransportResult.unavailable;
      }
      debugPrint('[Vault] send failed: ${error.message}');
      return _VaultTransportResult.failed;
    } catch (error) {
      debugPrint('[Vault] send failed: $error');
      return _VaultTransportResult.failed;
    }
  }

  Future<bool> _sendThreadMessage(
    RelayMessage message, {
    _PreparedVaultSendPlan? plan,
    bool requireAllDestinations = false,
  }) async {
    final vaultResult = await _sendVaultMessage(
      message,
      plan: plan,
      requireAllDestinations: requireAllDestinations,
    );
    if (vaultResult == _VaultTransportResult.sent) {
      return true;
    }
    return false;
  }

  void _showSendFailureSnackBar() {
    if (!mounted) return;
    final now = DateTime.now();
    final lastFailureAt = _lastSendFailureAt;
    if (lastFailureAt != null &&
        now.difference(lastFailureAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastSendFailureAt = now;
    final text = _isDirectMessageThread
        ? _desktopVaultBridgeUnavailable
              ? 'Direct desktop Vault messaging is not wired yet. Use Android or iPhone for now.'
              : 'Direct message not sent yet. Ask them to open The Vault, then try again in a moment.'
        : 'Message could not be sent. Try again in a moment.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _dispatchThreadMessage(
    RelayMessage message, {
    bool notifyOnFailure = true,
    _PreparedVaultSendPlan? plan,
    bool requireAllDestinations = false,
  }) async {
    final sent = await _sendThreadMessage(
      message,
      plan: plan,
      requireAllDestinations: requireAllDestinations,
    );
    if (sent || !notifyOnFailure) {
      return sent;
    }
    _showSendFailureSnackBar();
    return false;
  }

  Future<RelayDecodeResult> _decodeVaultEnvelope(
    VaultInboundEnvelope envelope,
  ) async {
    final localAddress = VaultStore.localAddress;
    if (localAddress == null) {
      return const RelayDecodeResult.invalid();
    }
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

  String _receiptEnvelopeId({required String kind, required String messageId}) {
    final raw =
        'receipt|$kind|${widget.chatId}|${_currentSenderId()}|$messageId';
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'rcpt_$digest';
  }

  Future<void> _sendReceipt({
    required String kind,
    required String messageId,
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    final targetMessageId = messageId.trim();
    if (targetMessageId.isEmpty) return;
    if (normalizedKind != RelayMessage.receiptKindDelivered &&
        normalizedKind != RelayMessage.receiptKindRead) {
      return;
    }

    final id = _receiptEnvelopeId(
      kind: normalizedKind,
      messageId: targetMessageId,
    );
    if (normalizedKind == RelayMessage.receiptKindDelivered &&
        _sentDeliveredReceiptIds.contains(id)) {
      return;
    }
    if (normalizedKind == RelayMessage.receiptKindRead &&
        _sentReadReceiptIds.contains(id)) {
      return;
    }

    final sent = await _sendThreadMessage(
      _buildRelayMessage(
        id: id,
        chatId: widget.chatId,
        senderId: _currentSenderId(),
        senderName: IdentityStore.displayName,
        type: RelayMessage.typeReceipt,
        body: '',
        receiptKind: normalizedKind,
        receiptMessageId: targetMessageId,
        createdAt: DateTime.now(),
      ),
    );

    if (!sent) return;
    if (normalizedKind == RelayMessage.receiptKindDelivered) {
      _sentDeliveredReceiptIds.add(id);
    } else {
      _sentReadReceiptIds.add(id);
    }

    debugPrint(
      '[Receipt] sent kind=$normalizedKind chat=${widget.chatId} messageId=$targetMessageId',
    );
  }

  Widget _buildTransportNoticeBanner() {
    if (!_isDirectMessageThread || !_desktopVaultBridgeUnavailable) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _incomingFill.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pink.withValues(alpha: 0.36)),
      ),
      child: const Text(
        'Direct Vault messaging on desktop is not fully wired yet. Android and iPhone can exchange direct messages today.',
        style: TextStyle(color: Colors.white, height: 1.35),
      ),
    );
  }

  Future<void> _applyIncomingReceipt(RelayMessage relayMessage) async {
    final kind = (relayMessage.receiptKind ?? '').trim().toLowerCase();
    final messageId = (relayMessage.receiptMessageId ?? '').trim();
    if (messageId.isEmpty) return;
    if (kind != RelayMessage.receiptKindDelivered &&
        kind != RelayMessage.receiptKindRead) {
      return;
    }

    final resolvedChatId = await _resolveIncomingChatId(relayMessage);

    final applied = await MessageStore.applyReceipt(
      chatId: resolvedChatId,
      messageId: messageId,
      kind: kind,
      receiptAt: relayMessage.createdAt,
    );
    debugPrint(
      '[Receipt] received kind=$kind chat=$resolvedChatId '
      'messageId=$messageId from=${relayMessage.senderId} applied=$applied',
    );
  }

  GlobalKey _messageRowKey(String messageId) {
    final id = messageId.trim();
    return _messageRowKeys.putIfAbsent(id, () => GlobalKey(debugLabel: id));
  }

  void _pruneMessageRowKeys(List<ChatMessage> messages) {
    final keep = messages
        .map((m) => m.id.trim())
        .where((m) => m.isNotEmpty)
        .toSet();
    _messageRowKeys.removeWhere((id, _) => !keep.contains(id));
  }

  bool _rowKeyIsVisible(GlobalKey key) {
    final rowContext = key.currentContext;
    if (rowContext == null) return false;
    final obj = rowContext.findRenderObject();
    if (obj is! RenderBox || !obj.attached || !obj.hasSize) {
      return false;
    }

    final topLeft = obj.localToGlobal(Offset.zero);
    final rect = topLeft & obj.size;
    if (rect.isEmpty) return false;

    final media = MediaQuery.of(context);
    final topInset = media.padding.top + kToolbarHeight;
    final bottomInset = media.padding.bottom + 64;
    final viewport = Rect.fromLTWH(
      0,
      topInset,
      media.size.width,
      (media.size.height - topInset - bottomInset).clamp(0, media.size.height),
    );
    final overlap = rect.intersect(viewport);
    if (overlap.isEmpty) return false;
    final visibleArea = overlap.width * overlap.height;
    final totalArea = rect.width * rect.height;
    if (totalArea <= 0) return false;
    return (visibleArea / totalArea) >= 0.18;
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    if (!position.hasPixels) return true;
    final threshold = position.viewportDimension * 0.18;
    final gap = position.maxScrollExtent - position.pixels;
    return gap <= (threshold < 96 ? 96 : threshold);
  }

  void _handleScrollPositionChanged() {
    _scheduleVisibleReadReceiptSweep();
    _markThreadReadIfNearBottom();
  }

  void _markThreadReadIfNearBottom({bool force = false}) {
    if (!mounted) return;
    if (!force && !_isNearBottom()) return;
    final messages = MessageStore.getMessagesForChat(widget.chatId);
    ChatMessage? latestIncoming;
    for (final message in messages) {
      if (_isOutgoingMessage(message)) continue;
      latestIncoming = message;
    }
    if (latestIncoming == null) {
      unawaited(ChatUnreadStore.markChatRead(widget.chatId));
      return;
    }
    unawaited(
      ChatUnreadStore.markChatReadThrough(
        widget.chatId,
        messageId: latestIncoming.id,
      ),
    );
  }

  void _scheduleVisibleReadReceiptSweep() {
    if (!mounted) return;
    if (!ReadReceiptsStore.sendReadReceipts) return;
    if (_readReceiptSweepScheduled) return;
    _readReceiptSweepScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readReceiptSweepScheduled = false;
      if (!mounted || !ReadReceiptsStore.sendReadReceipts) return;
      final messages = MessageStore.getMessagesForChat(widget.chatId);
      ChatMessage? latestIncoming;
      for (final message in messages) {
        if (_isOutgoingMessage(message)) continue;
        latestIncoming = message;
      }
      if (latestIncoming == null) return;
      final latestSeenIncomingId = latestIncoming.id.trim();
      if (latestSeenIncomingId.isEmpty) return;
      final latestKey = _messageRowKeys[latestSeenIncomingId];
      final latestVisible = latestKey != null && _rowKeyIsVisible(latestKey);
      if (!_isNearBottom() && !latestVisible) {
        return;
      }
      unawaited(
        _sendReceipt(
          kind: RelayMessage.receiptKindRead,
          messageId: latestSeenIncomingId,
        ),
      );
      if (latestSeenIncomingId.isNotEmpty) {
        unawaited(
          ChatUnreadStore.markChatReadThrough(
            widget.chatId,
            messageId: latestSeenIncomingId,
          ),
        );
      }
    });
  }

  Widget _buildOutgoingReceiptIndicator(
    ChatMessage message, {
    required TextStyle style,
  }) {
    final isRead = message.readAt != null;
    final isDelivered = message.deliveredAt != null;
    final icon = isRead
        ? Icons.done_all_rounded
        : isDelivered
        ? Icons.done_all_rounded
        : Icons.done_rounded;
    final color = isRead
        ? const Color(0xFF4AA3FF)
        : style.color ?? Colors.white54;
    return Icon(icon, size: 13, color: color);
  }

  Widget _buildTimestampWithReceipt(
    BuildContext context, {
    required ChatMessage message,
    required bool isOutgoing,
    required Color color,
    required double fontSize,
  }) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: color, fontSize: fontSize);
    if (!isOutgoing) {
      return Text(_formatTime(message.createdAt), style: style);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_formatTime(message.createdAt), style: style),
        const SizedBox(width: 4),
        _buildOutgoingReceiptIndicator(
          message,
          style: style ?? const TextStyle(),
        ),
      ],
    );
  }

  String _senderLabelForId(String senderId) {
    final cleanSenderId = senderId.trim();
    if (cleanSenderId.isEmpty) return 'Unknown';
    final myId = _currentSenderId().trim();
    if (cleanSenderId == myId ||
        cleanSenderId == IdentityStore.publicId.trim()) {
      return 'You';
    }
    final contactName = ContactsStore.getById(
      cleanSenderId,
    )?.displayName.trim();
    if (contactName != null && contactName.isNotEmpty) {
      return contactName;
    }
    return _isDirectMessageThread ? widget.chatTitle : cleanSenderId;
  }

  String _messagePreviewText(ChatMessage message) {
    if (message.isSticker) return 'Sticker';
    if (message.isVoiceNote) return 'Voice message';
    if (message.isAttachment) {
      final attachmentName = (message.attachmentName ?? '').trim();
      return attachmentName.isEmpty ? 'Attachment' : attachmentName;
    }
    final body = message.body.replaceAll('\n', ' ').trim();
    return body.isEmpty ? 'Message' : _snip(body, max: 48);
  }

  MessageReplyPreview _replyPreviewForMessage(ChatMessage message) {
    return MessageReplyPreview(
      messageId: message.id,
      senderId: message.senderId,
      type: message.type,
      previewText: _messagePreviewText(message),
    );
  }

  void _startReplyDraft(ChatMessage message) {
    if (!mounted) {
      _replyingToMessage = message;
      return;
    }
    setState(() => _replyingToMessage = message);
    FocusScope.of(context).requestFocus(_composerFocusNode);
  }

  void _clearReplyDraft() {
    if (_replyingToMessage == null) return;
    if (!mounted) {
      _replyingToMessage = null;
      return;
    }
    setState(() => _replyingToMessage = null);
  }

  Future<void> _toggleReaction(ChatMessage message, String emojiValue) async {
    final emojiText = emojiValue.trim();
    if (emojiText.isEmpty) return;
    final senderId = _currentSenderId().trim();
    if (senderId.isEmpty) return;

    final alreadyReacted = message.reactions.any(
      (reaction) =>
          reaction.senderId.trim() == senderId && reaction.emoji == emojiText,
    );
    final action = alreadyReacted
        ? RelayMessage.reactionActionRemove
        : RelayMessage.reactionActionAdd;
    final reactedAt = DateTime.now();
    final applied = await MessageStore.applyReaction(
      chatId: widget.chatId,
      messageId: message.id,
      senderId: senderId,
      emoji: emojiText,
      action: action,
      reactedAt: reactedAt,
    );
    if (!applied) return;
    if (mounted) {
      setState(() {});
    }

    unawaited(
      _dispatchThreadMessage(
        _buildRelayMessage(
          id: 'rxn_${_uuid.v4()}',
          chatId: widget.chatId,
          senderId: senderId,
          senderName: IdentityStore.displayName,
          body: '',
          createdAt: reactedAt,
          type: RelayMessage.typeReaction,
          reactionEmoji: emojiText,
          reactionTargetMessageId: message.id,
          reactionAction: action,
        ),
        notifyOnFailure: false,
      ),
    );
  }

  Future<void> _showReactionEmojiPicker(ChatMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A0024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => VaultEmojiStickerPickerSheet(
        emojiOnly: true,
        headerTitle: 'React',
        headerSubtitle: 'Choose an emoji reaction.',
        onSelectEmoji: (emojiValue) => _toggleReaction(message, emojiValue),
        onSelectSticker: (_) async {},
        onLongPressSticker: (_) async {},
      ),
    );
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final commonReactions = <String>['❤️', '👍', '😂', '😮', '😢', '🔥'];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A0024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _senderLabelForId(message.senderId),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _messagePreviewText(message),
                  style: const TextStyle(color: Colors.white60, height: 1.35),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in commonReactions)
                      ActionChip(
                        label: Text(
                          value,
                          style: const TextStyle(fontSize: 18),
                        ),
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _toggleReaction(message, value);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.reply_rounded,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Reply',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startReplyDraft(message);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.add_reaction_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'More reactions',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Future<void>.delayed(
                      const Duration(milliseconds: 120),
                    );
                    if (!mounted) return;
                    await _showReactionEmojiPicker(message);
                  },
                ),
                if (!message.isAttachment &&
                    !message.isSticker &&
                    !message.isVoiceNote)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.copy_all_rounded,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'Copy text',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: message.body),
                      );
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplyQuote(
    MessageReplyPreview replyTo, {
    required bool isOutgoing,
  }) {
    final accent = isOutgoing
        ? Colors.white.withValues(alpha: 0.72)
        : _pink.withValues(alpha: 0.88);
    final fill = isOutgoing
        ? Colors.black.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.12);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _senderLabelForId(replyTo.senderId),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            replyTo.previewText.trim().isEmpty
                ? 'Message'
                : replyTo.previewText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionTray(ChatMessage message, {required bool isOutgoing}) {
    if (message.reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final grouped = <String, _ReactionGroup>{};
    final myId = _currentSenderId().trim();
    for (final reaction in message.reactions) {
      final key = reaction.emoji;
      final current = grouped[key];
      if (current == null) {
        grouped[key] = _ReactionGroup(
          emoji: reaction.emoji,
          count: 1,
          mine: reaction.senderId.trim() == myId,
        );
      } else {
        grouped[key] = _ReactionGroup(
          emoji: current.emoji,
          count: current.count + 1,
          mine: current.mine || reaction.senderId.trim() == myId,
        );
      }
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final reaction in grouped.values)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _toggleReaction(message, reaction.emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: reaction.mine
                    ? _pink.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: reaction.mine
                      ? _pink.withValues(alpha: 0.62)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reaction.emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text(
                    '${reaction.count}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageRow(
    BuildContext context,
    ChatMessage message,
    double contentWidth,
  ) {
    final isMe = _isOutgoingMessage(message);
    final timestamp = _buildTimestampWithReceipt(
      context,
      message: message,
      isOutgoing: isMe,
      color: message.isSticker
          ? _textSoft.withValues(alpha: 0.9)
          : (message.isAttachment || message.isVoiceNote)
          ? _textSoft.withValues(alpha: 0.94)
          : isMe
          ? _buttonText.withValues(alpha: 0.82)
          : _textSoft.withValues(alpha: 0.92),
      fontSize: message.isSticker
          ? 10.6
          : (message.isAttachment || message.isVoiceNote)
          ? 10.4
          : 9.6,
    );
    final reactions = _buildReactionTray(message, isOutgoing: isMe);
    final replyTo = message.replyTo;

    if (message.isSticker) {
      final minWidth = contentWidth * 0.40;
      final maxWidth = contentWidth * 0.58;
      final stickerWidth = (contentWidth * 0.52).clamp(minWidth, maxWidth);
      final stickerWidget = TweenAnimationBuilder<double>(
        key: ValueKey('bigSticker:${message.id}'),
        tween: Tween<double>(begin: 0.95, end: 1.0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: RepaintBoundary(
          child: _buildStickerContent(message, sizeOverride: stickerWidth),
        ),
      );
      return KeyedSubtree(
        key: _messageRowKey(message.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => _showMessageActions(message),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (replyTo != null) ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: contentWidth * 0.54,
                      ),
                      child: _buildReplyQuote(replyTo, isOutgoing: isMe),
                    ),
                    const SizedBox(height: 4),
                  ],
                  stickerWidget,
                  if (message.reactions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    reactions,
                  ],
                  const SizedBox(height: 2),
                  timestamp,
                ],
              ),
            ),
          ),
        ),
      );
    }

    final isTextMessage =
        !message.isSticker && !message.isAttachment && !message.isVoiceNote;
    final bubbleColor = isMe ? _pink : _incomingFill;
    final bubbleBorder = isMe ? null : Border.all(color: _pink, width: 1.2);
    final bubbleTextColor = isMe ? _buttonText : _text;
    final bubbleRadius = isTextMessage
        ? BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 8),
            bottomRight: Radius.circular(isMe ? 8 : 18),
          )
        : BorderRadius.circular(16);
    final bubblePadding = isTextMessage
        ? const EdgeInsets.symmetric(horizontal: 9, vertical: 5)
        : const EdgeInsets.symmetric(horizontal: 9, vertical: 5);

    final emojiCount = isTextMessage ? _emojiOnlyClusterCount(message.body) : 0;
    final emojiFontSize = emojiCount == 0
        ? null
        : _emojiOnlyFontSizeForCount(
            emojiCount,
            MediaQuery.textScalerOf(context),
          );
    final displayBody = emojiCount == 0 ? message.body : message.body.trim();
    final animatedEmojiAsset = isTextMessage && emojiCount == 1
        ? animatedEmojiAssetFor(displayBody)
        : null;
    final content = message.isAttachment
        ? _buildAttachmentContent(message)
        : message.isVoiceNote
        ? _buildVoiceNoteContent(message, isMe: isMe)
        : animatedEmojiAsset != null
        ? SizedBox.square(
            dimension: emojiFontSize ?? 56,
            child: AnimatedEmoji(assetPath: animatedEmojiAsset),
          )
        : Text(
            displayBody,
            style: TextStyle(
              fontSize: emojiFontSize ?? 13.2,
              height: 1.14,
              letterSpacing: 0.1,
              color: bubbleTextColor,
            ),
          );

    return KeyedSubtree(
      key: _messageRowKey(message.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth * 0.72),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => _showMessageActions(message),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: bubblePadding,
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: bubbleRadius,
                      border: bubbleBorder,
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (replyTo != null) ...[
                          _buildReplyQuote(replyTo, isOutgoing: isMe),
                          const SizedBox(height: 5),
                        ],
                        content,
                      ],
                    ),
                  ),
                  if (message.reactions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    reactions,
                  ],
                  const SizedBox(height: 2),
                  timestamp,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pollRelay() async {
    if (!_threadOwnsVaultMailboxPolling) {
      return;
    }
    if (!VaultMailboxSyncService.ownsDeviceMailboxPolling) {
      final vaultResult = await _pollVaultRelay();
      if (vaultResult == _VaultTransportResult.unavailable &&
          _usesLegacyRelayMailbox) {
        await _pollLegacyRelay();
      }
      return;
    }
    if (_usesLegacyRelayMailbox) {
      await _pollLegacyRelay();
    }
  }

  Future<_VaultTransportResult> _pollVaultRelay() async {
    if (_polling) return _VaultTransportResult.failed;
    _polling = true;
    var ok = false;
    try {
      await VaultStore.ensureReady();
      final mailboxId = VaultStore.deviceMailboxId.trim();
      if (mailboxId.isEmpty) {
        return _VaultTransportResult.unavailable;
      }
      final mailbox = await VaultRelayClient.fetchMailbox(mailboxId: mailboxId);
      if (mailbox == null) {
        if (RelayClient.logSuccess) {
          debugPrint('[Vault] poll mailbox=$mailboxId -> fetch failed');
        }
        return _VaultTransportResult.failed;
      }
      ok = true;

      if (RelayClient.logSuccess) {
        debugPrint(
          '[Vault] poll mailbox=$mailboxId -> envelopes=${mailbox.envelopes.length}',
        );
      }
      if (mailbox.envelopes.isEmpty) {
        return _VaultTransportResult.sent;
      }

      final existing = MessageStore.messages;
      final knownIds = existing.map((m) => m.id).toSet();
      final known = existing.map(_messageSignature).toSet();
      final byId = <String, ChatMessage>{for (final m in existing) m.id: m};

      final ackIds = <String>[];

      var decodedOk = 0;
      var decodedFailed = 0;
      var dupId = 0;
      var dupSig = 0;
      var skipSelfAck = 0;
      var stored = 0;
      var receivedFromOther = false;

      for (final envelope in mailbox.envelopes) {
        if (_selfReceiptEnvelopeIds.contains(envelope.envelopeId)) {
          skipSelfAck += 1;
          continue;
        }
        if (knownIds.contains(envelope.envelopeId)) {
          dupId += 1;
          final local = byId[envelope.envelopeId];
          if (local != null && _isSelfSender(local.senderId)) {
            skipSelfAck += 1;
            continue;
          }
          ackIds.add(envelope.envelopeId);
          continue;
        }

        RelayDecodeResult decodeResult;
        try {
          decodeResult = await _decodeVaultEnvelope(envelope);
        } on PlatformException catch (error) {
          if (error.code == 'UNIMPLEMENTED') {
            return _VaultTransportResult.unavailable;
          }
          debugPrint('[Vault] poll decrypt failed: ${error.message}');
          return _VaultTransportResult.failed;
        } catch (error) {
          debugPrint('[Vault] poll decrypt failed: $error');
          return _VaultTransportResult.failed;
        }

        final relayMessage = decodeResult.message;
        if (relayMessage == null) {
          decodedFailed += 1;
          ackIds.add(envelope.envelopeId);
          continue;
        }
        decodedOk += 1;
        final isSelf = _isSelfSender(relayMessage.senderId);
        final resolvedChatId = await _resolveIncomingChatId(
          relayMessage,
          source: envelope.source,
        );
        final signature = _relaySignature(
          relayMessage,
          chatIdOverride: resolvedChatId,
        );
        if (known.contains(signature)) {
          dupSig += 1;
          if (isSelf) {
            skipSelfAck += 1;
            continue;
          }
          ackIds.add(envelope.envelopeId);
          continue;
        }
        final incomingMessageId = relayMessage.id.trim();
        final replayScope = 'vault:$resolvedChatId';
        final alreadySeen = await ReplayProtectionStore.hasSeen(
          scope: replayScope,
          envelopeId: envelope.envelopeId,
          senderId: relayMessage.senderId,
          messageId: incomingMessageId.isEmpty ? null : incomingMessageId,
        );
        if (alreadySeen) {
          ackIds.add(envelope.envelopeId);
          continue;
        }
        ChatMessage? added;
        IncomingAttachmentIngestResult? attachmentIngest;
        final relayType = relayMessage.type.trim().isEmpty
            ? RelayMessage.typeText
            : relayMessage.type.trim();
        if (relayType == RelayMessage.typeReceipt) {
          if (isSelf) {
            _selfReceiptEnvelopeIds.add(envelope.envelopeId);
            if (_selfReceiptEnvelopeIds.length > 1000) {
              _selfReceiptEnvelopeIds.remove(_selfReceiptEnvelopeIds.first);
            }
          } else {
            await _applyIncomingReceipt(relayMessage);
          }
          await ReplayProtectionStore.remember(
            scope: replayScope,
            envelopeId: envelope.envelopeId,
            senderId: relayMessage.senderId,
            messageId: incomingMessageId.isEmpty ? null : incomingMessageId,
          );
        } else if (relayType == RelayMessage.typeVoice &&
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
            );
          } else {
            added = await MessageStore.addIncomingMessage(
              chatId: resolvedChatId,
              senderId: relayMessage.senderId,
              body: relayMessage.body,
              createdAt: relayMessage.createdAt,
              id: envelope.envelopeId,
            );
          }
        } else if (relayType == RelayMessage.typeSticker) {
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
          );
        } else if (relayType == RelayMessage.typeAttachmentChunk) {
          attachmentIngest = await _handleIncomingAttachmentChunk(
            relayMessage,
            resolvedChatId: resolvedChatId,
          );
          added = attachmentIngest.message;
        } else if (relayType == RelayMessage.typeAttachmentManifest) {
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
          );
        }
        if (attachmentIngest != null && !attachmentIngest.shouldAck) {
          continue;
        }
        if (added != null) {
          await ReplayProtectionStore.remember(
            scope: replayScope,
            envelopeId: envelope.envelopeId,
            senderId: relayMessage.senderId,
            messageId: incomingMessageId.isEmpty ? null : incomingMessageId,
          );
          stored += 1;
          if (!isSelf) {
            receivedFromOther = true;
            final resolvedIncomingMessageId = incomingMessageId.isEmpty
                ? envelope.envelopeId
                : incomingMessageId;
            await ChatUnreadStore.recordIncomingMessage(
              chatId: resolvedChatId,
              senderId: relayMessage.senderId,
              messageId: resolvedIncomingMessageId,
              envelopeId: envelope.envelopeId,
            );
            unawaited(
              _sendReceipt(
                kind: RelayMessage.receiptKindDelivered,
                messageId: resolvedIncomingMessageId,
              ),
            );
          }
        }
        known.add(signature);
        knownIds.add(envelope.envelopeId);
        if (added != null) {
          byId[envelope.envelopeId] = added;
        }
        if (isSelf) {
          skipSelfAck += 1;
          continue;
        }
        ackIds.add(envelope.envelopeId);
      }

      if (RelayClient.logSuccess) {
        debugPrint(
          '[Vault] poll mailbox=$mailboxId decoded=$decodedOk decodeFailed=$decodedFailed stored=$stored ack=${ackIds.length} dupId=$dupId dupSig=$dupSig skipSelfAck=$skipSelfAck',
        );
      }

      if (receivedFromOther) {
        await _playNotificationTone();
      }

      if (ackIds.isNotEmpty) {
        final ackOk = await VaultRelayClient.ackMailbox(
          mailboxId: mailboxId,
          envelopeIds: ackIds,
        );
        if (!ackOk && RelayClient.logSuccess) {
          debugPrint(
            '[Vault] poll mailbox=$mailboxId ack failed for ${ackIds.length} envelopes',
          );
        } else if (RelayClient.logSuccess) {
          debugPrint('[Vault] poll mailbox=$mailboxId acked=${ackIds.length}');
        }
      } else if (RelayClient.logSuccess) {
        debugPrint('[Vault] poll mailbox=$mailboxId acked=0');
      }
    } on PlatformException catch (error) {
      if (error.code == 'UNIMPLEMENTED') {
        return _VaultTransportResult.unavailable;
      }
      debugPrint('[Vault] poll failed: ${error.message}');
      return _VaultTransportResult.failed;
    } catch (error) {
      debugPrint('[Vault] poll failed: $error');
      return _VaultTransportResult.failed;
    } finally {
      _polling = false;
      if (ok) {
        _scheduleNextPoll();
      } else {
        _scheduleNextPoll();
      }
    }
    return _VaultTransportResult.sent;
  }

  Future<void> _pollLegacyRelay() async {
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
      var deferredDecrypt = 0;
      final sharedSecret = _chatSharedSecret();

      for (final envelope in mailbox.envelopes) {
        if (_selfReceiptEnvelopeIds.contains(envelope.envelopeId)) {
          skipSelfAck += 1;
          continue;
        }
        if (knownIds.contains(envelope.envelopeId)) {
          dupId += 1;
          final local = byId[envelope.envelopeId];
          if (local != null && _isSelfSender(local.senderId)) {
            // Shared mailbox: don't ack our own outbound envelope, or other
            // participants may miss it before they poll.
            skipSelfAck += 1;
            continue;
          }
          ackIds.add(envelope.envelopeId);
          continue;
        }
        final decodeResult = RelayClient.decodePayload(
          envelope,
          sharedSecret: sharedSecret,
        );
        final relayMessage = decodeResult.message;
        if (relayMessage == null) {
          if (decodeResult.retryable) {
            deferredDecrypt += 1;
            continue;
          }
          decodedFailed += 1;
          ackIds.add(envelope.envelopeId);
          continue;
        }
        decodedOk += 1;
        final resolvedChatId = await _resolveIncomingChatId(relayMessage);
        if (resolvedChatId != widget.chatId) {
          mismatchChat += 1;
          mismatchExample ??= resolvedChatId;
          ackIds.add(envelope.envelopeId);
          continue;
        }
        final isSelf = _isSelfSender(relayMessage.senderId);
        final signature = _relaySignature(
          relayMessage,
          chatIdOverride: resolvedChatId,
        );
        if (known.contains(signature)) {
          dupSig += 1;
          if (isSelf) {
            skipSelfAck += 1;
            continue;
          }
          ackIds.add(envelope.envelopeId);
          continue;
        }
        final incomingMessageId = relayMessage.id.trim();
        final replayScope = 'relay:$resolvedChatId';
        final alreadySeen = await ReplayProtectionStore.hasSeen(
          scope: replayScope,
          envelopeId: envelope.envelopeId,
          senderId: relayMessage.senderId,
          messageId: incomingMessageId.isEmpty ? null : incomingMessageId,
        );
        if (alreadySeen) {
          ackIds.add(envelope.envelopeId);
          continue;
        }
        ChatMessage? added;
        IncomingAttachmentIngestResult? attachmentIngest;
        final relayType = relayMessage.type.trim().isEmpty
            ? RelayMessage.typeText
            : relayMessage.type.trim();
        if (relayType == RelayMessage.typeReceipt) {
          if (isSelf) {
            _selfReceiptEnvelopeIds.add(envelope.envelopeId);
            if (_selfReceiptEnvelopeIds.length > 1000) {
              _selfReceiptEnvelopeIds.remove(_selfReceiptEnvelopeIds.first);
            }
          } else {
            await _applyIncomingReceipt(relayMessage);
          }
          await ReplayProtectionStore.remember(
            scope: replayScope,
            envelopeId: envelope.envelopeId,
            senderId: relayMessage.senderId,
            messageId: incomingMessageId.isEmpty ? null : incomingMessageId,
          );
        } else if (relayType == RelayMessage.typeVoice &&
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
            );
          } else {
            // Fall back to a text-only placeholder (still acks the envelope).
            added = await MessageStore.addIncomingMessage(
              chatId: resolvedChatId,
              senderId: relayMessage.senderId,
              body: relayMessage.body,
              createdAt: relayMessage.createdAt,
              id: envelope.envelopeId,
            );
          }
        } else if (relayType == RelayMessage.typeSticker) {
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
          );
        } else if (relayType == RelayMessage.typeAttachmentChunk) {
          attachmentIngest = await _handleIncomingAttachmentChunk(
            relayMessage,
            resolvedChatId: resolvedChatId,
          );
          added = attachmentIngest.message;
        } else if (relayType == RelayMessage.typeAttachmentManifest) {
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
          );
        }
        if (attachmentIngest != null && !attachmentIngest.shouldAck) {
          continue;
        }
        if (added != null) {
          await ReplayProtectionStore.remember(
            scope: replayScope,
            envelopeId: envelope.envelopeId,
            senderId: relayMessage.senderId,
            messageId: incomingMessageId.isEmpty ? null : incomingMessageId,
          );
          stored += 1;
          if (!isSelf) {
            receivedFromOther = true;
            final resolvedIncomingMessageId = incomingMessageId.isEmpty
                ? envelope.envelopeId
                : incomingMessageId;
            await ChatUnreadStore.recordIncomingMessage(
              chatId: resolvedChatId,
              senderId: relayMessage.senderId,
              messageId: resolvedIncomingMessageId,
              envelopeId: envelope.envelopeId,
            );
            unawaited(
              _sendReceipt(
                kind: RelayMessage.receiptKindDelivered,
                messageId: resolvedIncomingMessageId,
              ),
            );
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
          '[Relay] poll mailbox=${widget.chatId} decoded=$decodedOk decodeFailed=$decodedFailed deferredDecrypt=$deferredDecrypt stored=$stored ack=${ackIds.length} dupId=$dupId dupSig=$dupSig skipSelfAck=$skipSelfAck mismatchChat=$mismatchChat$mismatchNote',
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

  String _relaySignature(RelayMessage message, {String? chatIdOverride}) {
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
        '${message.attachmentId ?? ''}|${message.attachmentChunkIndex ?? -1}|${message.attachmentChunkCount ?? -1}|${message.attachmentHash ?? ''}|${message.attachmentKeyB64 ?? ''}';
    final receipt =
        '${message.receiptKind ?? ''}|${message.receiptMessageId ?? ''}';
    return '$chatId|${message.senderId}|$stamp|$type|$dur|$voiceLen|$sticker|$attachment|$receipt|${message.body}';
  }

  String? _resolveToneUri() {
    final chatTone = ChatAppearanceStore.getForChat(
      widget.chatId,
    )?.toneUri?.trim();
    if (chatTone != null && chatTone.isNotEmpty) {
      return chatTone;
    }

    final contactId = widget.contactId?.trim();
    if (contactId == null || contactId.isEmpty) return null;
    final contactTone = ContactAppearanceStore.getForContact(
      contactId,
    )?.toneUri?.trim();
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
      final trimmed = toneUri.trim();
      final parsed = Uri.tryParse(trimmed);
      if (parsed != null &&
          parsed.scheme.isNotEmpty &&
          parsed.scheme != 'file') {
        await _audioPlayer.play(UrlSource(trimmed));
        return;
      }

      var path = trimmed;
      if (parsed != null && parsed.scheme == 'file') {
        try {
          path = parsed.toFilePath();
        } catch (_) {}
      }
      await _audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('[Tone] play failed: $e uri=$toneUri');
    }
  }

  String _formatDurationSeconds(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString()}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDurationMs(int? ms) {
    if (ms == null || ms <= 0) return '';
    final seconds = (ms / 1000).round();
    return _formatDurationSeconds(seconds);
  }

  Future<_VoiceRecordFormat> _pickVoiceRecordFormat() async {
    // Prefer Opus (small files, good for voice notes).
    try {
      final supported = await _voiceRecorder.isEncoderSupported(
        AudioEncoder.opus,
      );
      if (supported) {
        return const _VoiceRecordFormat(
          encoder: AudioEncoder.opus,
          bitRate: 16000,
          sampleRate: 16000,
          mime: 'audio/opus',
        );
      }
    } catch (_) {}

    // Fallback to AMR-NB (very small, speech-optimized).
    try {
      final supported = await _voiceRecorder.isEncoderSupported(
        AudioEncoder.amrNb,
      );
      if (supported) {
        return const _VoiceRecordFormat(
          encoder: AudioEncoder.amrNb,
          bitRate: 12200,
          sampleRate: 8000,
          mime: 'audio/3gpp',
        );
      }
    } catch (_) {}

    // Last resort: AAC-LC.
    return const _VoiceRecordFormat(
      encoder: AudioEncoder.aacLc,
      bitRate: 32000,
      sampleRate: 16000,
      mime: 'audio/mp4',
    );
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice) return;
    if (_pendingVoiceDraftPath != null) return;

    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    final format = await _pickVoiceRecordFormat();
    final id = _uuid.v4();
    final path = await VoiceNoteStorage.pathForId(id: id, mime: format.mime);

    setState(() {
      _isRecordingVoice = true;
      _recordingVoiceId = id;
      _recordingVoiceMime = format.mime;
      _recordingVoicePath = path;
      _recordingVoiceStartedAt = DateTime.now();
      _recordingVoiceSeconds = 0;
      _recordingAutoStopped = false;
    });

    try {
      await _voiceRecorder.start(
        RecordConfig(
          encoder: format.encoder,
          bitRate: format.bitRate,
          sampleRate: format.sampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _recordingVoiceId = null;
        _recordingVoiceMime = null;
        _recordingVoicePath = null;
        _recordingVoiceStartedAt = null;
        _recordingVoiceSeconds = 0;
        _recordingAutoStopped = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Voice recording failed: $e')));
      return;
    }

    _recordingVoiceTimer?.cancel();
    _recordingVoiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isRecordingVoice) return;
      setState(() => _recordingVoiceSeconds += 1);
      unawaited(_checkRecordingFileSize());
    });
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;

    _recordingVoiceTimer?.cancel();
    _recordingVoiceTimer = null;

    final draftPath = (_recordingVoicePath ?? '').trim();

    setState(() {
      _isRecordingVoice = false;
      _recordingVoiceId = null;
      _recordingVoiceMime = null;
      _recordingVoicePath = null;
      _recordingVoiceStartedAt = null;
      _recordingVoiceSeconds = 0;
      _recordingAutoStopped = false;
    });

    try {
      await _voiceRecorder.cancel();
    } catch (_) {}

    if (draftPath.isNotEmpty) {
      try {
        await File(draftPath).delete();
      } catch (_) {}
    }
  }

  static const int _maxVoiceNoteBytes = 550 * 1024;
  static const int _voiceNoteAutoStopThresholdBytes =
      _maxVoiceNoteBytes - (8 * 1024);

  Future<void> _checkRecordingFileSize() async {
    if (!_isRecordingVoice) return;
    if (_recordingAutoStopped) return;
    final path = (_recordingVoicePath ?? '').trim();
    if (path.isEmpty) return;
    if (_recordingSizeCheckInProgress) return;
    _recordingSizeCheckInProgress = true;
    try {
      final size = await File(path).length();
      if (size >= _voiceNoteAutoStopThresholdBytes) {
        await _stopRecordingDueToSizeLimit();
      }
    } catch (_) {
      // Ignore read errors while the file is being written.
    } finally {
      _recordingSizeCheckInProgress = false;
    }
  }

  Future<void> _stopRecordingDueToSizeLimit() async {
    if (!_isRecordingVoice) return;
    if (_recordingAutoStopped) return;
    _recordingAutoStopped = true;

    final id = (_recordingVoiceId ?? '').trim();
    final mime = (_recordingVoiceMime ?? '').trim();
    final startedAt = _recordingVoiceStartedAt;

    _recordingVoiceTimer?.cancel();
    _recordingVoiceTimer = null;

    String? path;
    try {
      path = await _voiceRecorder.stop();
    } catch (_) {
      path = null;
    }

    final cleanedPath = (path ?? '').trim();
    if (!mounted) return;

    setState(() {
      _isRecordingVoice = false;
      _recordingVoiceId = null;
      _recordingVoiceMime = null;
      _recordingVoicePath = null;
      _recordingVoiceStartedAt = null;
      _recordingVoiceSeconds = 0;
      _pendingVoiceDraftId = id.isEmpty ? _uuid.v4() : id;
      _pendingVoiceDraftPath = cleanedPath.isEmpty ? null : cleanedPath;
      _pendingVoiceDraftMime = mime.isEmpty ? null : mime;
      _pendingVoiceDraftDurationMs = startedAt == null
          ? null
          : DateTime.now().difference(startedAt).inMilliseconds;
    });

    if (cleanedPath.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Max voice note length reached. Send it as-is?'),
        action: SnackBarAction(
          label: 'Send',
          onPressed: _sendPendingVoiceDraft,
        ),
      ),
    );
  }

  Future<void> _stopAndSendVoiceNote() async {
    if (!_isRecordingVoice) return;

    final id = (_recordingVoiceId ?? '').trim();
    final mime = (_recordingVoiceMime ?? '').trim();
    final startedAt = _recordingVoiceStartedAt;

    _recordingVoiceTimer?.cancel();
    _recordingVoiceTimer = null;

    setState(() {
      _isRecordingVoice = false;
      _recordingVoiceId = null;
      _recordingVoiceMime = null;
      _recordingVoicePath = null;
      _recordingVoiceStartedAt = null;
      _recordingVoiceSeconds = 0;
      _recordingAutoStopped = false;
    });

    String? path;
    try {
      path = await _voiceRecorder.stop();
    } catch (_) {
      path = null;
    }
    final cleanedPath = (path ?? '').trim();
    if (cleanedPath.isEmpty) return;

    final file = File(cleanedPath);
    try {
      if (!await file.exists()) return;
    } catch (_) {
      return;
    }

    late List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return;
    }
    if (bytes.isEmpty) return;
    if (bytes.length > _maxVoiceNoteBytes) {
      if (!mounted) return;
      setState(() {
        _pendingVoiceDraftId = id.isEmpty ? _uuid.v4() : id;
        _pendingVoiceDraftPath = cleanedPath;
        _pendingVoiceDraftMime = mime.isEmpty ? null : mime;
        _pendingVoiceDraftDurationMs = startedAt == null
            ? null
            : DateTime.now().difference(startedAt).inMilliseconds;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Voice note hit the size limit. Send it as-is?'),
          action: SnackBarAction(
            label: 'Send',
            onPressed: _sendPendingVoiceDraft,
          ),
        ),
      );
      return;
    }

    final durationMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;
    final senderId = _currentSenderId();
    final replyTo = _replyingToMessage == null
        ? null
        : _replyPreviewForMessage(_replyingToMessage!);

    final stored = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: 'Voice message',
      id: id.isEmpty ? null : id,
      type: ChatMessage.typeVoice,
      voicePath: cleanedPath,
      voiceMime: mime.isEmpty ? null : mime,
      voiceDurationMs: durationMs,
      replyTo: replyTo,
    );
    if (stored == null) return;
    _clearReplyDraft();

    // Voice bytes are base64 in the payload JSON, and the payload JSON itself
    // is then base64 for envelope transport.
    final voiceB64 = base64Encode(bytes);
    unawaited(
      _dispatchThreadMessage(
        _buildRelayMessage(
          id: stored.id,
          chatId: stored.chatId,
          senderId: stored.senderId,
          senderName: IdentityStore.displayName,
          type: RelayMessage.typeVoice,
          body: stored.body,
          voiceB64: voiceB64,
          voiceMime: stored.voiceMime,
          voiceDurationMs: stored.voiceDurationMs,
          replyTo: stored.replyTo,
          createdAt: stored.createdAt,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {});
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Future<void> _discardPendingVoiceDraft() async {
    final path = (_pendingVoiceDraftPath ?? '').trim();
    if (mounted) {
      setState(() {
        _pendingVoiceDraftId = null;
        _pendingVoiceDraftPath = null;
        _pendingVoiceDraftMime = null;
        _pendingVoiceDraftDurationMs = null;
      });
    } else {
      _pendingVoiceDraftId = null;
      _pendingVoiceDraftPath = null;
      _pendingVoiceDraftMime = null;
      _pendingVoiceDraftDurationMs = null;
    }

    if (path.isNotEmpty) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _sendPendingVoiceDraft() async {
    final path = (_pendingVoiceDraftPath ?? '').trim();
    if (path.isEmpty) return;

    final id = (_pendingVoiceDraftId ?? '').trim();
    final mime = (_pendingVoiceDraftMime ?? '').trim();
    final durationMs = _pendingVoiceDraftDurationMs;

    final file = File(path);
    try {
      if (!await file.exists()) {
        await _discardPendingVoiceDraft();
        return;
      }
    } catch (_) {
      return;
    }

    late List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return;
    }
    if (bytes.isEmpty) return;

    final senderId = _currentSenderId();
    final replyTo = _replyingToMessage == null
        ? null
        : _replyPreviewForMessage(_replyingToMessage!);

    final stored = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: 'Voice message',
      id: id.isEmpty ? null : id,
      type: ChatMessage.typeVoice,
      voicePath: path,
      voiceMime: mime.isEmpty ? null : mime,
      voiceDurationMs: durationMs,
      replyTo: replyTo,
    );
    if (stored == null) return;
    _clearReplyDraft();

    final voiceB64 = base64Encode(bytes);
    unawaited(
      _dispatchThreadMessage(
        _buildRelayMessage(
          id: stored.id,
          chatId: stored.chatId,
          senderId: stored.senderId,
          senderName: IdentityStore.displayName,
          type: RelayMessage.typeVoice,
          body: stored.body,
          voiceB64: voiceB64,
          voiceMime: stored.voiceMime,
          voiceDurationMs: stored.voiceDurationMs,
          replyTo: stored.replyTo,
          createdAt: stored.createdAt,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _pendingVoiceDraftId = null;
      _pendingVoiceDraftPath = null;
      _pendingVoiceDraftMime = null;
      _pendingVoiceDraftDurationMs = null;
    });
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Future<void> _toggleVoicePlayback(ChatMessage message) async {
    if (!message.isVoiceNote) return;

    final id = message.id.trim();
    final path = (message.voicePath ?? '').trim();
    if (id.isEmpty || path.isEmpty) return;

    try {
      final exists = await File(path).exists();
      if (!exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice note file is missing')),
        );
        return;
      }
    } catch (_) {}

    final isSelected = _playingVoiceMessageId == id;
    if (isSelected) {
      try {
        if (_voiceIsPlaying) {
          await _voicePlayer.pause();
        } else {
          await _voicePlayer.resume();
        }
      } catch (_) {}
      return;
    }

    try {
      await _voicePlayer.stop();
    } catch (_) {}

    if (!mounted) return;
    setState(() => _playingVoiceMessageId = id);

    try {
      await _voicePlayer.play(DeviceFileSource(path));
    } catch (e) {
      if (!mounted) return;
      setState(() => _playingVoiceMessageId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Voice playback failed: $e')));
    }
  }

  Widget _buildVoiceNoteContent(ChatMessage message, {required bool isMe}) {
    final selected = _playingVoiceMessageId == message.id.trim();
    final icon = selected && _voiceIsPlaying
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    final duration = _formatDurationMs(message.voiceDurationMs);
    final label = duration.isEmpty ? 'Voice note' : 'Voice note • $duration';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _toggleVoicePlayback(message),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (isMe ? Colors.white : Colors.black).withValues(
                alpha: 0.12,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14.2,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStickerContent(ChatMessage message, {double? sizeOverride}) {
    final packId = (message.stickerPackId ?? '').trim();
    final stickerId = (message.stickerId ?? '').trim();
    final sticker = StickerCatalog.findSticker(packId, stickerId);
    if (sticker == null) {
      return const Text(
        'Sticker unavailable',
        style: TextStyle(color: Colors.white70),
      );
    }

    final isLottieLike =
        sticker.type == StickerAssetType.lottie ||
        sticker.type == StickerAssetType.animatedEmoji;
    final defaultSize = isLottieLike ? 124.0 : 108.0;
    final size = sizeOverride ?? defaultSize;
    if (sticker.type == StickerAssetType.staticImage ||
        sticker.type == StickerAssetType.animatedWebp) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(sticker.assetPath, fit: BoxFit.contain),
      );
    }

    if (sticker.type == StickerAssetType.animatedEmoji) {
      return SizedBox(
        width: size,
        height: size,
        child: AnimatedEmoji(assetPath: sticker.assetPath),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<LottieComposition?>(
        future: StickerCache.loadLottie(sticker.assetPath),
        builder: (context, snapshot) {
          final comp = snapshot.data;
          if (comp == null) {
            return Lottie.asset(sticker.assetPath, fit: BoxFit.contain);
          }
          return Lottie(composition: comp, fit: BoxFit.contain, repeat: true);
        },
      ),
    );
  }

  Future<Uint8List?> _readAttachmentPreviewBytes(String path) {
    final key = path.trim();
    return _attachmentPreviewBytes.putIfAbsent(key, () {
      return MediaStorage.readDecryptedBytes(
        key,
        attachmentId: _resolveAttachmentIdFromPath(key),
      ).timeout(const Duration(seconds: 12)).catchError((_) => null);
    });
  }

  Future<Uint8List?> _readAttachmentThumbnailBytes({
    required String encryptedPath,
    required String id,
    required String extension,
  }) {
    final key = '$encryptedPath|$id|$extension';
    return _attachmentThumbnailBytes.putIfAbsent(key, () {
      return MediaStorage.readVideoThumbnailBytes(
        encryptedPath: encryptedPath,
        id: id,
        extension: extension,
        attachmentId: id,
      ).timeout(const Duration(seconds: 10)).catchError((_) => null);
    });
  }

  String? _resolveAttachmentIdFromPath(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return null;
    final fileName = normalized.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName.trim().isEmpty ? null : fileName.trim();
    }
    final value = fileName.substring(0, dotIndex).trim();
    return value.isEmpty ? null : value;
  }

  Widget _buildAttachmentContent(ChatMessage message) {
    final mime = (message.attachmentMime ?? '').trim();
    final name = (message.attachmentName ?? 'Attachment').trim();
    final size = message.attachmentSize ?? 0;
    final path = (message.attachmentPath ?? '').trim();
    final hasPath = path.isNotEmpty;
    final isImage = mime.startsWith('image/') && hasPath;
    final isVideo = mime.startsWith('video/') && hasPath;
    final previewWidth = (MediaQuery.of(context).size.width * 0.40).clamp(
      164.0,
      212.0,
    );
    final imagePreviewHeight = (previewWidth * 0.88).clamp(126.0, 188.0);
    final videoPreviewHeight = (previewWidth * 0.58).clamp(98.0, 148.0);

    if (isImage) {
      return InkWell(
        onTap: () => _openAttachmentPreview(message),
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Uint8List?>(
          future: _readAttachmentPreviewBytes(path),
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (snapshot.connectionState != ConnectionState.done) {
              return Container(
                width: previewWidth,
                height: imagePreviewHeight,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            if (data == null || data.isEmpty) {
              return Container(
                width: previewWidth,
                height: imagePreviewHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white54,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Image unavailable',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Container(
                    width: previewWidth,
                    height: imagePreviewHeight,
                    color: Colors.black.withValues(alpha: 0.16),
                    alignment: Alignment.center,
                    child: Image.memory(
                      data,
                      fit: BoxFit.contain,
                      width: previewWidth,
                      height: imagePreviewHeight,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'View',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    if (isVideo) {
      final extension = _attachmentExtensionFor(name: name, mime: mime);
      return InkWell(
        onTap: () => _openAttachmentPreview(message),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: previewWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: previewWidth,
                  height: videoPreviewHeight,
                  child: FutureBuilder<Uint8List?>(
                    future: _readAttachmentThumbnailBytes(
                      encryptedPath: path,
                      id: message.attachmentId ?? message.id,
                      extension: extension,
                    ),
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (data != null)
                            Image.memory(
                              data,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          else
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.08),
                                    Colors.white.withValues(alpha: 0.02),
                                  ],
                                ),
                              ),
                            ),
                          Container(
                            color: Colors.black.withValues(alpha: 0.16),
                          ),
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 56,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.58),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Video',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    size: 14,
                    color: Colors.white60,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      size > 0
                          ? '${_formatBytes(size)} • Tap to play'
                          : 'Tap to play',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                if (size > 0)
                  Text(
                    _formatBytes(size),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAttachmentPreview(ChatMessage message) async {
    final path = (message.attachmentPath ?? '').trim();
    final mime = (message.attachmentMime ?? '').trim();
    if (path.isEmpty) return;
    if (!mime.startsWith('image/') && !mime.startsWith('video/')) {
      return;
    }
    await pushOrPresentDesktopCard<void>(
      context,
      settings: RouteSettings(name: '/attachment-preview/${message.id}'),
      maxWidth: 760,
      maxHeightFactor: 0.82,
      builder: (_) => _AttachmentPreviewScreen(message: message),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
  }

  void _handleVoicePlaybackComplete() {
    final completedId = (_playingVoiceMessageId ?? '').trim();
    if (completedId.isEmpty) return;

    if (mounted) {
      setState(() => _playingVoiceMessageId = null);
    } else {
      _playingVoiceMessageId = null;
    }

    if (!VoiceNotesStore.autoplayNext) return;
    unawaited(_playNextVoiceNote(afterMessageId: completedId));
  }

  Future<void> _playNextVoiceNote({required String afterMessageId}) async {
    if (!mounted) return;
    if (!VoiceNotesStore.autoplayNext) return;

    final messages = MessageStore.getMessagesForChat(widget.chatId);
    final idx = messages.indexWhere((m) => m.id == afterMessageId);
    if (idx < 0) return;

    for (var i = idx + 1; i < messages.length; i++) {
      final m = messages[i];
      if (m.isVoiceNote) {
        await _toggleVoicePlayback(m);
        return;
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final senderId = _currentSenderId();
    final replyTo = _replyingToMessage == null
        ? null
        : _replyPreviewForMessage(_replyingToMessage!);
    final message = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: text,
      replyTo: replyTo,
    );

    if (message == null) return;
    _clearReplyDraft();
    unawaited(
      _dispatchThreadMessage(
        _buildRelayMessage(
          id: message.id,
          chatId: message.chatId,
          senderId: message.senderId,
          senderName: IdentityStore.displayName,
          body: message.body,
          createdAt: message.createdAt,
          replyTo: message.replyTo,
        ),
      ),
    );

    _controller.clear();
    if (!mounted) return;
    setState(() {});
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Future<void> _sendSticker(StickerAsset sticker) async {
    final senderId = _currentSenderId();
    final replyTo = _replyingToMessage == null
        ? null
        : _replyPreviewForMessage(_replyingToMessage!);

    final message = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: sticker.name,
      type: ChatMessage.typeSticker,
      stickerPackId: sticker.packId,
      stickerId: sticker.id,
      replyTo: replyTo,
    );

    if (message == null) return;
    _clearReplyDraft();

    await StickerStore.addRecent(
      StickerRef(packId: sticker.packId, stickerId: sticker.id),
    );

    unawaited(
      _dispatchThreadMessage(
        _buildRelayMessage(
          id: message.id,
          chatId: message.chatId,
          senderId: message.senderId,
          senderName: IdentityStore.displayName,
          body: message.body,
          type: RelayMessage.typeSticker,
          stickerPackId: sticker.packId,
          stickerId: sticker.id,
          stickerVariant: message.stickerVariant,
          replyTo: message.replyTo,
          createdAt: message.createdAt,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {});
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Future<IncomingAttachmentIngestResult> _handleIncomingAttachmentChunk(
    RelayMessage relayMessage, {
    String? resolvedChatId,
  }) async {
    return IncomingAttachmentIngest.ingestChunk(
      relayMessage,
      resolvedChatId: (resolvedChatId ?? relayMessage.chatId).trim(),
    );
  }

  Future<IncomingAttachmentIngestResult> _handleIncomingAttachmentManifest(
    RelayMessage relayMessage, {
    required String resolvedChatId,
  }) async {
    return IncomingAttachmentIngest.ingestManifest(
      relayMessage,
      resolvedChatId: resolvedChatId,
    );
  }

  Future<void> _openAttachmentPicker() async {
    final path = await _pickAttachmentPath();
    if (path == null || path.trim().isEmpty) return;

    final options = await _showAttachmentOptions();
    if (options == null) return;

    await _sendAttachment(path.trim(), options);
  }

  Future<void> _openGifPicker() async {
    final path = await pushOrPresentDesktopCard<String>(
      context,
      settings: const RouteSettings(name: '/gifs'),
      maxWidth: 720,
      maxHeightFactor: 0.82,
      builder: (_) => const GiphySearchScreen(),
    );
    if (path == null || path.trim().isEmpty) return;
    await _sendAttachment(
      path.trim(),
      MediaSendPolicy(
        quality: MediaQualityPreset.original,
        stripMetadata: false,
        wifiOnly: MediaPolicyStore.policy.wifiOnly,
      ),
    );
  }

  Future<String?> _pickAttachmentPath() async {
    if (_prefersDeviceAlbumPicker) {
      final selection = await SecurityStore.runWithAutoLockSuppressed(
        () => showDeviceMediaPicker(
          context,
          title: 'Choose from Albums',
          mode: DeviceMediaPickerMode.mixed,
        ),
      );
      return selection?.path;
    }

    final result = await SecurityStore.runWithAutoLockSuppressed(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _mediaExtensions,
      ),
    );
    return result?.files.single.path;
  }

  Future<String?> _pickBackgroundPath() async {
    if (_prefersDeviceAlbumPicker) {
      final selection = await SecurityStore.runWithAutoLockSuppressed(
        () => showDeviceMediaPicker(
          context,
          title: 'Choose Background',
          mode: DeviceMediaPickerMode.image,
        ),
      );
      return selection?.path;
    }

    final result = await SecurityStore.runWithAutoLockSuppressed(
      () => FilePicker.platform.pickFiles(type: FileType.image),
    );
    return result?.files.single.path;
  }

  double _backgroundBrightness(ChatAppearance? appearance) {
    return (appearance?.backgroundBrightness ?? 0.32).clamp(0.0, 1.0);
  }

  double _backgroundBlur(ChatAppearance? appearance) {
    return (appearance?.backgroundBlur ?? 0.0).clamp(0.0, 12.0);
  }

  String _backgroundEffectsSubtitle(ChatAppearance? appearance) {
    final brightness = (_backgroundBrightness(appearance) * 100).round();
    final blur = _backgroundBlur(appearance).toStringAsFixed(0);
    return 'Brightness $brightness% • Blur $blur';
  }

  Future<void> _showBackgroundEffectsEditor() async {
    final current = ChatAppearanceStore.getForChat(widget.chatId);
    var brightness = _backgroundBrightness(current);
    var blur = _backgroundBlur(current);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final brightnessPercent = (brightness * 100).round();
            return AlertDialog(
              title: const Text('Background Effects'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keep the wallpaper crisp, dim it down, or blur it until the chat stays readable.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(child: Text('Brightness')),
                        Text('$brightnessPercent%'),
                      ],
                    ),
                    Slider(
                      min: 0,
                      max: 1,
                      divisions: 20,
                      value: brightness,
                      onChanged: (value) {
                        setDialogState(() => brightness = value);
                      },
                    ),
                    Row(
                      children: [
                        const Expanded(child: Text('Blur')),
                        Text(blur.toStringAsFixed(0)),
                      ],
                    ),
                    Slider(
                      min: 0,
                      max: 12,
                      divisions: 12,
                      value: blur,
                      onChanged: (value) {
                        setDialogState(() => blur = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await ChatAppearanceStore.setBackgroundEffects(
                      widget.chatId,
                      brightness: 0.32,
                      blur: 0,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    await ChatAppearanceStore.setBackgroundEffects(
                      widget.chatId,
                      brightness: brightness,
                      blur: blur,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<MediaSendPolicy?> _showAttachmentOptions() async {
    final base = MediaPolicyStore.policy;
    final isWindows = !kIsWeb && Platform.isWindows;
    return showModalBottomSheet<MediaSendPolicy>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A0024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        MediaQualityPreset quality = MediaQualityPreset.original;
        bool strip = false;
        bool wifiOnly = base.wifiOnly;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final sendLabel =
                isWindows || (quality == MediaQualityPreset.original && !strip)
                ? 'Send Original'
                : 'Send';
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Send Attachment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Original size is the default. Only change the options below if you want to compress an image or strip metadata before sending.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        height: 1.25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!isWindows) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Quality',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: MediaQualityPreset.values.map((preset) {
                          final selected = quality == preset;
                          return ChoiceChip(
                            label: Text(_qualityLabel(preset)),
                            selected: selected,
                            onSelected: (_) => setSheetState(() {
                              quality = preset;
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: strip,
                      title: const Text('Strip metadata'),
                      subtitle: const Text(
                        'Only if you want to remove EXIF data',
                      ),
                      onChanged: (value) => setSheetState(() {
                        strip = value;
                      }),
                    ),
                    SwitchListTile(
                      value: wifiOnly,
                      title: const Text('Upload only on Wi-Fi'),
                      subtitle: const Text('Optional global preference'),
                      onChanged: (value) => setSheetState(() {
                        wifiOnly = value;
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await MediaPolicyStore.setWifiOnly(wifiOnly);
                              if (sheetContext.mounted) {
                                Navigator.pop(
                                  sheetContext,
                                  MediaSendPolicy(
                                    quality: isWindows
                                        ? MediaQualityPreset.original
                                        : quality,
                                    stripMetadata: strip,
                                    wifiOnly: wifiOnly,
                                  ),
                                );
                              }
                            },
                            child: Text(sendLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _qualityLabel(MediaQualityPreset preset) {
    switch (preset) {
      case MediaQualityPreset.original:
        return 'Original';
      case MediaQualityPreset.small:
        return 'Small';
      case MediaQualityPreset.medium:
        return 'Medium';
      case MediaQualityPreset.large:
        return 'Large';
    }
  }

  Future<void> _sendAttachment(String path, MediaSendPolicy policy) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final name = path.split(RegExp(r'[\\\\/]+')).last;
    final mime = _guessMimeType(name);

    try {
      final inline = _isInlineMedia(mime);

      final bytes = await file.readAsBytes();

      Uint8List processed = bytes;
      if (policy.stripMetadata ||
          policy.quality != MediaQualityPreset.original) {
        final transformed = await _processMedia(
          bytes: bytes,
          mime: mime,
          quality: policy.quality,
          stripMetadata: policy.stripMetadata,
        );
        if (transformed != null) {
          processed = transformed;
        }
      }

      final senderId = _currentSenderId();
      final attachmentId = _uuid.v4();
      final manifestMessageId = attachmentId;
      final mediaKey = MediaCipher.generateAttachmentKey();
      try {
        final encryptedPath = await MediaStorage.storeEncryptedBytes(
          id: attachmentId,
          bytes: processed,
          mediaKey: mediaKey,
        );

        final replyTo = _replyingToMessage == null
            ? null
            : _replyPreviewForMessage(_replyingToMessage!);
        final message = await MessageStore.addMessage(
          chatId: widget.chatId,
          senderId: senderId,
          body: 'Attachment: $name',
          id: manifestMessageId,
          type: ChatMessage.typeAttachment,
          attachmentId: attachmentId,
          attachmentName: name,
          attachmentMime: mime,
          attachmentSize: processed.length,
          attachmentPath: encryptedPath,
          attachmentInline: inline,
          replyTo: replyTo,
        );
        if (message == null) return;
        _clearReplyDraft();

        final sent = await _sendAttachmentChunks(
          attachmentId: attachmentId,
          manifestMessageId: manifestMessageId,
          name: name,
          mime: mime,
          inline: inline,
          bytes: processed,
          mediaKey: mediaKey,
          replyTo: message.replyTo,
        );
        if (!sent) {
          await MessageStore.removeMessage(
            chatId: widget.chatId,
            messageId: message.id,
          );
          _showSendFailureSnackBar();
          if (!mounted) return;
          setState(() {});
          return;
        }

        if (!mounted) return;
        setState(() {});
        _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
      } finally {
        mediaKey.fillRange(0, mediaKey.length, 0);
      }
    } catch (_) {
      _showSendFailureSnackBar();
      return;
    }
  }

  Future<bool> _sendAttachmentChunks({
    required String attachmentId,
    required String manifestMessageId,
    required String name,
    required String mime,
    required bool inline,
    required Uint8List bytes,
    required Uint8List mediaKey,
    MessageReplyPreview? replyTo,
  }) async {
    final sendPlan = await _prepareVaultSendPlan();
    if (sendPlan == null) {
      return false;
    }
    final encrypted = MediaCipher.encrypt(bytes, keyBytes: mediaKey);
    final attachmentKeyB64 = base64Encode(mediaKey);
    final transportHash = sha256.convert(encrypted).toString();
    final totalChunks = (encrypted.length / _attachmentChunkSize).ceil().clamp(
      1,
      999999,
    );

    for (var i = 0; i < totalChunks; i++) {
      final start = i * _attachmentChunkSize;
      final end = (start + _attachmentChunkSize).clamp(0, encrypted.length);
      final chunk = encrypted.sublist(start, end);
      final chunkB64 = base64Encode(chunk);
      final sent = await _sendAttachmentChunkWithRetry(
        _buildRelayMessage(
          id: '${attachmentId}_$i',
          chatId: widget.chatId,
          senderId: _currentSenderId(),
          senderName: IdentityStore.displayName,
          type: RelayMessage.typeAttachmentChunk,
          body: 'Attachment',
          attachmentId: attachmentId,
          attachmentName: name,
          attachmentMime: mime,
          attachmentSize: encrypted.length,
          attachmentChunkIndex: i,
          attachmentChunkCount: totalChunks,
          attachmentChunkB64: chunkB64,
          attachmentInline: inline,
          replyTo: replyTo,
          createdAt: DateTime.now(),
        ),
        plan: sendPlan,
      );
      if (!sent) return false;
    }
    return _sendAttachmentManifestWithRetry(
      _buildRelayMessage(
        id: manifestMessageId,
        chatId: widget.chatId,
        senderId: _currentSenderId(),
        senderName: IdentityStore.displayName,
        type: RelayMessage.typeAttachmentManifest,
        body: 'Attachment: $name',
        attachmentId: attachmentId,
        attachmentName: name,
        attachmentMime: mime,
        attachmentSize: bytes.length,
        attachmentHash: transportHash,
        attachmentKeyB64: attachmentKeyB64,
        attachmentChunkCount: totalChunks,
        attachmentInline: inline,
        replyTo: replyTo,
        createdAt: DateTime.now(),
      ),
      plan: sendPlan,
    );
  }

  Future<bool> _sendAttachmentChunkWithRetry(
    RelayMessage message, {
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
          await WindowsVaultHelperBridge.restartHelper();
        }
        await Future<void>.delayed(delay);
      }
      final sent = await _dispatchThreadMessage(
        message,
        notifyOnFailure: attempt == retryDelays.length - 1,
        plan: plan,
        requireAllDestinations: false,
      );
      if (sent) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _sendAttachmentManifestWithRetry(
    RelayMessage message, {
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
          await WindowsVaultHelperBridge.restartHelper();
        }
        await Future<void>.delayed(delay);
      }
      final sent = await _dispatchThreadMessage(
        message,
        notifyOnFailure: attempt == retryDelays.length - 1,
        plan: plan,
        requireAllDestinations: false,
      );
      if (sent) {
        return true;
      }
    }
    return false;
  }

  bool _isInlineMedia(String mime) {
    if (mime.startsWith('image/')) return true;
    return false;
  }

  String _guessMimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'application/octet-stream';
  }

  Future<Uint8List?> _processMedia({
    required Uint8List bytes,
    required String mime,
    required MediaQualityPreset quality,
    required bool stripMetadata,
  }) async {
    if (!mime.startsWith('image/') || mime == 'image/gif') {
      return null;
    }
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final target = _resizeForQuality(image, quality);
      final outImage = target ?? image;

      if (mime == 'image/png') {
        return Uint8List.fromList(img.encodePng(outImage));
      }
      if (mime == 'image/webp') {
        // Keep WebP input untouched until we add a supported encoder path.
        return bytes;
      }
      return Uint8List.fromList(img.encodeJpg(outImage, quality: 85));
    } catch (_) {
      return null;
    }
  }

  img.Image? _resizeForQuality(img.Image image, MediaQualityPreset quality) {
    if (quality == MediaQualityPreset.original) return null;
    final maxSide = switch (quality) {
      MediaQualityPreset.small => 720,
      MediaQualityPreset.medium => 1280,
      MediaQualityPreset.large => 1920,
      MediaQualityPreset.original => image.width,
    };
    if (image.width <= maxSide && image.height <= maxSide) {
      return image;
    }
    return img.copyResize(
      image,
      width: image.width >= image.height ? maxSide : null,
      height: image.height > image.width ? maxSide : null,
    );
  }

  void _insertEmojiIntoComposer(String emojiValue) {
    final value = _controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(0, text.length);
    final replaceStart = safeStart < safeEnd ? safeStart : safeEnd;
    final replaceEnd = safeStart < safeEnd ? safeEnd : safeStart;
    final nextText = text.replaceRange(replaceStart, replaceEnd, emojiValue);
    final nextOffset = replaceStart + emojiValue.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    if (mounted) {
      FocusScope.of(context).requestFocus(_composerFocusNode);
    }
  }

  Future<void> _openStickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A0024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => VaultEmojiStickerPickerSheet(
        onSelectEmoji: _insertEmojiIntoComposer,
        onSelectSticker: _sendSticker,
        onLongPressSticker: _showStickerActions,
      ),
    );
  }

  Future<void> _showStickerActions(StickerAsset sticker) async {
    final ref = StickerRef(packId: sticker.packId, stickerId: sticker.id);
    final isFavorite = StickerStore.isFavorite(ref);
    final inRecents = StickerStore.recents.any((r) => r.key == ref.key);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A0024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                title: Text(
                  isFavorite ? 'Remove from favorites' : 'Add to favorites',
                ),
                onTap: () async {
                  await StickerStore.toggleFavorite(ref);
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
              if (inRecents)
                ListTile(
                  title: const Text('Remove from recents'),
                  onTap: () async {
                    await StickerStore.removeRecent(ref);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
              ListTile(
                title: const Text('Pack info'),
                subtitle: Text(
                  StickerCatalog.findPack(sticker.packId)?.title ??
                      'Unknown pack',
                ),
                onTap: () {
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
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
        final hasContactTone =
            !hasChatTone && contactToneUri != null && contactToneUri.isNotEmpty;
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
              if (!_isDirectMessageThread) ...[
                ListTile(
                  title: const Text('Copy Invite'),
                  subtitle: const Text('Share this chat with another device'),
                  onTap: () async {
                    await _copyInvitePayload();
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
                    await Future<void>.delayed(
                      const Duration(milliseconds: 120),
                    );
                    if (!mounted) return;
                    await _showInviteQr();
                  },
                ),
              ],
              ListTile(
                title: const Text('Set Background'),
                onTap: () async {
                  final path = await _pickBackgroundPath();
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
                title: const Text('Background Effects'),
                subtitle: Text(_backgroundEffectsSubtitle(chatAppearance)),
                onTap: () async {
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                  await Future<void>.delayed(const Duration(milliseconds: 120));
                  if (!mounted) return;
                  await _showBackgroundEffectsEditor();
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
                  muted
                      ? 'Unmute Push Notifications'
                      : 'Mute Push Notifications',
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
                      content: Text(!muted ? 'Chat muted' : 'Chat unmuted'),
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

  String _buildInvitePayload(String? sharedSecret) {
    return VaultChatInvite(
      chatId: widget.chatId,
      title: widget.chatTitle,
      sharedSecret: sharedSecret,
      transport: _isDirectMessageThread ? 'vault_direct' : 'vault_group',
    ).toInviteLink();
  }

  Future<void> _copyInvitePayload() async {
    if (_isDirectMessageThread) return;
    final groupReady = await _ensureVaultGroupReady();
    if (!groupReady || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not prepare this Vault invite.')),
        );
      }
      return;
    }
    final sharedSecret = await ChatStore.ensureSharedSecret(widget.chatId);
    if (!mounted) return;
    await Clipboard.setData(
      ClipboardData(text: _buildInvitePayload(sharedSecret)),
    );
  }

  Future<void> _showInviteQr() async {
    if (_isDirectMessageThread) return;
    final groupReady = await _ensureVaultGroupReady();
    if (!groupReady || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not prepare this Vault invite.')),
        );
      }
      return;
    }
    final sharedSecret = await ChatStore.ensureSharedSecret(widget.chatId);
    if (!mounted) return;
    final payload = _buildInvitePayload(sharedSecret);
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
    return DateTimeFormatStore.formatMessageTimestamp(context, dt);
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
        final threshold = p.viewportDimension * 0.35;
        final nearBottom =
            (p.maxScrollExtent - p.pixels) <=
            (threshold < 220 ? 220 : threshold);
        if (!nearBottom) return;
      }
      if (jump) {
        _scrollController.jumpTo(p.maxScrollExtent);
        _markThreadReadIfNearBottom(force: true);
        _scheduleVisibleReadReceiptSweep();
        _scheduleScrollSettlement(onlyIfNearBottom: onlyIfNearBottom);
        return;
      }
      _scrollController
          .animateTo(
            p.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          )
          .whenComplete(() {
            _markThreadReadIfNearBottom(force: true);
            _scheduleVisibleReadReceiptSweep();
            _scheduleScrollSettlement(onlyIfNearBottom: onlyIfNearBottom);
          });
    });
  }

  void _scheduleScrollSettlement({required bool onlyIfNearBottom}) {
    _scrollSettleTimer?.cancel();
    _scrollSettleTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasPixels) return;
      if (onlyIfNearBottom) {
        final threshold = position.viewportDimension * 0.35;
        final nearBottom =
            (position.maxScrollExtent - position.pixels) <=
            (threshold < 220 ? 220 : threshold);
        if (!nearBottom) return;
      }
      _scrollController.jumpTo(position.maxScrollExtent);
      _markThreadReadIfNearBottom(force: true);
      _scheduleVisibleReadReceiptSweep();
    });
  }

  void _handleStickyScroll(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      _lastMessageCount = 0;
      _lastStickyLastId = '';
      _didInitialScrollToBottom = false;
      return;
    }

    final lastId = messages.last.id.trim();
    if (!_didInitialScrollToBottom) {
      // Chat UX: open at the latest message, not at the top of history.
      _didInitialScrollToBottom = true;
      _lastMessageCount = messages.length;
      _lastStickyLastId = lastId;
      _scheduleScrollToBottom(jump: true, onlyIfNearBottom: false);
      return;
    }

    final count = messages.length;
    final grew = count > _lastMessageCount;
    final tailChanged = lastId != _lastStickyLastId;
    _lastMessageCount = count;
    _lastStickyLastId = lastId;
    if (!grew && !tailChanged) return;

    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Widget _buildThreadTitle() {
    final isDirectThread = (widget.contactId ?? '').trim().isNotEmpty;
    final subtitle = isDirectThread ? 'Direct chat' : 'Secure group chat';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.chatTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.4,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.8,
            color: _textSoft.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildThreadActions(BuildContext context) {
    return [
      if ((widget.contactId ?? '').trim().isNotEmpty)
        AnimatedBuilder(
          animation: Listenable.merge([
            CallPolicyStore.modeNotifier,
            CallPolicyStore.neverAllowNotifier,
          ]),
          builder: (context, _) {
            final mode = CallPolicyStore.mode;
            final contactId = (widget.contactId ?? '').trim();
            final blocked = CallPolicyStore.neverAllow.contains(contactId);
            final disabled = mode == WhoCanCallMode.noPhoneCalls || blocked;
            return IconButton(
              tooltip: disabled ? 'Calls disabled' : 'Call',
              icon: Icon(
                Icons.call,
                color: disabled ? _textSoft.withValues(alpha: 0.45) : _text,
              ),
              onPressed: disabled
                  ? null
                  : () => CallService.startOutgoingCall(
                      context: context,
                      mailboxId: _directCallMailboxId(),
                      peerId: contactId,
                      peerName: widget.chatTitle,
                    ),
            );
          },
        ),
      IconButton(
        tooltip: 'Settings',
        icon: Icon(Icons.settings_outlined, color: _text),
        onPressed: _openSettingsSheet,
      ),
    ];
  }

  PreferredSizeWidget _buildThreadAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _screenBg,
      foregroundColor: _text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      title: _buildThreadTitle(),
      actions: _buildThreadActions(context),
    );
  }

  Widget _buildEmbeddedHeader(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            children: [
              Expanded(child: _buildThreadTitle()),
              ..._buildThreadActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreadBody(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ChatAppearanceStore.appearancesNotifier,
      builder: (context, _, __) {
        final appearance = ChatAppearanceStore.getForChat(widget.chatId);
        final backgroundUri = appearance?.backgroundUri?.trim();
        final backgroundBrightness = _backgroundBrightness(appearance);
        final backgroundBlur = _backgroundBlur(appearance);
        final backgroundDimAlpha = (1 - backgroundBrightness) * 0.72;
        return LayoutBuilder(
          builder: (context, viewport) {
            final centeredDesktopThread =
                widget.embedded && viewport.maxWidth >= 840;
            final contentWidth = centeredDesktopThread
                ? 660.0
                : viewport.maxWidth;
            final messagePadding = centeredDesktopThread
                ? const EdgeInsets.fromLTRB(16, 10, 16, 12)
                : const EdgeInsets.fromLTRB(8, 8, 8, 10);
            final composerPadding = centeredDesktopThread
                ? const EdgeInsets.fromLTRB(16, 2, 16, 6)
                : const EdgeInsets.fromLTRB(8, 2, 8, 6);

            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: _screenBg),
                  ),
                ),
                if (backgroundUri != null && backgroundUri.isNotEmpty)
                  Positioned.fill(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: backgroundDimAlpha),
                        BlendMode.darken,
                      ),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: backgroundBlur,
                          sigmaY: backgroundBlur,
                        ),
                        child: Image.file(
                          File(backgroundUri),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    color: _overlayTint.withValues(
                      alpha: backgroundUri != null && backgroundUri.isNotEmpty
                          ? 0.18
                          : 0.65,
                    ),
                  ),
                ),
                Column(
                  children: [
                    _buildTransportNoticeBanner(),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentWidth),
                          child: ValueListenableBuilder(
                            valueListenable: MessageStore.messagesNotifier,
                            builder: (context, _, __) {
                              final messages = MessageStore.getMessagesForChat(
                                widget.chatId,
                              );
                              _logRenderedMessages(messages);
                              _handleStickyScroll(messages);
                              _pruneMessageRowKeys(messages);
                              _scheduleVisibleReadReceiptSweep();

                              if (messages.isEmpty) {
                                return const Center(
                                  child: Text('No messages yet'),
                                );
                              }

                              return ListView.builder(
                                controller: _scrollController,
                                padding: messagePadding,
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  return _buildMessageRow(
                                    context,
                                    message,
                                    contentWidth,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentWidth),
                          child: Padding(
                            padding: composerPadding,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_replyingToMessage != null) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.fromLTRB(
                                      11,
                                      8,
                                      8,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Replying to ${_senderLabelForId(_replyingToMessage!.senderId)}',
                                                style: TextStyle(
                                                  color: _pink,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12.1,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _messagePreviewText(
                                                  _replyingToMessage!,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Cancel reply',
                                          onPressed: _clearReplyDraft,
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            color: Colors.white70,
                                          ),
                                          iconSize: 17,
                                          splashRadius: 16,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                width: 30,
                                                height: 30,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                Row(
                                  children: [
                                    if (_isRecordingVoice) ...[
                                      IconButton(
                                        tooltip: 'Cancel recording',
                                        onPressed: _cancelVoiceRecording,
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 34,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.18,
                                              ),
                                            ),
                                            color: Colors.black.withValues(
                                              alpha: 0.15,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFFFF4D6D),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Recording ${_formatDurationSeconds(_recordingVoiceSeconds)}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        height: 34,
                                        child: ElevatedButton.icon(
                                          onPressed: _stopAndSendVoiceNote,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _pink,
                                            foregroundColor: Colors.white,
                                            shape: const StadiumBorder(),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                            ),
                                          ),
                                          icon: const Icon(Icons.stop_rounded),
                                          label: const Text('Send'),
                                        ),
                                      ),
                                    ] else if (_pendingVoiceDraftPath !=
                                        null) ...[
                                      IconButton(
                                        tooltip: 'Discard voice note',
                                        onPressed: _discardPendingVoiceDraft,
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 34,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.18,
                                              ),
                                            ),
                                            color: Colors.black.withValues(
                                              alpha: 0.15,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.mic_rounded,
                                                size: 17,
                                                color: Colors.white70,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Voice note ready'
                                                '${_pendingVoiceDraftDurationMs == null ? '' : ' • ${_formatDurationMs(_pendingVoiceDraftDurationMs)}'}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.2,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        height: 34,
                                        child: ElevatedButton(
                                          onPressed: _sendPendingVoiceDraft,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _pink,
                                            foregroundColor: Colors.white,
                                            shape: const StadiumBorder(),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                          ),
                                          child: const Text('Send'),
                                        ),
                                      ),
                                    ] else ...[
                                      IconButton(
                                        tooltip: 'Emojis & stickers',
                                        onPressed: _openStickerSheet,
                                        icon: const Icon(
                                          Icons.emoji_emotions_outlined,
                                        ),
                                        color: _textSoft,
                                        iconSize: 18,
                                        splashRadius: 14,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 28,
                                              height: 28,
                                            ),
                                        visualDensity: const VisualDensity(
                                          horizontal: -2,
                                          vertical: -2,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'GIFs',
                                        onPressed: _openGifPicker,
                                        icon: const Icon(
                                          Icons.gif_box_outlined,
                                        ),
                                        color: _textSoft,
                                        iconSize: 18,
                                        splashRadius: 14,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 28,
                                              height: 28,
                                            ),
                                        visualDensity: const VisualDensity(
                                          horizontal: -2,
                                          vertical: -2,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Attach media',
                                        onPressed: _openAttachmentPicker,
                                        icon: const Icon(
                                          Icons.attach_file_rounded,
                                        ),
                                        color: _textSoft,
                                        iconSize: 18,
                                        splashRadius: 14,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 28,
                                              height: 28,
                                            ),
                                        visualDensity: const VisualDensity(
                                          horizontal: -2,
                                          vertical: -2,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        child: TextField(
                                          controller: _controller,
                                          focusNode: _composerFocusNode,
                                          textInputAction: TextInputAction.send,
                                          onSubmitted: (_) => _send(),
                                          style: TextStyle(
                                            color: _text,
                                            fontSize: 13.2,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          cursorColor: _pink,
                                          decoration: InputDecoration(
                                            hintText: 'Message',
                                            hintStyle: TextStyle(
                                              color: _textSoft.withValues(
                                                alpha: 0.85,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 3,
                                                ),
                                            filled: true,
                                            fillColor: Colors.black.withValues(
                                              alpha: 0.12,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              borderSide: BorderSide(
                                                color: _textSoft.withValues(
                                                  alpha: 0.28,
                                                ),
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              borderSide: BorderSide(
                                                color: _textSoft.withValues(
                                                  alpha: 0.28,
                                                ),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              borderSide: BorderSide(
                                                color: _pink.withValues(
                                                  alpha: 0.74,
                                                ),
                                                width: 1.1,
                                              ),
                                            ),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: _controller,
                                        builder: (context, value, _) {
                                          final hasText = value.text
                                              .trim()
                                              .isNotEmpty;
                                          if (!hasText) {
                                            return IconButton(
                                              tooltip: 'Voice note',
                                              onPressed: _startVoiceRecording,
                                              icon: const Icon(
                                                Icons.mic_none_rounded,
                                              ),
                                              iconSize: 18,
                                              splashRadius: 14,
                                              constraints:
                                                  const BoxConstraints.tightFor(
                                                    width: 28,
                                                    height: 28,
                                                  ),
                                              visualDensity:
                                                  const VisualDensity(
                                                    horizontal: -2,
                                                    vertical: -2,
                                                  ),
                                            );
                                          }
                                          return SizedBox(
                                            height: 32,
                                            child: ElevatedButton(
                                              onPressed: _send,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _pink,
                                                foregroundColor: Colors.white,
                                                shape: const StadiumBorder(),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                textStyle: const TextStyle(
                                                  fontSize: 12.2,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              child: const Text('Send'),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        VaultThemeStore.themeNotifier,
        DateTimeFormatStore.formatNotifier,
      ]),
      builder: (context, _) => OrientationLockScope(
        orientations: OrientationLock.chatAndMedia,
        child: widget.embedded
            ? DecoratedBox(
                decoration: BoxDecoration(color: _screenBg),
                child: Column(
                  children: [
                    _buildEmbeddedHeader(context),
                    Expanded(child: _buildThreadBody(context)),
                  ],
                ),
              )
            : Scaffold(
                backgroundColor: _screenBg,
                appBar: _buildThreadAppBar(context),
                body: _buildThreadBody(context),
              ),
      ),
    );
  }
}

class _ReactionGroup {
  final String emoji;
  final int count;
  final bool mine;

  const _ReactionGroup({
    required this.emoji,
    required this.count,
    required this.mine,
  });
}

class _VoiceRecordFormat {
  final AudioEncoder encoder;
  final int bitRate;
  final int sampleRate;
  final String mime;

  const _VoiceRecordFormat({
    required this.encoder,
    required this.bitRate,
    required this.sampleRate,
    required this.mime,
  });
}

class _AttachmentPreviewScreen extends StatelessWidget {
  final ChatMessage message;

  const _AttachmentPreviewScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    final mime = (message.attachmentMime ?? '').trim();
    final name = (message.attachmentName ?? 'Attachment').trim();
    final path = (message.attachmentPath ?? '').trim();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: () {
            if (path.isEmpty) {
              return const Text(
                'Attachment unavailable.',
                style: TextStyle(color: Colors.white70),
              );
            }
            if (mime.startsWith('image/')) {
              return FutureBuilder<Uint8List?>(
                future: MediaStorage.readDecryptedBytes(
                  path,
                  attachmentId: message.attachmentId ?? message.id,
                ).timeout(const Duration(seconds: 12)).catchError((_) => null),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const CircularProgressIndicator();
                  }
                  if (data == null || data.isEmpty) {
                    return const Text(
                      'Image unavailable.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    );
                  }
                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.memory(data, fit: BoxFit.contain),
                    ),
                  );
                },
              );
            }
            if (mime.startsWith('video/')) {
              return _VideoAttachmentPlayer(message: message);
            }
            return const Text(
              'Preview not available for this file type.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            );
          }(),
        ),
      ),
    );
  }
}

class _VideoAttachmentPlayer extends StatefulWidget {
  final ChatMessage message;

  const _VideoAttachmentPlayer({required this.message});

  @override
  State<_VideoAttachmentPlayer> createState() => _VideoAttachmentPlayerState();
}

class _VideoAttachmentPlayerState extends State<_VideoAttachmentPlayer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final message = widget.message;
    final encryptedPath = (message.attachmentPath ?? '').trim();
    if (encryptedPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Video unavailable.';
      });
      return;
    }

    final ext = _attachmentExtensionFor(
      name: (message.attachmentName ?? '').trim(),
      mime: (message.attachmentMime ?? '').trim(),
    );
    final previewPath = await MediaStorage.materializeDecryptedTempFile(
      encryptedPath: encryptedPath,
      id: message.attachmentId ?? message.id,
      extension: ext,
      attachmentId: message.attachmentId ?? message.id,
    );
    if (previewPath == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not prepare this video.';
      });
      return;
    }

    final controller = VideoPlayerController.file(File(previewPath));
    try {
      await controller.initialize();
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This video could not be played.';
      });
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_loading) {
      return const CircularProgressIndicator();
    }
    if (_error != null || controller == null) {
      return Text(
        _error ?? 'This video could not be played.',
        style: const TextStyle(color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final aspectRatio = value.isInitialized && value.aspectRatio > 0
              ? value.aspectRatio
              : (16 / 9);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: const Color(0xFF111118),
                            child: GestureDetector(
                              onTap: _togglePlayback,
                              child: VideoPlayer(controller),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 160),
                                opacity: value.isPlaying ? 0 : 1,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  child: const Center(
                                    child: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Colors.white,
                                      size: 62,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                padding: EdgeInsets.zero,
                colors: VideoProgressColors(
                  playedColor: const Color(0xFFFF2DAA),
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_formatMediaDuration(value.position)} / ${_formatMediaDuration(value.duration)}',
                      style: const TextStyle(color: Colors.white70),
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

String _attachmentExtensionFor({required String name, required String mime}) {
  final trimmedName = name.trim();
  final dot = trimmedName.lastIndexOf('.');
  if (dot > -1 && dot < trimmedName.length - 1) {
    return trimmedName.substring(dot + 1).toLowerCase();
  }
  if (mime == 'video/mp4') return 'mp4';
  if (mime == 'video/quicktime') return 'mov';
  if (mime == 'video/x-matroska') return 'mkv';
  if (mime == 'video/webm') return 'webm';
  if (mime == 'image/png') return 'png';
  if (mime == 'image/webp') return 'webp';
  if (mime == 'image/gif') return 'gif';
  if (mime == 'image/jpeg') return 'jpg';
  return 'bin';
}

String _formatMediaDuration(Duration? duration) {
  if (duration == null) return '0:00';
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

int _emojiOnlyClusterCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;

  var count = 0;
  for (final cluster in trimmed.characters) {
    if (cluster.trim().isEmpty) continue;
    if (emoji.Emojis.getOneOrNull(cluster) == null) return 0;
    count += 1;
  }
  return count == 0 ? 0 : count;
}

double? _emojiOnlyFontSizeForCount(int count, TextScaler scaler) {
  final base = switch (count) {
    1 => 56.0,
    2 => 44.0,
    3 => 36.0,
    _ => null,
  };
  if (base == null) return null;
  return scaler.scale(base);
}
