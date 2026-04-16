class MessageReaction {
  final String emoji;
  final String senderId;
  final DateTime createdAt;

  const MessageReaction({
    required this.emoji,
    required this.senderId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'emoji': emoji,
    'senderId': senderId,
    'createdAt': createdAt.toIso8601String(),
  };

  static MessageReaction? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final emojiValue = (json['emoji'] ?? '').toString().trim();
    final senderId = (json['senderId'] ?? json['sender_id'] ?? '')
        .toString()
        .trim();
    if (emojiValue.isEmpty || senderId.isEmpty) {
      return null;
    }
    return MessageReaction(
      emoji: emojiValue,
      senderId: senderId,
      createdAt:
          DateTime.tryParse(
            (json['createdAt'] ?? json['created_at'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class MessageReplyPreview {
  final String messageId;
  final String senderId;
  final String type;
  final String previewText;

  const MessageReplyPreview({
    required this.messageId,
    required this.senderId,
    required this.type,
    required this.previewText,
  });

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'senderId': senderId,
    'type': type,
    'previewText': previewText,
  };

  static MessageReplyPreview? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final messageId = (json['messageId'] ?? json['message_id'] ?? '')
        .toString()
        .trim();
    final senderId = (json['senderId'] ?? json['sender_id'] ?? '')
        .toString()
        .trim();
    if (messageId.isEmpty || senderId.isEmpty) {
      return null;
    }
    final type = (json['type'] ?? ChatMessage.typeText).toString().trim();
    final previewText = (json['previewText'] ?? json['preview_text'] ?? '')
        .toString();
    return MessageReplyPreview(
      messageId: messageId,
      senderId: senderId,
      type: type.isEmpty ? ChatMessage.typeText : type,
      previewText: previewText,
    );
  }
}

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
  final MessageReplyPreview? replyTo;
  final List<MessageReaction> reactions;
  final DateTime? deliveredAt;
  final DateTime? readAt;
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
    this.replyTo,
    this.reactions = const <MessageReaction>[],
    this.deliveredAt,
    this.readAt,
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

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? type,
    String? body,
    String? stickerPackId,
    String? stickerId,
    String? stickerVariant,
    String? attachmentId,
    String? attachmentName,
    String? attachmentMime,
    int? attachmentSize,
    String? attachmentPath,
    bool? attachmentInline,
    String? voicePath,
    String? voiceMime,
    int? voiceDurationMs,
    MessageReplyPreview? replyTo,
    List<MessageReaction>? reactions,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      body: body ?? this.body,
      stickerPackId: stickerPackId ?? this.stickerPackId,
      stickerId: stickerId ?? this.stickerId,
      stickerVariant: stickerVariant ?? this.stickerVariant,
      attachmentId: attachmentId ?? this.attachmentId,
      attachmentName: attachmentName ?? this.attachmentName,
      attachmentMime: attachmentMime ?? this.attachmentMime,
      attachmentSize: attachmentSize ?? this.attachmentSize,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      attachmentInline: attachmentInline ?? this.attachmentInline,
      voicePath: voicePath ?? this.voicePath,
      voiceMime: voiceMime ?? this.voiceMime,
      voiceDurationMs: voiceDurationMs ?? this.voiceDurationMs,
      replyTo: replyTo ?? this.replyTo,
      reactions: reactions ?? this.reactions,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

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
    if (replyTo != null) 'replyTo': replyTo!.toJson(),
    if (reactions.isNotEmpty)
      'reactions': reactions.map((reaction) => reaction.toJson()).toList(),
    if (deliveredAt != null) 'deliveredAt': deliveredAt!.toIso8601String(),
    if (readAt != null) 'readAt': readAt!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  static ChatMessage fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? json['messageType'] ?? '')
        .toString()
        .trim();
    final type = rawType.isEmpty ? typeText : rawType;

    final voicePath = (json['voicePath'] ?? json['voice_path'])?.toString();
    final voiceMime = (json['voiceMime'] ?? json['voice_mime'])?.toString();
    final deliveredAt = DateTime.tryParse(
      (json['deliveredAt'] ?? json['delivered_at'] ?? '').toString(),
    );
    final readAt = DateTime.tryParse(
      (json['readAt'] ?? json['read_at'] ?? '').toString(),
    );

    final stickerPackId = (json['stickerPackId'] ?? json['sticker_pack_id'])
        ?.toString();
    final stickerId = (json['stickerId'] ?? json['sticker_id'])?.toString();
    final stickerVariant = (json['stickerVariant'] ?? json['sticker_variant'])
        ?.toString();

    final attachmentId = (json['attachmentId'] ?? json['attachment_id'])
        ?.toString();
    final attachmentName = (json['attachmentName'] ?? json['attachment_name'])
        ?.toString();
    final attachmentMime = (json['attachmentMime'] ?? json['attachment_mime'])
        ?.toString();
    int? attachmentSize;
    final attachmentSizeRaw = json['attachmentSize'] ?? json['attachment_size'];
    if (attachmentSizeRaw is int) {
      attachmentSize = attachmentSizeRaw;
    } else if (attachmentSizeRaw is double) {
      attachmentSize = attachmentSizeRaw.toInt();
    } else if (attachmentSizeRaw is String) {
      attachmentSize = int.tryParse(attachmentSizeRaw.trim());
    }
    final attachmentPath = (json['attachmentPath'] ?? json['attachment_path'])
        ?.toString();
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

    final replyTo = MessageReplyPreview.fromJson(
      json['replyTo'] ?? json['reply_to'],
    );
    final rawReactions = json['reactions'];
    final reactions = <MessageReaction>[];
    if (rawReactions is List) {
      for (final item in rawReactions) {
        final parsed = MessageReaction.fromJson(item);
        if (parsed != null) {
          reactions.add(parsed);
        }
      }
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
      replyTo: replyTo,
      reactions: reactions,
      deliveredAt: deliveredAt,
      readAt: readAt,
      createdAt:
          DateTime.tryParse(
            (json['createdAt'] ?? json['created_at'] ?? '').toString(),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
