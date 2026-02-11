class ChatMessage {
  static const String typeText = 'text';
  static const String typeVoice = 'voice';
  static const String typeSticker = 'sticker';
  static const String typeAttachment = 'attachment';

  final String id;
  final String chatId;
  final String senderId;
  final String type;
  final String body;
  final String? stickerPackId;
  final String? stickerId;
  final String? stickerVariant;
  final String? attachmentId;
  final String? attachmentName;
  final String? attachmentMime;
  final int? attachmentSize;
  final String? attachmentPath;
  final bool? attachmentInline;
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
    this.stickerPackId,
    this.stickerId,
    this.stickerVariant,
    this.attachmentId,
    this.attachmentName,
    this.attachmentMime,
    this.attachmentSize,
    this.attachmentPath,
    this.attachmentInline,
    this.voicePath,
    this.voiceMime,
    this.voiceDurationMs,
    required this.createdAt,
  });

  bool get isVoiceNote =>
      type == typeVoice && (voicePath ?? '').trim().isNotEmpty;

  bool get isSticker =>
      type == typeSticker &&
      (stickerPackId ?? '').trim().isNotEmpty &&
      (stickerId ?? '').trim().isNotEmpty;

  bool get isAttachment =>
      type == typeAttachment && (attachmentPath ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'type': type,
        'body': body,
        if (stickerPackId != null) 'stickerPackId': stickerPackId,
        if (stickerId != null) 'stickerId': stickerId,
        if (stickerVariant != null) 'stickerVariant': stickerVariant,
        if (attachmentId != null) 'attachmentId': attachmentId,
        if (attachmentName != null) 'attachmentName': attachmentName,
        if (attachmentMime != null) 'attachmentMime': attachmentMime,
        if (attachmentSize != null) 'attachmentSize': attachmentSize,
        if (attachmentPath != null) 'attachmentPath': attachmentPath,
        if (attachmentInline != null) 'attachmentInline': attachmentInline,
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

    final stickerPackId =
        (json['stickerPackId'] ?? json['sticker_pack_id'])?.toString();
    final stickerId = (json['stickerId'] ?? json['sticker_id'])?.toString();
    final stickerVariant =
        (json['stickerVariant'] ?? json['sticker_variant'])?.toString();

    final attachmentId =
        (json['attachmentId'] ?? json['attachment_id'])?.toString();
    final attachmentName =
        (json['attachmentName'] ?? json['attachment_name'])?.toString();
    final attachmentMime =
        (json['attachmentMime'] ?? json['attachment_mime'])?.toString();
    int? attachmentSize;
    final attachmentSizeRaw =
        json['attachmentSize'] ?? json['attachment_size'];
    if (attachmentSizeRaw is int) {
      attachmentSize = attachmentSizeRaw;
    } else if (attachmentSizeRaw is double) {
      attachmentSize = attachmentSizeRaw.toInt();
    } else if (attachmentSizeRaw is String) {
      attachmentSize = int.tryParse(attachmentSizeRaw.trim());
    }
    final attachmentPath =
        (json['attachmentPath'] ?? json['attachment_path'])?.toString();
    final attachmentInline = json['attachmentInline'] is bool
        ? json['attachmentInline'] as bool
        : (json['attachment_inline'] is bool
            ? json['attachment_inline'] as bool
            : null);

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
      stickerPackId: stickerPackId,
      stickerId: stickerId,
      stickerVariant: stickerVariant,
      attachmentId: attachmentId,
      attachmentName: attachmentName,
      attachmentMime: attachmentMime,
      attachmentSize: attachmentSize,
      attachmentPath: attachmentPath,
      attachmentInline: attachmentInline,
      voicePath: voicePath,
      voiceMime: voiceMime,
      voiceDurationMs: voiceDurationMs,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
