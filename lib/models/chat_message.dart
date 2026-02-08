class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
      };

  static ChatMessage fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      chatId: (json['chatId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
