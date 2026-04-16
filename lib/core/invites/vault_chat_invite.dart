import 'dart:convert';

class VaultChatInvite {
  static const String type = 'cc-chat';
  static const String host = 'vault.theconquerorscourt.com';
  static const String joinPath = '/join';

  final String chatId;
  final String? title;
  final String? sharedSecret;
  final String? transport;

  const VaultChatInvite({
    required this.chatId,
    this.title,
    this.sharedSecret,
    this.transport,
  });

  Uri toUri() {
    return Uri.https(host, joinPath, <String, String>{
      'chatId': chatId.trim(),
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if ((sharedSecret ?? '').trim().isNotEmpty)
        'sharedSecret': sharedSecret!.trim(),
      if ((transport ?? '').trim().isNotEmpty) 'transport': transport!.trim(),
    });
  }

  String toInviteLink() => toUri().toString();

  Map<String, dynamic> toLegacyJson() {
    return <String, dynamic>{
      'type': type,
      'chatId': chatId.trim(),
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if ((transport ?? '').trim().isNotEmpty) 'transport': transport!.trim(),
      if ((sharedSecret ?? '').trim().isNotEmpty)
        'sharedSecret': sharedSecret!.trim(),
    };
  }

  static VaultChatInvite? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final fromJson = _parseJson(trimmed);
    if (fromJson != null) return fromJson;

    final uri = Uri.tryParse(trimmed);
    final looksLikeUri =
        uri != null && (uri.hasScheme || trimmed.contains('/'));
    final fromUri = _parseUri(trimmed);
    if (fromUri != null) return fromUri;
    if (looksLikeUri) return null;

    return VaultChatInvite(chatId: trimmed);
  }

  static VaultChatInvite? _parseJson(String raw) {
    if (!raw.startsWith('{')) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final chatId = (map['chatId'] ?? map['id'] ?? map['chat_id'] ?? '')
          .toString()
          .trim();
      if (chatId.isEmpty) return null;
      final title = (map['title'] ?? '').toString().trim();
      final sharedSecret =
          (map['sharedSecret'] ?? map['shared_secret'] ?? map['key'] ?? '')
              .toString()
              .trim();
      final transport = (map['transport'] ?? '').toString().trim();
      return VaultChatInvite(
        chatId: chatId,
        title: title.isEmpty ? null : title,
        sharedSecret: sharedSecret.isEmpty ? null : sharedSecret,
        transport: transport.isEmpty ? null : transport,
      );
    } catch (_) {
      return null;
    }
  }

  static VaultChatInvite? _parseUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || (!uri.hasScheme && !raw.contains('/'))) {
      return null;
    }

    final queryId = (uri.queryParameters['chatId'] ?? uri.queryParameters['id'])
        ?.trim();
    final title = uri.queryParameters['title']?.trim();
    final sharedSecret =
        (uri.queryParameters['sharedSecret'] ??
                uri.queryParameters['key'] ??
                '')
            .trim();
    final transport = (uri.queryParameters['transport'] ?? '').trim();

    if ((queryId ?? '').isNotEmpty) {
      return VaultChatInvite(
        chatId: queryId!,
        title: (title ?? '').isEmpty ? null : title,
        sharedSecret: sharedSecret.isEmpty ? null : sharedSecret,
        transport: transport.isEmpty ? null : transport,
      );
    }

    final pathSegments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (pathSegments.isEmpty) {
      return null;
    }

    final last = pathSegments.last;
    if (last.toLowerCase() == 'join' || last.toLowerCase() == 'join.html') {
      return null;
    }

    return VaultChatInvite(
      chatId: last,
      title: (title ?? '').isEmpty ? null : title,
      sharedSecret: sharedSecret.isEmpty ? null : sharedSecret,
      transport: transport.isEmpty ? null : transport,
    );
  }
}
