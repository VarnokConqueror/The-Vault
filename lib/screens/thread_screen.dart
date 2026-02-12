import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:lottie/lottie.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../state/message_store.dart';
import '../state/identity_store.dart';
import '../state/push_store.dart';
import '../state/voice_notes_store.dart';
import '../state/sticker_store.dart';
import '../state/media_policy_store.dart';
import '../state/chat_appearance_store.dart';
import '../state/contact_appearance_store.dart';
import '../state/security_store.dart';
import '../models/chat_message.dart';
import '../core/relay/relay_client.dart';
import '../core/tones/tone_storage.dart';
import '../core/voice_notes/voice_note_storage.dart';
import '../core/calls/call_service.dart';
import '../state/call_policy_store.dart';
import '../core/ui/orientation_lock.dart';
import '../core/stickers/animated_emoji.dart';
import '../core/stickers/sticker_catalog.dart';
import '../core/stickers/sticker_cache.dart';
import '../core/stickers/sticker_feature_flags.dart';
import '../core/media/media_storage.dart';
import '../core/media/attachment_assembler.dart';
import '../core/media/media_cipher.dart';

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
  static const Uuid _uuid = Uuid();
  static const int _attachmentChunkSize = 64 * 1024;

  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _voicePlayer = AudioPlayer();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;
  bool _polling = false;
  int _pollDelayMs = 2000;

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
    _configureTonePlayer();
    _configureVoicePlayer();
    _scheduleNextPoll();
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
    _controller.dispose();
    _audioPlayer.dispose();
    _voiceCompleteSub?.cancel();
    _voiceCompleteSub = null;
    _voiceStateSub?.cancel();
    _voiceStateSub = null;
    _recordingVoiceTimer?.cancel();
    _recordingVoiceTimer = null;
    try {
      unawaited(_voiceRecorder.cancel());
    } catch (_) {}
    unawaited(_voiceRecorder.dispose());
    _voicePlayer.dispose();
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
        ChatMessage? added;
        final relayType = relayMessage.type.trim().isEmpty
            ? RelayMessage.typeText
            : relayMessage.type.trim();
        if (relayType == RelayMessage.typeVoice &&
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
              chatId: relayMessage.chatId,
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
              chatId: relayMessage.chatId,
              senderId: relayMessage.senderId,
              body: relayMessage.body,
              createdAt: relayMessage.createdAt,
              id: envelope.envelopeId,
            );
          }
        } else if (relayType == RelayMessage.typeSticker) {
          added = await MessageStore.addIncomingMessage(
            chatId: relayMessage.chatId,
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
          added = await _handleIncomingAttachmentChunk(
            relayMessage,
            envelope.envelopeId,
          );
        } else {
          added = await MessageStore.addIncomingMessage(
            chatId: relayMessage.chatId,
            senderId: relayMessage.senderId,
            body: relayMessage.body,
            createdAt: relayMessage.createdAt,
            id: envelope.envelopeId,
          );
        }
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

  String _relaySignature(RelayMessage message) {
    final stamp = message.createdAt.millisecondsSinceEpoch;
    final type = message.type.trim().isEmpty
        ? RelayMessage.typeText
        : message.type.trim();
    final dur = message.voiceDurationMs ?? 0;
    final voiceLen = (message.voiceB64 ?? '').length;
    final sticker =
        '${message.stickerPackId ?? ''}|${message.stickerId ?? ''}|${message.stickerVariant ?? ''}';
    final attachment =
        '${message.attachmentId ?? ''}|${message.attachmentChunkIndex ?? -1}|${message.attachmentChunkCount ?? -1}';
    return '${message.chatId}|${message.senderId}|$stamp|$type|$dur|$voiceLen|$sticker|$attachment|${message.body}';
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
    final senderId = IdentityStore.publicId.trim().isEmpty
        ? 'local'
        : IdentityStore.publicId;

    final stored = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: 'Voice message',
      id: id.isEmpty ? null : id,
      type: ChatMessage.typeVoice,
      voicePath: cleanedPath,
      voiceMime: mime.isEmpty ? null : mime,
      voiceDurationMs: durationMs,
    );
    if (stored == null) return;

    // Voice bytes are base64 in the payload JSON, and the payload JSON itself
    // is then base64 for envelope transport.
    final voiceB64 = base64Encode(bytes);
    unawaited(
      RelayClient.sendMessage(
        RelayMessage(
          id: stored.id,
          chatId: stored.chatId,
          senderId: stored.senderId,
          senderName: IdentityStore.displayName,
          type: RelayMessage.typeVoice,
          body: stored.body,
          voiceB64: voiceB64,
          voiceMime: stored.voiceMime,
          voiceDurationMs: stored.voiceDurationMs,
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

    final senderId = IdentityStore.publicId.trim().isEmpty
        ? 'local'
        : IdentityStore.publicId;

    final stored = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: 'Voice message',
      id: id.isEmpty ? null : id,
      type: ChatMessage.typeVoice,
      voicePath: path,
      voiceMime: mime.isEmpty ? null : mime,
      voiceDurationMs: durationMs,
    );
    if (stored == null) return;

    final voiceB64 = base64Encode(bytes);
    unawaited(
      RelayClient.sendMessage(
        RelayMessage(
          id: stored.id,
          chatId: stored.chatId,
          senderId: stored.senderId,
          senderName: IdentityStore.displayName,
          type: RelayMessage.typeVoice,
          body: stored.body,
          voiceB64: voiceB64,
          voiceMime: stored.voiceMime,
          voiceDurationMs: stored.voiceDurationMs,
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isMe ? Colors.white : Colors.black).withValues(
                alpha: 0.12,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
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
    final defaultSize = isLottieLike ? 140.0 : 120.0;
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

  Widget _buildAttachmentContent(ChatMessage message) {
    final mime = (message.attachmentMime ?? '').trim();
    final name = (message.attachmentName ?? 'Attachment').trim();
    final size = message.attachmentSize ?? 0;
    final path = (message.attachmentPath ?? '').trim();
    final inline = message.attachmentInline ?? false;

    if (inline && mime.startsWith('image/') && path.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: MediaStorage.readDecryptedBytes(path),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const SizedBox(
              width: 140,
              height: 140,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              data,
              fit: BoxFit.cover,
              width: 200,
              height: 200,
            ),
          );
        },
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

  Future<void> _sendSticker(StickerAsset sticker) async {
    final senderId = IdentityStore.publicId.trim().isEmpty
        ? 'local'
        : IdentityStore.publicId;

    final message = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: sticker.name,
      type: ChatMessage.typeSticker,
      stickerPackId: sticker.packId,
      stickerId: sticker.id,
    );

    if (message == null) return;

    await StickerStore.addRecent(
      StickerRef(packId: sticker.packId, stickerId: sticker.id),
    );

    RelayClient.sendMessage(
      RelayMessage(
        id: message.id,
        chatId: message.chatId,
        senderId: message.senderId,
        senderName: IdentityStore.displayName,
        body: message.body,
        type: RelayMessage.typeSticker,
        stickerPackId: sticker.packId,
        stickerId: sticker.id,
        stickerVariant: message.stickerVariant,
        createdAt: message.createdAt,
      ),
    );

    if (!mounted) return;
    setState(() {});
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Future<ChatMessage?> _handleIncomingAttachmentChunk(
    RelayMessage relayMessage,
    String envelopeId,
  ) async {
    final attachmentId = (relayMessage.attachmentId ?? '').trim();
    final chunkB64 = (relayMessage.attachmentChunkB64 ?? '').trim();
    final chunkIndex = relayMessage.attachmentChunkIndex ?? -1;
    final chunkCount = relayMessage.attachmentChunkCount ?? -1;
    if (attachmentId.isEmpty ||
        chunkB64.isEmpty ||
        chunkIndex < 0 ||
        chunkCount <= 0) {
      return null;
    }

    Uint8List chunkBytes;
    try {
      chunkBytes = base64Decode(chunkB64);
    } catch (_) {
      return null;
    }

    await AttachmentAssembler.storeChunk(
      attachmentId: attachmentId,
      index: chunkIndex,
      bytes: chunkBytes,
    );

    final ready = await AttachmentAssembler.hasAllChunks(
      attachmentId: attachmentId,
      totalChunks: chunkCount,
    );
    if (!ready) return null;

    final assembled = await AttachmentAssembler.assemble(
      attachmentId: attachmentId,
      totalChunks: chunkCount,
    );
    if (assembled == null || assembled.isEmpty) return null;

    final path = await MediaStorage.storeEncryptedBytesRaw(
      id: attachmentId,
      encryptedBytes: assembled,
    );
    await AttachmentAssembler.cleanup(
      attachmentId: attachmentId,
      totalChunks: chunkCount,
    );

    return MessageStore.addIncomingMessage(
      chatId: relayMessage.chatId,
      senderId: relayMessage.senderId,
      body: relayMessage.body,
      createdAt: relayMessage.createdAt,
      id: envelopeId,
      type: ChatMessage.typeAttachment,
      attachmentId: attachmentId,
      attachmentName: relayMessage.attachmentName,
      attachmentMime: relayMessage.attachmentMime,
      attachmentSize: relayMessage.attachmentSize,
      attachmentPath: path,
      attachmentInline: relayMessage.attachmentInline ?? true,
    );
  }

  Future<void> _openAttachmentPicker() async {
    final result = await SecurityStore.runWithAutoLockSuppressed(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'mp4',
          'mov',
          'mkv',
          'webm',
        ],
      ),
    );
    final file = result?.files.single;
    final path = file?.path;
    if (path == null || path.trim().isEmpty) return;

    final options = await _showAttachmentOptions();
    if (options == null) return;

    await _sendAttachment(path.trim(), options);
  }

  Future<MediaSendPolicy?> _showAttachmentOptions() async {
    final base = MediaPolicyStore.policy;
    return showModalBottomSheet<MediaSendPolicy>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A0024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        MediaQualityPreset quality = base.quality;
        bool strip = base.stripMetadata;
        bool wifiOnly = base.wifiOnly;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Attachment Options',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Quality',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
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
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
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
                              await MediaPolicyStore.setQuality(quality);
                              await MediaPolicyStore.setStripMetadata(strip);
                              await MediaPolicyStore.setWifiOnly(wifiOnly);
                              if (sheetContext.mounted) {
                                Navigator.pop(
                                  sheetContext,
                                  MediaSendPolicy(
                                    quality: quality,
                                    stripMetadata: strip,
                                    wifiOnly: wifiOnly,
                                  ),
                                );
                              }
                            },
                            child: const Text('Send'),
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

    final inline = _isInlineMedia(mime);

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return;
    }

    Uint8List processed = bytes;
    if (policy.stripMetadata || policy.quality != MediaQualityPreset.original) {
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

    final senderId = IdentityStore.publicId.trim().isEmpty
        ? 'local'
        : IdentityStore.publicId;
    final attachmentId = _uuid.v4();
    final encryptedPath = await MediaStorage.storeEncryptedBytes(
      id: attachmentId,
      bytes: processed,
    );

    final message = await MessageStore.addMessage(
      chatId: widget.chatId,
      senderId: senderId,
      body: 'Attachment: $name',
      type: ChatMessage.typeAttachment,
      attachmentId: attachmentId,
      attachmentName: name,
      attachmentMime: mime,
      attachmentSize: processed.length,
      attachmentPath: encryptedPath,
      attachmentInline: inline,
    );
    if (message == null) return;

    await _sendAttachmentChunks(
      attachmentId: attachmentId,
      name: name,
      mime: mime,
      inline: inline,
      bytes: processed,
    );

    if (!mounted) return;
    setState(() {});
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: false);
  }

  Future<void> _sendAttachmentChunks({
    required String attachmentId,
    required String name,
    required String mime,
    required bool inline,
    required Uint8List bytes,
  }) async {
    final encrypted = MediaCipher.encrypt(bytes);
    final totalChunks = (encrypted.length / _attachmentChunkSize).ceil().clamp(
      1,
      999999,
    );

    for (var i = 0; i < totalChunks; i++) {
      final start = i * _attachmentChunkSize;
      final end = (start + _attachmentChunkSize).clamp(0, encrypted.length);
      final chunk = encrypted.sublist(start, end);
      final chunkB64 = base64Encode(chunk);
      RelayClient.sendMessage(
        RelayMessage(
          id: '${attachmentId}_$i',
          chatId: widget.chatId,
          senderId: IdentityStore.publicId.trim(),
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
          createdAt: DateTime.now(),
        ),
      );
    }
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

  Future<void> _openStickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A0024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return DefaultTabController(
          length: 3,
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.55,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 10),
                const TabBar(
                  tabs: [
                    Tab(text: 'Recents'),
                    Tab(text: 'Favorites'),
                    Tab(text: 'Packs'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _StickerGridTab(
                        title: 'Recent Stickers',
                        source: StickerStore.recentsNotifier,
                        onTapSticker: (sticker) async {
                          await _sendSticker(sticker);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        onLongPressSticker: _showStickerActions,
                      ),
                      _StickerGridTab(
                        title: 'Favorite Stickers',
                        source: StickerStore.favoritesNotifier,
                        onTapSticker: (sticker) async {
                          await _sendSticker(sticker);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        onLongPressSticker: _showStickerActions,
                      ),
                      _StickerPacksTab(
                        onTapSticker: (sticker) async {
                          await _sendSticker(sticker);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        onLongPressSticker: _showStickerActions,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    _scheduleScrollToBottom(jump: false, onlyIfNearBottom: true);
  }

  @override
  Widget build(BuildContext context) {
    return OrientationLockScope(
      orientations: OrientationLock.chatAndMedia,
      child: Scaffold(
        backgroundColor: _screenBg,
        appBar: AppBar(
          title: Text(widget.chatTitle),
          actions: [
            if ((widget.contactId ?? '').trim().isNotEmpty)
              AnimatedBuilder(
                animation: Listenable.merge([
                  CallPolicyStore.modeNotifier,
                  CallPolicyStore.neverAllowNotifier,
                ]),
                builder: (context, _) {
                  final mode = CallPolicyStore.mode;
                  final contactId = (widget.contactId ?? '').trim();
                  final blocked = CallPolicyStore.neverAllow.contains(
                    contactId,
                  );
                  final disabled =
                      mode == WhoCanCallMode.noPhoneCalls || blocked;
                  return IconButton(
                    tooltip: disabled ? 'Calls disabled' : 'Call',
                    icon: Icon(
                      Icons.call,
                      color: disabled ? Colors.white38 : null,
                    ),
                    onPressed: disabled
                        ? null
                        : () => CallService.startOutgoingCall(
                            context: context,
                            mailboxId: widget.chatId,
                            peerId: contactId,
                            peerName: widget.chatTitle,
                          ),
                  );
                },
              ),
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
                              final isSticker = message.isSticker;

                              if (isSticker) {
                                final screenWidth = MediaQuery.of(
                                  context,
                                ).size.width;
                                final minWidth = screenWidth * 0.45;
                                final maxWidth = screenWidth * 0.65;
                                final stickerWidth = (screenWidth * 0.60).clamp(
                                  minWidth,
                                  maxWidth,
                                );
                                final stickerWidget =
                                    TweenAnimationBuilder<double>(
                                      key: ValueKey('bigSticker:${message.id}'),
                                      tween: Tween<double>(
                                        begin: 0.95,
                                        end: 1.0,
                                      ),
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, value, child) {
                                        return Transform.scale(
                                          scale: value,
                                          alignment: Alignment.center,
                                          child: child,
                                        );
                                      },
                                      child: RepaintBoundary(
                                        child: _buildStickerContent(
                                          message,
                                          sizeOverride: stickerWidth,
                                        ),
                                      ),
                                    );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  child: Align(
                                    alignment: isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: isMe
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        stickerWidget,
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatTime(message.createdAt),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white60,
                                                fontSize: 11,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              if (!message.isAttachment &&
                                  !message.isVoiceNote &&
                                  isSingleEmojiMessage(message.body)) {
                                final emoji = message.body.trim();
                                final normalizedEmoji = normalizeEmoji(emoji);
                                final asset =
                                    animatedEmojiAssetFor(normalizedEmoji);
                                assert(() {
                                  debugPrint(
                                    '[EmojiAnim] enabled=${StickerFeatureFlags.enableAnimEmoji} '
                                    'normalized=$normalizedEmoji asset=$asset',
                                  );
                                  return true;
                                }());
                                final screenWidth =
                                    MediaQuery.of(context).size.width;
                                const minEmojiSize = 56.0;
                                const baseEmojiSize = 64.0;
                                final maxEmojiSize = screenWidth * 0.25;
                                final safeMaxEmojiSize =
                                    maxEmojiSize < minEmojiSize
                                        ? minEmojiSize
                                        : maxEmojiSize;
                                final scaledEmojiSize =
                                    MediaQuery.textScalerOf(context).scale(
                                  baseEmojiSize,
                                );
                                final emojiSize = scaledEmojiSize.clamp(
                                  minEmojiSize,
                                  safeMaxEmojiSize,
                                );

                                final emojiWidget = RepaintBoundary(
                                  child: asset != null
                                      ? SizedBox(
                                          width: emojiSize,
                                          height: emojiSize,
                                          child: AnimatedEmoji(
                                            assetPath: asset,
                                            repeat: true,
                                          ),
                                        )
                                      : SizedBox.square(
                                          dimension: emojiSize,
                                          child: Center(
                                            child: Text(
                                              emoji,
                                              style: TextStyle(
                                                fontSize: emojiSize,
                                                height: 1.0,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                );

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Align(
                                    alignment: isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: isMe
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        emojiWidget,
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatTime(message.createdAt),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white60,
                                                fontSize: 11,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final bubbleColor = isSticker
                                  ? Colors.transparent
                                  : (isMe ? _pink : _incomingFill);
                              final bubbleBorder = isSticker
                                  ? null
                                  : isMe
                                  ? null
                                  : Border.all(color: _pink, width: 1.2);
                              final content = message.isSticker
                                  ? _buildStickerContent(message)
                                  : message.isAttachment
                                  ? _buildAttachmentContent(message)
                                  : message.isVoiceNote
                                  ? _buildVoiceNoteContent(message, isMe: isMe)
                                  : Text(
                                      message.body,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
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
                                      padding: isSticker
                                          ? const EdgeInsets.all(6)
                                          : const EdgeInsets.symmetric(
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
                                          content,
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
                            if (_isRecordingVoice) ...[
                              IconButton(
                                tooltip: 'Cancel recording',
                                onPressed: _cancelVoiceRecording,
                                icon: const Icon(Icons.close_rounded),
                              ),
                              Expanded(
                                child: Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                    color: Colors.black.withValues(alpha: 0.15),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFFF4D6D),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Recording ${_formatDurationSeconds(_recordingVoiceSeconds)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: _stopAndSendVoiceNote,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _pink,
                                    foregroundColor: Colors.white,
                                    shape: const StadiumBorder(),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                  ),
                                  icon: const Icon(Icons.stop_rounded),
                                  label: const Text('Send'),
                                ),
                              ),
                            ] else if (_pendingVoiceDraftPath != null) ...[
                              IconButton(
                                tooltip: 'Discard voice note',
                                onPressed: _discardPendingVoiceDraft,
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                              Expanded(
                                child: Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                    color: Colors.black.withValues(alpha: 0.15),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.mic_rounded,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Voice note ready'
                                        '${_pendingVoiceDraftDurationMs == null ? '' : ' • ${_formatDurationMs(_pendingVoiceDraftDurationMs)}'}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: _sendPendingVoiceDraft,
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
                            ] else ...[
                              IconButton(
                                tooltip: 'Stickers',
                                onPressed: _openStickerSheet,
                                icon: const Icon(Icons.emoji_emotions_outlined),
                              ),
                              IconButton(
                                tooltip: 'Attach media',
                                onPressed: _openAttachmentPicker,
                                icon: const Icon(Icons.attach_file_rounded),
                              ),
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
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _controller,
                                builder: (context, value, _) {
                                  final hasText = value.text.trim().isNotEmpty;
                                  if (!hasText) {
                                    return IconButton(
                                      tooltip: 'Voice note',
                                      onPressed: _startVoiceRecording,
                                      icon: const Icon(Icons.mic_none_rounded),
                                    );
                                  }
                                  return SizedBox(
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
                                  );
                                },
                              ),
                            ],
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
      ),
    );
  }
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

class _StickerGridTab extends StatelessWidget {
  final String title;
  final ValueListenable<List<StickerRef>> source;
  final Future<void> Function(StickerAsset sticker) onTapSticker;
  final Future<void> Function(StickerAsset sticker) onLongPressSticker;

  const _StickerGridTab({
    required this.title,
    required this.source,
    required this.onTapSticker,
    required this.onLongPressSticker,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<StickerRef>>(
      valueListenable: source,
      builder: (context, refs, _) {
        final stickers = <StickerAsset>[];
        for (final ref in refs) {
          final sticker = StickerCatalog.findSticker(ref.packId, ref.stickerId);
          if (sticker != null && !_isPlaceholderStickerForSheet(sticker)) {
            stickers.add(sticker);
          }
        }
        if (stickers.isEmpty) {
          return Center(
            child: Text(title, style: const TextStyle(color: Colors.white54)),
          );
        }
        return _StickerGrid(
          stickers: stickers,
          onTapSticker: onTapSticker,
          onLongPressSticker: onLongPressSticker,
        );
      },
    );
  }
}

bool _isPlaceholderStickerForSheet(StickerAsset sticker) {
  if (sticker.packId != StickerCatalog.starterPackId) return false;
  return sticker.id == 'flame' || sticker.id == 'flame_emoji_demo';
}

bool isSingleEmojiMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  final clusters = trimmed.characters;
  if (clusters.length != 1) return false;
  return _isEmojiCluster(clusters.first);
}

final RegExp _keycapEmojiRe =
    RegExp(r'^[0-9#*]\uFE0F?\u20E3$', unicode: true);
final RegExp _flagEmojiRe =
    RegExp(r'^[\u{1F1E6}-\u{1F1FF}]{2}$', unicode: true);
final RegExp _extendedPictographicRuneRe =
    RegExp(r'^\p{Extended_Pictographic}$', unicode: true);

bool _isEmojiCluster(String cluster) {
  if (_keycapEmojiRe.hasMatch(cluster)) return true;
  if (_flagEmojiRe.hasMatch(cluster)) return true;

  var hasEmojiBase = false;
  for (final rune in cluster.runes) {
    if (_extendedPictographicRuneRe.hasMatch(String.fromCharCodes([rune]))) {
      hasEmojiBase = true;
      continue;
    }

    if (_isEmojiSequenceControlRune(rune)) continue;
    return false;
  }

  return hasEmojiBase;
}

bool _isEmojiSequenceControlRune(int rune) {
  if (rune == 0x200D) return true; // ZWJ
  if (rune == 0xFE0F || rune == 0xFE0E) return true; // variation selectors
  if (rune == 0x20E3) return true; // keycap combining
  if (rune >= 0x1F3FB && rune <= 0x1F3FF) return true; // skin tone modifiers
  if (rune >= 0xE0020 && rune <= 0xE007F) return true; // tag sequence
  return false;
}

class _StickerPacksTab extends StatelessWidget {
  final Future<void> Function(StickerAsset sticker) onTapSticker;
  final Future<void> Function(StickerAsset sticker) onLongPressSticker;

  const _StickerPacksTab({
    required this.onTapSticker,
    required this.onLongPressSticker,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: StickerCatalog.packs.length,
      itemBuilder: (context, index) {
        final pack = StickerCatalog.packs[index];
        final stickers = pack.stickers
            .where((s) => !_isPlaceholderStickerForSheet(s))
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pack.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pack.description,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 10),
            _StickerGrid(
              stickers: stickers,
              onTapSticker: onTapSticker,
              onLongPressSticker: onLongPressSticker,
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _StickerGrid extends StatelessWidget {
  final List<StickerAsset> stickers;
  final Future<void> Function(StickerAsset sticker) onTapSticker;
  final Future<void> Function(StickerAsset sticker) onLongPressSticker;

  const _StickerGrid({
    required this.stickers,
    required this.onTapSticker,
    required this.onLongPressSticker,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width ~/ 90;
    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stickers.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount.clamp(3, 6),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        StickerCache.precacheSticker(context, sticker);
        return InkWell(
          onTap: () => onTapSticker(sticker),
          onLongPress: () => onLongPressSticker(sticker),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _StickerThumb(sticker: sticker),
            ),
          ),
        );
      },
    );
  }
}

class _StickerThumb extends StatelessWidget {
  final StickerAsset sticker;

  const _StickerThumb({required this.sticker});

  @override
  Widget build(BuildContext context) {
    if (sticker.type == StickerAssetType.staticImage ||
        sticker.type == StickerAssetType.animatedWebp) {
      return Image.asset(sticker.assetPath, fit: BoxFit.contain);
    }
    if (sticker.type == StickerAssetType.animatedEmoji) {
      return AnimatedEmoji(assetPath: sticker.assetPath);
    }
    return FutureBuilder<LottieComposition?>(
      future: StickerCache.loadLottie(sticker.assetPath),
      builder: (context, snapshot) {
        final comp = snapshot.data;
        if (comp == null) {
          return Lottie.asset(sticker.assetPath, fit: BoxFit.contain);
        }
        return Lottie(composition: comp, fit: BoxFit.contain, repeat: true);
      },
    );
  }
}
