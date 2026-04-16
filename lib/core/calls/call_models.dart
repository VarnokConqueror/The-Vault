enum CallDirection {
  outgoing,
  incoming,
}

enum CallPhase {
  idle,
  ringingOutgoing,
  ringingIncoming,
  connecting,
  inCall,
  ended,
}

class CallSession {
  final String callId;
  final String mailboxId;
  final String peerId;
  final String peerName;
  final CallDirection direction;
  final CallPhase phase;
  final bool muted;
  final bool speakerOn;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final String? endedReason;

  const CallSession({
    required this.callId,
    required this.mailboxId,
    required this.peerId,
    required this.peerName,
    required this.direction,
    required this.phase,
    required this.muted,
    required this.speakerOn,
    required this.createdAt,
    required this.connectedAt,
    required this.endedReason,
  });

  CallSession copyWith({
    CallPhase? phase,
    bool? muted,
    bool? speakerOn,
    DateTime? connectedAt,
    String? endedReason,
  }) {
    return CallSession(
      callId: callId,
      mailboxId: mailboxId,
      peerId: peerId,
      peerName: peerName,
      direction: direction,
      phase: phase ?? this.phase,
      muted: muted ?? this.muted,
      speakerOn: speakerOn ?? this.speakerOn,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedReason: endedReason ?? this.endedReason,
    );
  }
}

class CallSignalType {
  static const String offer = 'offer';
  static const String answer = 'answer';
  static const String ice = 'ice';
  static const String hangup = 'hangup';
  static const String busy = 'busy';
  static const String reject = 'reject';
  static const String timeout = 'timeout';
}

