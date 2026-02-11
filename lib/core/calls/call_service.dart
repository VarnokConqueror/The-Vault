import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/relay/relay_client.dart';
import '../../state/call_policy_store.dart';
import '../../state/identity_store.dart';
import '../../state/security_store.dart';
import 'call_models.dart';
import 'call_signaling.dart';
import '../ui/orientation_lock.dart';

class CallService {
  static const bool logDebug = bool.fromEnvironment(
    'CALL_LOG_DEBUG',
    defaultValue: false,
  );
  static const bool forceTurnRelay = bool.fromEnvironment(
    'CALL_FORCE_TURN_RELAY',
    defaultValue: false,
  );

  static final ValueNotifier<CallSession?> currentCallNotifier =
      ValueNotifier<CallSession?>(null);

  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _initialized = false;

  static CallSignalingClient? _signal;
  static RTCPeerConnection? _pc;
  static MediaStream? _localStream;
  static MediaStreamTrack? _localAudioTrack;

  static Timer? _callTimeoutTimer;
  static Timer? _offerResendTimer;
  static int _offerResendAttempts = 0;
  static String _callerOfferSdp = '';
  static String _callerOfferType = 'offer';
  static final List<RTCIceCandidate> _callerIceBuffer = <RTCIceCandidate>[];
  static final List<RTCIceCandidate> _pendingIce = <RTCIceCandidate>[];
  static Map<String, dynamic>? _pendingOffer;

  static bool _ringing = false;

  static const String _prefCallActive = 'cc_call_active_v1';

  static void init({required GlobalKey<NavigatorState> navigatorKey}) {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;
    SecurityStore.lockedNotifier.addListener(_handleUnlock);
  }

  static bool get hasActiveCall {
    final c = currentCallNotifier.value;
    if (c == null) return false;
    return c.phase != CallPhase.ended && c.phase != CallPhase.idle;
  }

