class ChatAppearance {
  final String chatId;
  final String? backgroundUri;
  final String? toneUri;

  const ChatAppearance({
    required this.chatId,
    this.backgroundUri,
    this.toneUri,
  });

  Map<String, dynamic> toJson() => {
        'backgroundUri': backgroundUri,
        'toneUri': toneUri,
      };

  static ChatAppearance fromJson(String chatId, Map<String, dynamic> json) {
    return ChatAppearance(
      chatId: chatId,
      backgroundUri: (json['backgroundUri'] as String?)?.toString(),
      toneUri: (json['toneUri'] as String?)?.toString(),
    );
  }
}
