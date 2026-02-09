class ChatMessage {
  static const String typeText = 'text';
  static const String typeVoice = 'voice';

  final String id;
  final String chatId;
  final String senderId;
  final String type;
  final String body;
  final String? voicePath;
  final String? voiceMime;
  final int? voiceDurationMs;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.type = typeText,
    required this.body,
    this.voicePath,
    this.voiceMime,
    this.voiceDurationMs,
    required this.createdAt,
  });

  bool get isVoiceNote =>
      type == typeVoice && (voicePath ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'type': type,
        'body': body,
        if (voicePath != null) 'voicePath': voicePath,
        if (voiceMime != null) 'voiceMime': voiceMime,
        if (voiceDurationMs != null) 'voiceDurationMs': voiceDurationMs,
        'createdAt': createdAt.toIso8601String(),
      };

  static ChatMessage fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? json['messageType'] ?? '').toString().trim();
    final type = rawType.isEmpty ? typeText : rawType;

    final voicePath = (json['voicePath'] ?? json['voice_path'])?.toString();
    final voiceMime = (json['voiceMime'] ?? json['voice_mime'])?.toString();

    int? voiceDurationMs;
    final durationRaw = json['voiceDurationMs'] ?? json['voice_duration_ms'];
    if (durationRaw is int) {
      voiceDurationMs = durationRaw;
    } else if (durationRaw is double) {
      voiceDurationMs = durationRaw.toInt();
    } else if (durationRaw is String) {
      voiceDurationMs = int.tryParse(durationRaw.trim());
    }

    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      chatId: (json['chatId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      type: type,
      body: (json['body'] ?? '').toString(),
      voicePath: voicePath,
      voiceMime: voiceMime,
      voiceDurationMs: voiceDurationMs,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
