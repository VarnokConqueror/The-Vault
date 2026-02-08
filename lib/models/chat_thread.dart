import '../state/chat_store.dart';

/// Represents a local-only chat thread.
/// Optional contact references are local-only and persisted when present.
class ChatThread {
  final String id;
  final String title;
  final DateTime createdAt;
  // Optional local-only reference to a contact (no implied trust or linkage).
  final String? contactId;

  ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    this.contactId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        if (contactId != null) 'contactId': contactId,
      };

  static ChatThread fromJson(Map<String, dynamic> json) {
    final contactIdRaw = (json['contactId'] ?? '').toString().trim();
    return ChatThread(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? ChatStore.defaultChatTitle).toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      contactId: contactIdRaw.isEmpty ? null : contactIdRaw,
    );
  }
}




