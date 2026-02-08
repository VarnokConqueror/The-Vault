class ChatAppearance {
  final String chatId;
  final String? backgroundUri;
  final String? toneUri;
  final String? toneName;

  const ChatAppearance({
    required this.chatId,
    this.backgroundUri,
    this.toneUri,
    this.toneName,
  });

  Map<String, dynamic> toJson() => {
        'backgroundUri': backgroundUri,
        'toneUri': toneUri,
        'toneName': toneName,
      };

  static ChatAppearance fromJson(String chatId, Map<String, dynamic> json) {
    return ChatAppearance(
      chatId: chatId,
      backgroundUri: (json['backgroundUri'] as String?)?.toString(),
      toneUri: (json['toneUri'] as String?)?.toString(),
      toneName: (json['toneName'] as String?)?.toString(),
    );
  }
}