  static Future<void> startOutgoingCall({
    required BuildContext context,
    required String mailboxId,
    required String peerId,
    required String peerName,
  }) async {
    if (hasActiveCall) return;
    if (!IdentityStore.usernameCustom) return;
    if (CallPolicyStore.mode == WhoCanCallMode.noPhoneCalls) return;
    if (CallPolicyStore.neverAllow.contains(peerId.trim())) return;

    final mb = mailboxId.trim();
    if (mb.isEmpty) return;

    final myDeviceId = IdentityStore.publicId.trim();
    if (myDeviceId.isEmpty) return;

    final callId = const Uuid().v4();
    _log('startOutgoingCall callId=$callId mailbox=$mb peer=${peerId.trim()}');
    currentCallNotifier.value = CallSession(
      callId: callId,
      mailboxId: mb,
      peerId: peerId.trim(),
      peerName: peerName.trim().isEmpty ? 'Call' : peerName.trim(),
      direction: CallDirection.outgoing,
      phase: CallPhase.ringingOutgoing,
      muted: false,
      speakerOn: false,
      createdAt: DateTime.now(),
      connectedAt: null,
      endedReason: null,
    );

    SecurityStore.pushAutoLockSuppression();
    unawaited(_setCallActive(true));

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _OutgoingCallScreen(
          callId: callId,
          mailboxId: mb,
          peerName: peerName,
          peerId: peerId,
        ),
      ),
    );

    try {
      await _connectSignaling(mailboxId: mb, deviceId: myDeviceId);
      _log('ws connected');
      await _startWebRtcCaller(callId: callId, mailboxId: mb);
      _log('offer sent');

      _callTimeoutTimer?.cancel();
      _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
        final c = currentCallNotifier.value;
        if (c == null) return;
        if (c.callId != callId) return;
        if (c.phase == CallPhase.inCall) return;
        unawaited(_sendSignal(
          type: CallSignalType.timeout,
          callId: callId,
          mailboxId: mb,
        ));
        unawaited(_endCall(reason: 'timeout'));
      });
    } catch (e) {
      _log('startOutgoingCall failed: $e');
      await _endCall(reason: 'failed');
    }
  }

  static Future<bool> handleIncomingCallPush({
    required String callId,
    required String mailboxId,
    required String callerId,
    required String callerName,
    bool showUiImmediately = true,
  }) async {
    final id = callId.trim();
    final mb = mailboxId.trim();
    final fromId = callerId.trim();
    final fromName = callerName.trim().isEmpty ? 'Unknown' : callerName.trim();
    if (id.isEmpty || mb.isEmpty || fromId.isEmpty) return false;

    if (!IdentityStore.usernameCustom) {
      await _sendOneShotSignal(
        mailboxId: mb,
        type: CallSignalType.reject,
        callId: id,
      );
      return false;
    }

    await CallPolicyStore.rememberRecentCaller(fromId);

    // Busy handling: if we're already in a call, tell the caller immediately.
    if (hasActiveCall) {
      await _sendOneShotSignal(
        mailboxId: mb,
        type: CallSignalType.busy,
        callId: id,
      );
      return false;
    }

    final permitted = CallPolicyStore.isIncomingCallPermitted(callerId: fromId);
    if (!permitted) {
      await _sendOneShotSignal(
        mailboxId: mb,
        type: CallSignalType.reject,
        callId: id,
      );
      return false;
    }

    currentCallNotifier.value = CallSession(
      callId: id,
      mailboxId: mb,
      peerId: fromId,
      peerName: fromName,
      direction: CallDirection.incoming,
      phase: CallPhase.ringingIncoming,
      muted: false,
      speakerOn: false,
      createdAt: DateTime.now(),
      connectedAt: null,
      endedReason: null,
    );
    _pendingOffer = null;
    _pendingIce.clear();

    SecurityStore.pushAutoLockSuppression();
    unawaited(_setCallActive(true));

    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 45), () {
      final c = currentCallNotifier.value;
      if (c == null) return;
      if (c.callId != id) return;
      if (c.phase == CallPhase.inCall) return;
      unawaited(_endCall(reason: 'missed'));
    });

    if (!showUiImmediately) return true;
    _openIncomingCallScreen();
    return true;
  }

  static void openIncomingCallFromNotification({
    required String callId,
    required String mailboxId,
    required String callerId,
    required String callerName,
  }) {
    // We re-run the normal flow. This ensures policy/busy checks happen too.
    unawaited(
      handleIncomingCallPush(
        callId: callId,
        mailboxId: mailboxId,
        callerId: callerId,
        callerName: callerName,
        showUiImmediately: true,
      ),
    );
  }

  static Future<void> answerIncoming() async {
    final c = currentCallNotifier.value;
    if (c == null) return;
    if (c.direction != CallDirection.incoming) return;
    if (c.phase != CallPhase.ringingIncoming) return;

    currentCallNotifier.value = c.copyWith(phase: CallPhase.connecting);
    _stopRinging();

    try {
      final myDeviceId = IdentityStore.publicId.trim();
      await _connectSignaling(mailboxId: c.mailboxId, deviceId: myDeviceId);

      final offer = await _waitForOffer(c.callId);
      await _startWebRtcCalleeFromOffer(
        callId: c.callId,
        mailboxId: c.mailboxId,
        offer: offer,
      );
    } catch (e) {
      _log('answerIncoming failed: $e');
      await _endCall(reason: 'failed');
    }
  }

  static Future<void> declineIncoming() async {
    final c = currentCallNotifier.value;
    if (c == null) return;
    if (c.direction != CallDirection.incoming) return;
    if (c.phase != CallPhase.ringingIncoming &&
        c.phase != CallPhase.connecting) {
      return;
    }

    _stopRinging();
    await _sendOneShotSignal(
      mailboxId: c.mailboxId,
      type: CallSignalType.reject,
      callId: c.callId,
    );
    await _endCall(reason: 'rejected');
  }

  static Future<void> hangup() async {
    final c = currentCallNotifier.value;
    if (c == null) return;
    await _sendSignal(
      type: CallSignalType.hangup,
      callId: c.callId,
      mailboxId: c.mailboxId,
    );
    await _endCall(reason: 'hangup');
  }

  static Future<void> setMuted(bool muted) async {
    final c = currentCallNotifier.value;
    if (c == null) return;
    final track = _localAudioTrack;
    if (track != null) {
      try {
        await Helper.setMicrophoneMute(muted, track);
      } catch (_) {
        // Fallback for platforms where setMicrophoneMute isn't supported.
        try {
          track.enabled = !muted;
        } catch (_) {}
      }
    }
    currentCallNotifier.value = c.copyWith(muted: muted);
  }

  static Future<void> setSpeakerOn(bool enabled) async {
    final c = currentCallNotifier.value;
    if (c == null) return;
    try {
      await Helper.setSpeakerphoneOn(enabled);
    } catch (_) {}
    currentCallNotifier.value = c.copyWith(speakerOn: enabled);
  }

  static Future<void> _connectSignaling({
    required String mailboxId,
    required String deviceId,
  }) async {
    if (_signal != null) return;
    final signal = CallSignalingClient(mailboxId: mailboxId, deviceId: deviceId);
    signal.onEvent = _handleSignalEvent;
    signal.onError = (e) => _log('ws error: $e');
    signal.onDone = () => _log('ws done');
    await signal.connect();
    _signal = signal;
  }

  static Future<void> _sendSignal({
    required String type,
    required String callId,
    required String mailboxId,
    Map<String, dynamic>? extra,
  }) async {
    final c = currentCallNotifier.value;
    if (c == null) return;
    if (c.callId != callId) return;

    final payload = <String, dynamic>{
      'type': type,
      'callId': callId,
      'call_id': callId,
      'fromChatId': mailboxId,
      'from_chat_id': mailboxId,
      'toChatId': mailboxId,
      'to_chat_id': mailboxId,
      'senderId': IdentityStore.publicId.trim(),
      'sender_id': IdentityStore.publicId.trim(),
      'senderName': IdentityStore.displayName.trim(),
      'sender_name': IdentityStore.displayName.trim(),
      if (extra != null) ...extra,
    };
    _signal?.send(payload);
  }

  static Future<void> _sendOneShotSignal({
    required String mailboxId,
    required String type,
    required String callId,
  }) async {
    final myDeviceId = IdentityStore.publicId.trim();
    if (myDeviceId.isEmpty) return;

    final client = CallSignalingClient(mailboxId: mailboxId, deviceId: myDeviceId);
    try {
      await client.connect();
      client.send(<String, dynamic>{
        'type': type,
        'callId': callId,
        'call_id': callId,
        'fromChatId': mailboxId,
        'from_chat_id': mailboxId,
        'toChatId': mailboxId,
        'to_chat_id': mailboxId,
        'senderId': myDeviceId,
        'sender_id': myDeviceId,
        'senderName': IdentityStore.displayName.trim(),
        'sender_name': IdentityStore.displayName.trim(),
      });
    } catch (_) {
      // ignore
    } finally {
      await client.close();
    }
  }

  static Future<void> _startWebRtcCaller({
    required String callId,
    required String mailboxId,
  }) async {
    _offerResendTimer?.cancel();
    _offerResendTimer = null;
    _offerResendAttempts = 0;
    _callerOfferSdp = '';
    _callerOfferType = 'offer';
    _callerIceBuffer.clear();

    final iceServers = await RelayClient.fetchIceServers();
    final config = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      if (forceTurnRelay) 'iceTransportPolicy': 'relay',
    };

    _pc = await createPeerConnection(config);
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.trim().isEmpty) return;
      try {
        _callerIceBuffer.add(
          RTCIceCandidate(
            candidate.candidate,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
          ),
        );
        // Keep the buffer small; we only need enough to bridge late-joiners.
        if (_callerIceBuffer.length > 60) {
          _callerIceBuffer.removeRange(0, _callerIceBuffer.length - 60);
        }
      } catch (_) {}
      unawaited(_sendSignal(
        type: CallSignalType.ice,
        callId: callId,
        mailboxId: mailboxId,
        extra: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      ));
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_endCall(reason: 'failed'));
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // Give the connection a moment to recover; if it doesn't, callers can hang up.
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_endCall(reason: 'ended'));
      }
    };

    _localStream =
        await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      _localAudioTrack = audioTracks.first;
    }
    for (final t in _localStream!.getTracks()) {
      await _pc!.addTrack(t, _localStream!);
    }

    final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
    await _pc!.setLocalDescription(offer);
    final local = await _pc!.getLocalDescription();
    final sdp = (local?.sdp ?? offer.sdp ?? '');
    final sdpType = (local?.type ?? offer.type ?? 'offer').trim();
    if (sdp.trim().isEmpty) {
      throw StateError('createOffer returned empty SDP');
    }
    _callerOfferSdp = sdp;
    _callerOfferType = sdpType.isEmpty ? 'offer' : sdpType;
    _log(
      'offer local sdpLen=${_callerOfferSdp.length} type=$_callerOfferType startsV=${_callerOfferSdp.startsWith('v=')} hasAudio=${_callerOfferSdp.contains('m=audio')} cr=${_callerOfferSdp.contains('\r')} lf=${_callerOfferSdp.contains('\n')} endsLf=${_callerOfferSdp.endsWith('\n')} escLf=${_callerOfferSdp.contains('\\n')}',
    );
    await _sendSignal(
      type: CallSignalType.offer,
      callId: callId,
      mailboxId: mailboxId,
      extra: {
        'sdp': _callerOfferSdp,
        'sdpType': _callerOfferType,
      },
    );

    // If the callee isn't connected yet (push wakes them up), they might miss the
    // first offer/ICE burst. Resend briefly until we get an answer or time out.
    _startCallerResendLoop(callId: callId, mailboxId: mailboxId);
  }

  static void _startCallerResendLoop({
    required String callId,
    required String mailboxId,
  }) {
    _offerResendTimer?.cancel();
    _offerResendTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      unawaited(_resendOfferAndIce(callId: callId, mailboxId: mailboxId));
    });
  }

  static Future<void> _resendOfferAndIce({
    required String callId,
    required String mailboxId,
  }) async {
    final c = currentCallNotifier.value;
    if (c == null || c.callId != callId || c.direction != CallDirection.outgoing) {
      _offerResendTimer?.cancel();
      _offerResendTimer = null;
      return;
    }

    if (c.phase == CallPhase.inCall ||
        c.phase == CallPhase.ended ||
        c.phase == CallPhase.idle) {
      _offerResendTimer?.cancel();
      _offerResendTimer = null;
      return;
    }

    _offerResendAttempts += 1;
    if (_offerResendAttempts > 20) {
      _offerResendTimer?.cancel();
      _offerResendTimer = null;
      return;
    }

    final sdp = _callerOfferSdp;
    if (sdp.trim().isEmpty) return;

    await _sendSignal(
      type: CallSignalType.offer,
      callId: callId,
      mailboxId: mailboxId,
      extra: {
        'sdp': sdp,
        'sdpType': _callerOfferType.trim().isEmpty ? 'offer' : _callerOfferType,
      },
    );

    // Re-send buffered candidates to help late joiners connect reliably.
    for (final cand in List<RTCIceCandidate>.from(_callerIceBuffer)) {
      final cstr = (cand.candidate ?? '').trim();
      if (cstr.isEmpty) continue;
      await _sendSignal(
        type: CallSignalType.ice,
        callId: callId,
        mailboxId: mailboxId,
        extra: {
          'candidate': cstr,
          'sdpMid': cand.sdpMid,
          'sdpMLineIndex': cand.sdpMLineIndex,
        },
      );
    }
  }

  static Future<void> _startWebRtcCalleeFromOffer({
    required String callId,
    required String mailboxId,
    required Map<String, dynamic> offer,
  }) async {
    final iceServers = await RelayClient.fetchIceServers();
    final config = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      if (forceTurnRelay) 'iceTransportPolicy': 'relay',
    };

    _pc = await createPeerConnection(config);
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.trim().isEmpty) return;
      unawaited(_sendSignal(
        type: CallSignalType.ice,
        callId: callId,
        mailboxId: mailboxId,
        extra: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      ));
    };
    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_endCall(reason: 'failed'));
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_endCall(reason: 'ended'));
      }
    };

    _localStream =
        await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      _localAudioTrack = audioTracks.first;
    }
    for (final t in _localStream!.getTracks()) {
      await _pc!.addTrack(t, _localStream!);
    }

    final remoteSdp = (offer['sdp'] ?? offer['offerSdp'] ?? '').toString();
    final remoteType =
        (offer['sdpType'] ?? offer['type'] ?? 'offer').toString().trim();
    if (remoteSdp.trim().isEmpty) {
      throw StateError('received offer missing SDP');
    }
    _log(
      'offer remote sdpLen=${remoteSdp.length} type=${remoteType.isEmpty ? 'offer' : remoteType} startsV=${remoteSdp.startsWith('v=')} hasAudio=${remoteSdp.contains('m=audio')} cr=${remoteSdp.contains('\r')} lf=${remoteSdp.contains('\n')} endsLf=${remoteSdp.endsWith('\n')} escLf=${remoteSdp.contains('\\n')}',
    );
    await _pc!.setRemoteDescription(
      RTCSessionDescription(remoteSdp, remoteType.isEmpty ? 'offer' : remoteType),
    );

    // Apply any ICE candidates we queued while waiting for the offer.
    for (final c in _pendingIce) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingIce.clear();

    final answer = await _pc!.createAnswer({'offerToReceiveAudio': 1});
    await _pc!.setLocalDescription(answer);
    final local = await _pc!.getLocalDescription();
    final answerSdp = (local?.sdp ?? answer.sdp ?? '');
    final answerType = (local?.type ?? answer.type ?? 'answer').trim();
    if (answerSdp.trim().isEmpty) {
      throw StateError('createAnswer returned empty SDP');
    }
    await _sendSignal(
      type: CallSignalType.answer,
      callId: callId,
      mailboxId: mailboxId,
      extra: {
        'sdp': answerSdp,
        'sdpType': answerType.isEmpty ? 'answer' : answerType,
      },
    );
  }

  static void _handleSignalEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? '').toString().trim();
    if (type.isEmpty) return;

    final callId = (event['callId'] ?? event['call_id'] ?? '').toString().trim();
    if (callId.isEmpty) return;

    final c = currentCallNotifier.value;
    if (c == null) return;
    if (c.callId != callId) return;

    final senderId =
        (event['senderId'] ?? event['sender_id'] ?? '').toString().trim();
    if (senderId.isNotEmpty && senderId == IdentityStore.publicId.trim()) {
      // Don't process our own echo.
      return;
    }

    if (type != CallSignalType.ice) {
      _log('signal type=$type from=${senderId.isEmpty ? "unknown" : senderId}');
    }

    switch (type) {
      case CallSignalType.offer:
        _pendingOffer = event;
        if (c.direction == CallDirection.incoming &&
            c.phase == CallPhase.ringingIncoming) {
          _openIncomingCallScreen();
        }
        return;
      case CallSignalType.answer:
        final sdp = (event['sdp'] ?? '').toString();
        final sdpType = (event['sdpType'] ?? 'answer').toString();
        final pc = _pc;
        if (pc == null) return;
        unawaited(pc.setRemoteDescription(RTCSessionDescription(sdp, sdpType)));
        _markConnected();
        return;
      case CallSignalType.ice:
        final cand = (event['candidate'] ?? '').toString();
        final sdpMid = (event['sdpMid'] ?? event['sdp_mid'] ?? '').toString();
        final idxRaw = event['sdpMLineIndex'] ?? event['sdp_mline_index'];
        final sdpMLineIndex = idxRaw is int ? idxRaw : int.tryParse('$idxRaw');
        if (cand.trim().isEmpty) return;
        final candidate = RTCIceCandidate(cand, sdpMid, sdpMLineIndex);
        final pc = _pc;
        if (pc == null) {
          _pendingIce.add(candidate);
          return;
        }
        unawaited(pc.addCandidate(candidate));
        return;
      case CallSignalType.hangup:
        unawaited(_endCall(reason: 'hangup'));
        return;
      case CallSignalType.reject:
        unawaited(_endCall(reason: 'rejected'));
        return;
      case CallSignalType.busy:
        unawaited(_endCall(reason: 'busy'));
        return;
      case CallSignalType.timeout:
        unawaited(_endCall(reason: 'timeout'));
        return;
    }
  }

  static Future<Map<String, dynamic>> _waitForOffer(String callId) async {
    final existing = _pendingOffer;
    if (existing != null) return existing;

    final completer = Completer<Map<String, dynamic>>();
    late void Function(Map<String, dynamic> event) prev;
    prev = _handleSignalEvent;

    // We don't want to duplicate parsing; we just watch for offer arrival.
    void watcher(Map<String, dynamic> event) {
      prev(event);
      final type = (event['type'] ?? '').toString().trim();
      final id = (event['callId'] ?? event['call_id'] ?? '').toString().trim();
      if (!completer.isCompleted &&
          type == CallSignalType.offer &&
          id == callId) {
        completer.complete(event);
      }
    }

    final signal = _signal;
    if (signal != null) {
      signal.onEvent = watcher;
    }

    try {
      return await completer.future.timeout(const Duration(seconds: 12));
    } finally {
      // Restore main handler.
      if (signal != null) {
        signal.onEvent = _handleSignalEvent;
      }
    }
  }

  static void _markConnected() {
    final c = currentCallNotifier.value;
    if (c == null) return;
    if (c.phase == CallPhase.inCall) return;

    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _offerResendTimer?.cancel();
    _offerResendTimer = null;

    currentCallNotifier.value = c.copyWith(
      phase: CallPhase.inCall,
      connectedAt: DateTime.now(),
    );
  }

  static Future<void> _endCall({required String reason}) async {
    _log('endCall reason=$reason');
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _offerResendTimer?.cancel();
    _offerResendTimer = null;
    _offerResendAttempts = 0;
    _callerOfferSdp = '';
    _callerOfferType = 'offer';
    _callerIceBuffer.clear();
    _stopRinging();

    try {
      await _signal?.close();
    } catch (_) {}
    _signal = null;

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        try {
          await t.stop();
        } catch (_) {}
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _localAudioTrack = null;

    _pendingOffer = null;
    _pendingIce.clear();

    final c = currentCallNotifier.value;
    if (c != null) {
      currentCallNotifier.value =
          c.copyWith(phase: CallPhase.ended, endedReason: reason);
    }

    // Give the UI a beat to observe ended state.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    currentCallNotifier.value = null;

    unawaited(_setCallActive(false));
    SecurityStore.popAutoLockSuppression();
  }

  static Future<void> _setCallActive(bool active) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefCallActive, active);
    } catch (_) {}
  }

  static void _openIncomingCallScreen() {
    if (SecurityStore.isLocked) {
      // Wait for unlock; we still keep the call pending.
      return;
    }
    final nav = _navigatorKey?.currentState;
    final c = currentCallNotifier.value;
    if (nav == null || c == null) return;

    nav.push(
      MaterialPageRoute(
        builder: (_) => _IncomingCallScreen(
          callId: c.callId,
          mailboxId: c.mailboxId,
          callerId: c.peerId,
          callerName: c.peerName,
        ),
      ),
    );
    _startRinging();
  }

  static void _handleUnlock() {
    if (SecurityStore.isLocked) return;
    final c = currentCallNotifier.value;
    if (c == null) return;
    if (c.direction == CallDirection.incoming &&
        c.phase == CallPhase.ringingIncoming) {
      _openIncomingCallScreen();
    }
  }

  static void _startRinging() {
    if (_ringing) return;
    _ringing = true;
    try {
      FlutterRingtonePlayer().playRingtone(looping: true);
    } catch (_) {}
  }

  static void _stopRinging() {
    if (!_ringing) return;
    _ringing = false;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }

  static void _log(String message) {
    if (!logDebug) return;
    debugPrint('[Call] $message');
  }
}

