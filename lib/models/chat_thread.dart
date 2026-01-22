import '../state/chat_store.dart';
class ChatThread {
  final String id;
  final String title;
  final DateTime createdAt;

  ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };

  static ChatThread fromJson(Map<String, dynamic> json) {
    return ChatThread(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? ChatStore.defaultChatTitle).toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}




