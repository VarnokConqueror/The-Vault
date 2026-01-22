import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_thread.dart';

class ChatStore {
  static const String defaultChatTitle = 'Council Chamber';
  static const _prefsKey = 'cc_chats_v1';

  static final ValueNotifier<List<ChatThread>> chatsNotifier =
      ValueNotifier<List<ChatThread>>(<ChatThread>[]);

  static List<ChatThread> get chats => List.unmodifiable(chatsNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      chatsNotifier.value = <ChatThread>[];
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final loaded = decoded
            .whereType<Map>()
            .map((m) => ChatThread.fromJson(Map<String, dynamic>.from(m)))
            .toList();

        // newest first
        loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        chatsNotifier.value = loaded;
      } else {
        chatsNotifier.value = <ChatThread>[];
      }
    } catch (_) {
      chatsNotifier.value = <ChatThread>[];
    }
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = chatsNotifier.value.map((c) => c.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }

  static Future<ChatThread> createChat({required String title}) async {
    final trimmed = title.trim();
    final chatTitle = trimmed.isEmpty ? defaultChatTitle : trimmed;

    final chat = ChatThread(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: chatTitle,
      createdAt: DateTime.now(),
    );

    final next = <ChatThread>[chat, ...chatsNotifier.value];
    chatsNotifier.value = next;

    await _save();
    return chat;
  }

  // --- Manual backup / restore (Venice-style) ---
  // Export all chats as a single JSON string.
  static String exportChatsJson() {
    final payload = chatsNotifier.value.map((c) => c.toJson()).toList();
    return jsonEncode(payload);
  }

  // Import chats from a JSON string (replaces current list).
  // Returns true on success, false if the input is invalid.
  static Future<bool> importChatsJson(String rawJson) async {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return false;

    // Basic safety cap to avoid pathological inputs (200 KB)
    if (trimmed.length > 200000) return false;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return false;

      final loaded = <ChatThread>[];

      for (final item in decoded) {
        if (item is! Map) continue;

        final m = Map<String, dynamic>.from(item);

        // Require id + createdAt to be present/parseable
        final id = (m['id'] ?? '').toString().trim();
        final createdAtRaw = (m['createdAt'] ?? '').toString().trim();
        final createdAt = DateTime.tryParse(createdAtRaw);

        if (id.isEmpty || createdAt == null) continue;

        // Normalize title
        var title = (m['title'] ?? '').toString().trim();
        if (title.isEmpty) title = defaultChatTitle;

        loaded.add(ChatThread(
          id: id,
          title: title,
          createdAt: createdAt,
        ));
      }

      // If nothing valid, treat as failure (don't wipe existing list)
      if (loaded.isEmpty) return false;

      // newest first
      loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      chatsNotifier.value = loaded;
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }
  }