class _OutgoingCallScreen extends StatefulWidget {
  const _OutgoingCallScreen({
    required this.callId,
    required this.mailboxId,
    required this.peerName,
    required this.peerId,
  });

  final String callId;
  final String mailboxId;
  final String peerName;
  final String peerId;

  @override
  State<_OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<_OutgoingCallScreen> {
  @override
  Widget build(BuildContext context) {
    return OrientationLockScope(
      orientations: OrientationLock.portraitOnly,
      child: ValueListenableBuilder<CallSession?>(
        valueListenable: CallService.currentCallNotifier,
        builder: (context, call, _) {
          if (call == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pop();
              }
            });
            return const SizedBox.shrink();
          }

          if (call.phase == CallPhase.inCall) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const _InCallScreen()),
              );
            });
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('Calling'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  Text(
                    widget.peerName.trim().isEmpty ? 'Calling…' : widget.peerName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    call.phase == CallPhase.ringingOutgoing
                        ? 'Ringing…'
                        : call.phase == CallPhase.connecting
                            ? 'Connecting…'
                            : 'Calling…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: CallService.hangup,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Hang up'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD21B5B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IncomingCallScreen extends StatefulWidget {
  const _IncomingCallScreen({
    required this.callId,
    required this.mailboxId,
    required this.callerId,
    required this.callerName,
  });

  final String callId;
  final String mailboxId;
  final String callerId;
  final String callerName;

  @override
  State<_IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<_IncomingCallScreen> {
  @override
  Widget build(BuildContext context) {
    return OrientationLockScope(
      orientations: OrientationLock.portraitOnly,
      child: ValueListenableBuilder<CallSession?>(
        valueListenable: CallService.currentCallNotifier,
        builder: (context, call, _) {
          if (call == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pop();
              }
            });
            return const SizedBox.shrink();
          }

          if (call.phase == CallPhase.inCall) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const _InCallScreen()),
              );
            });
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('Incoming call'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  Text(
                    widget.callerName.trim().isEmpty
                        ? 'Incoming call'
                        : widget.callerName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    call.phase == CallPhase.connecting ? 'Connecting…' : 'Ringing…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: CallService.declineIncoming,
                          icon: const Icon(Icons.call_end),
                          label: const Text('Decline'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD21B5B),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: CallService.answerIncoming,
                          icon: const Icon(Icons.call),
                          label: const Text('Answer'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1C9B5E),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InCallScreen extends StatefulWidget {
  const _InCallScreen();

  @override
  State<_InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<_InCallScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    if (hh > 0) {
      return '${hh.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return OrientationLockScope(
      orientations: OrientationLock.portraitOnly,
      child: ValueListenableBuilder<CallSession?>(
        valueListenable: CallService.currentCallNotifier,
        builder: (context, call, _) {
          if (call == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pop();
              }
            });
            return const SizedBox.shrink();
          }

          final connectedAt = call.connectedAt ?? DateTime.now();
          final elapsed = DateTime.now().difference(connectedAt);

          return Scaffold(
            appBar: AppBar(
              title: const Text('In call'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    call.peerName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(elapsed),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => CallService.setMuted(!call.muted),
                          icon: Icon(call.muted ? Icons.mic_off : Icons.mic),
                          label: Text(call.muted ? 'Unmute' : 'Mute'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => CallService.setSpeakerOn(!call.speakerOn),
                          icon: Icon(
                            call.speakerOn
                                ? Icons.volume_up
                                : Icons.hearing_outlined,
                          ),
                          label: Text(call.speakerOn ? 'Speaker' : 'Earpiece'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: CallService.hangup,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Hang up'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD21B5B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
