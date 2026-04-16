class ChatAppearance {
  final String chatId;
  final String? backgroundUri;
  final double? backgroundBrightness;
  final double? backgroundBlur;
  final String? toneUri;
  final String? toneName;

  const ChatAppearance({
    required this.chatId,
    this.backgroundUri,
    this.backgroundBrightness,
    this.backgroundBlur,
    this.toneUri,
    this.toneName,
  });

  Map<String, dynamic> toJson() => {
        'backgroundUri': backgroundUri,
        'backgroundBrightness': backgroundBrightness,
        'backgroundBlur': backgroundBlur,
        'toneUri': toneUri,
        'toneName': toneName,
      };

  static ChatAppearance fromJson(String chatId, Map<String, dynamic> json) {
    return ChatAppearance(
      chatId: chatId,
      backgroundUri: (json['backgroundUri'] as String?)?.toString(),
      backgroundBrightness: (json['backgroundBrightness'] as num?)?.toDouble(),
      backgroundBlur: (json['backgroundBlur'] as num?)?.toDouble(),
      toneUri: (json['toneUri'] as String?)?.toString(),
      toneName: (json['toneName'] as String?)?.toString(),
    );
  }
}
