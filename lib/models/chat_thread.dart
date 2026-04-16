enum ChatTransport { vaultDirect, vaultGroup }

/// Represents a local-only chat thread.
/// Optional contact references are local-only and persisted when present.
class ChatThread {
  static const String allCategory = 'All';
  static const String defaultCategory = '';
  static const String legacyDefaultCategory = 'Uncategorized';

  final String id;
  final String title;
  final DateTime createdAt;
  final String category;
  final String? sharedSecret;
  // Optional local-only reference to a contact (no implied trust or linkage).
  final String? contactId;

  bool get isDirectThread => (contactId ?? '').trim().isNotEmpty;
  bool get hasCategory => category.trim().isNotEmpty;

  ChatTransport get transport =>
      isDirectThread ? ChatTransport.vaultDirect : ChatTransport.vaultGroup;

  ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    this.category = defaultCategory,
    this.sharedSecret,
    this.contactId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'category': category,
    if (sharedSecret != null) 'sharedSecret': sharedSecret,
    if (contactId != null) 'contactId': contactId,
  };

  static ChatThread fromJson(Map<String, dynamic> json) {
    final contactIdRaw = (json['contactId'] ?? '').toString().trim();
    final sharedSecretRaw =
        (json['sharedSecret'] ?? json['shared_secret'] ?? '').toString().trim();
    final categoryRaw = (json['category'] ?? '').toString().trim();
    final normalizedCategory = normalize(categoryRaw);
    return ChatThread(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Group Chat').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      category: normalizedCategory,
      sharedSecret: sharedSecretRaw.isEmpty ? null : sharedSecretRaw,
      contactId: contactIdRaw.isEmpty ? null : contactIdRaw,
    );
  }

  static String normalize(String? raw) {
    final category = (raw ?? '').trim();
    if (category.isEmpty || category == legacyDefaultCategory) {
      return defaultCategory;
    }
    return category;
  }
}
