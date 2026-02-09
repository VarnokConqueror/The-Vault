import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../state/message_store.dart';
import '../state/identity_store.dart';
import '../state/push_store.dart';
import '../state/voice_notes_store.dart';
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
    final type = message.type.trim().isEmpty ? ChatMessage.typeText : message.type.trim();
    final dur = message.voiceDurationMs ?? 0;
    return '${message.chatId}|${message.senderId}|$stamp|$type|$dur|${message.body}';
  }

  String _relaySignature(RelayMessage message) {
    final stamp = message.createdAt.millisecondsSinceEpoch;
    final type = message.type.trim().isEmpty ? RelayMessage.typeText : message.type.trim();
    final dur = message.voiceDurationMs ?? 0;
    final voiceLen = (message.voiceB64 ?? '').length;
    return '${message.chatId}|${message.senderId}|$stamp|$type|$dur|$voiceLen|${message.body}';
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
      final trimmed = toneUri.trim();
      final parsed = Uri.tryParse(trimmed);
      if (parsed != null && parsed.scheme.isNotEmpty && parsed.scheme != 'file') {
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
      final supported = await _voiceRecorder.isEncoderSupported(AudioEncoder.opus);
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
      final supported = await _voiceRecorder.isEncoderSupported(AudioEncoder.amrNb);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice recording failed: $e')),
      );
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
  static const int _voiceNoteAutoStopThresholdBytes = _maxVoiceNoteBytes - (8 * 1024);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice playback failed: $e')),
      );
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
              color: (isMe ? Colors.white : Colors.black).withValues(alpha: 0.12),
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
                final blocked = CallPolicyStore.neverAllow.contains(contactId);
                final disabled = mode == WhoCanCallMode.noPhoneCalls || blocked;
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
                            final bubbleColor = isMe ? _pink : _incomingFill;
                            final bubbleBorder = isMe
                                ? null
                                : Border.all(color: _pink, width: 1.2);
                            final content = message.isVoiceNote
                                ? _buildVoiceNoteContent(
                                    message,
                                    isMe: isMe,
                                  )
                                : Text(
                                    message.body,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  );
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
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
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
                                      style: const TextStyle(color: Colors.white),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
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
                                      style: const TextStyle(color: Colors.white),
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
                              tooltip: 'Voice note',
                              onPressed: _startVoiceRecording,
                              icon: const Icon(Icons.mic_none_rounded),
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
