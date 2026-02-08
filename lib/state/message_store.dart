import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';

class MessageStore {
  static const _prefsKey = 'cc_messages_v1';

  static final ValueNotifier<List<ChatMessage>> messagesNotifier =
      ValueNotifier<List<ChatMessage>>(<ChatMessage>[]);

  static List<ChatMessage> get messages =>
      List.unmodifiable(messagesNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      messagesNotifier.value = <ChatMessage>[];
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        messagesNotifier.value = <ChatMessage>[];
        return;
      }

      final loaded = _parseMessages(decoded);
      if (loaded == null) {
        messagesNotifier.value = <ChatMessage>[];
        return;
      }

      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messagesNotifier.value = loaded;
    } catch (_) {
      messagesNotifier.value = <ChatMessage>[];
    }
  }

  static List<ChatMessage> getMessagesForChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return <ChatMessage>[];

    final filtered = messagesNotifier.value
        .where((m) => m.chatId == id)
        .toList();
    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
  }

  static Future<ChatMessage?> addMessage({
    required String chatId,
    required String senderId,
    required String body,
  }) async {
    final id = chatId.trim();
    final sender = senderId.trim();
    final text = body.trim();

    if (id.isEmpty || sender.isEmpty || text.isEmpty) return null;

    final message = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_$id',
      chatId: id,
      senderId: sender,
      body: text,
      createdAt: DateTime.now(),
    );

    final next = <ChatMessage>[...messagesNotifier.value, message];
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    await _save();
    return message;
  }

  static Future<ChatMessage?> addIncomingMessage({
    required String chatId,
    required String senderId,
    required String body,
    required DateTime createdAt,
    String? id,
  }) async {
    final trimmedChat = chatId.trim();
    final trimmedSender = senderId.trim();
    final text = body.trim();

    if (trimmedChat.isEmpty || trimmedSender.isEmpty || text.isEmpty) {
      return null;
    }

    final message = ChatMessage(
      id: (id == null || id.trim().isEmpty)
          ? '${createdAt.millisecondsSinceEpoch}_$trimmedChat'
          : id.trim(),
      chatId: trimmedChat,
      senderId: trimmedSender,
      body: text,
      createdAt: createdAt,
    );

    final next = <ChatMessage>[...messagesNotifier.value, message];
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    await _save();
    return message;
  }

  static String exportMessagesJson() {
    final payload = messagesNotifier.value.map((m) => m.toJson()).toList();
    return jsonEncode(payload);
  }

  static Future<bool> importMessagesJson(String rawJson) async {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return false;

    if (trimmed.length > 200000) return false;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return false;

      final loaded = _parseMessages(decoded);
      if (loaded == null) return false;

      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messagesNotifier.value = loaded;
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  static List<ChatMessage>? _parseMessages(List<dynamic> decoded) {
    final loaded = <ChatMessage>[];

    for (final item in decoded) {
      if (item is! Map) return null;
      final m = Map<String, dynamic>.from(item);

      final id = (m['id'] ?? '').toString().trim();
      final chatId = (m['chatId'] ?? '').toString().trim();
      final senderId = (m['senderId'] ?? '').toString().trim();
      final body = (m['body'] ?? '').toString();
      final createdAtRaw = (m['createdAt'] ?? '').toString().trim();
      final createdAt = DateTime.tryParse(createdAtRaw);

      if (id.isEmpty || chatId.isEmpty || senderId.isEmpty || createdAt == null) {
        return null;
      }

      loaded.add(ChatMessage(
        id: id,
        chatId: chatId,
        senderId: senderId,
        body: body,
        createdAt: createdAt,
      ));
    }

    return loaded;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = messagesNotifier.value.map((m) => m.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
