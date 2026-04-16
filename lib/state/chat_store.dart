import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/e2ee/chat_cipher.dart';
import '../models/chat_thread.dart';

/// Scaffolding for future chat-creation flow wiring (logic only).
/// Chat creation remains local-only and must be user-initiated.
class ChatCreationIntent {
  final String id;
  final String title;
  final DateTime createdAt;

  const ChatCreationIntent({
    required this.id,
    required this.title,
    required this.createdAt,
  });
}

class ChatStore {
  static const String defaultChatTitle = 'Group Chat';
  static const _prefsKey = 'cc_chats_v1';
  static const int _persistVersion = 1;
  static const _payloadVersionKey = 'version';
  static const _payloadChatsKey = 'chats';

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
      final result = _decodeAndMigrate(decoded);
      if (result == null) {
        chatsNotifier.value = <ChatThread>[];
        return;
      }

      final loaded = result.chatMaps
          .map((m) => ChatThread.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      // newest first
      loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      chatsNotifier.value = loaded;

      if (result.needsSave) {
        await _save();
      }
    } catch (_) {
      chatsNotifier.value = <ChatThread>[];
    }
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _buildPersistedPayload(chatsNotifier.value);
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }

  static Future<ChatThread> createChat({
    required String title,
    String category = ChatThread.defaultCategory,
  }) async {
    final trimmed = title.trim();
    final chatTitle = trimmed.isEmpty ? defaultChatTitle : trimmed;
    final normalizedCategory = ChatThread.normalize(category);

    final chat = ChatThread(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: chatTitle,
      createdAt: DateTime.now(),
      category: normalizedCategory,
      sharedSecret: ChatCipher.generateSharedSecret(),
    );

    final next = <ChatThread>[chat, ...chatsNotifier.value];
    chatsNotifier.value = next;

    await _save();
    return chat;
  }

  static Future<ChatThread> upsertChatFromInvite({
    required String chatId,
    String? title,
    String? sharedSecret,
  }) async {
    final id = chatId.trim();
    final secret = (sharedSecret ?? '').trim();
    if (id.isEmpty) {
      return createChat(title: title ?? '');
    }

    for (var i = 0; i < chatsNotifier.value.length; i++) {
      final chat = chatsNotifier.value[i];
      if (chat.id == id) {
        if (secret.isEmpty || (chat.sharedSecret ?? '').trim().isNotEmpty) {
          return chat;
        }
        final updated = ChatThread(
          id: chat.id,
          title: chat.title,
          createdAt: chat.createdAt,
          sharedSecret: secret,
          contactId: chat.contactId,
        );
        final next = <ChatThread>[...chatsNotifier.value];
        next[i] = updated;
        next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        chatsNotifier.value = next;
        await _save();
        return updated;
      }
    }

    final trimmed = (title ?? '').trim();
    final chatTitle = trimmed.isEmpty ? defaultChatTitle : trimmed;

    final chat = ChatThread(
      id: id,
      title: chatTitle,
      createdAt: DateTime.now(),
      category: ChatThread.defaultCategory,
      sharedSecret: secret.isEmpty ? null : secret,
    );

    final next = <ChatThread>[chat, ...chatsNotifier.value];
    chatsNotifier.value = next;
    await _save();
    return chat;
  }

  static Future<ChatThread> createChatForContact({
    required String contactId,
    required String title,
  }) async {
    final cid = contactId.trim();
    if (cid.isEmpty) {
      return createChat(title: title);
    }

    for (final chat in chatsNotifier.value) {
      if (chat.contactId == cid) {
        return chat;
      }
    }

    final trimmed = title.trim();
    final chatTitle = trimmed.isEmpty ? defaultChatTitle : trimmed;
    final directChatId = directChatIdForContact(cid);

    final chat = ChatThread(
      id: directChatId,
      title: chatTitle,
      createdAt: DateTime.now(),
      category: ChatThread.defaultCategory,
      sharedSecret: ChatCipher.generateSharedSecret(),
      contactId: cid,
    );

    final next = <ChatThread>[chat, ...chatsNotifier.value];
    chatsNotifier.value = next;

    await _save();
    return chat;
  }

  static String directChatIdForContact(String contactId) {
    final cid = contactId.trim();
    if (cid.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
    return 'direct:$cid';
  }

  // --- Manual backup / restore (Venice-style) ---
  // Export all chats as a single JSON string.
  static String exportChatsJson() {
    final payload = _buildPersistedPayload(chatsNotifier.value);
    return jsonEncode(payload);
  }

  static ChatThread? getChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return null;
    for (final chat in chatsNotifier.value) {
      if (chat.id == id) {
        return chat;
      }
    }
    return null;
  }

  static String? sharedSecretFor(String chatId) {
    final secret = getChat(chatId)?.sharedSecret?.trim() ?? '';
    return secret.isEmpty ? null : secret;
  }

  static Future<String?> ensureSharedSecret(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return null;

    for (var i = 0; i < chatsNotifier.value.length; i++) {
      final chat = chatsNotifier.value[i];
      if (chat.id != id) continue;
      final existing = (chat.sharedSecret ?? '').trim();
      if (existing.isNotEmpty) {
        return existing;
      }
      final updated = ChatThread(
        id: chat.id,
        title: chat.title,
        createdAt: chat.createdAt,
        sharedSecret: ChatCipher.generateSharedSecret(),
        contactId: chat.contactId,
      );
      final next = <ChatThread>[...chatsNotifier.value];
      next[i] = updated;
      next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      chatsNotifier.value = next;
      await _save();
      return updated.sharedSecret;
    }
    return null;
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
      final result = _decodeAndMigrate(decoded);
      if (result == null) return false;

      final loaded = <ChatThread>[];

      for (final item in result.chatMaps) {
        final m = Map<String, dynamic>.from(item);

        // Require id + createdAt to be present/parseable
        final id = (m['id'] ?? '').toString().trim();
        final createdAtRaw = (m['createdAt'] ?? '').toString().trim();
        final createdAt = DateTime.tryParse(createdAtRaw);

        if (id.isEmpty || createdAt == null) return false;

        // Normalize title
        var title = (m['title'] ?? '').toString().trim();
        if (title.isEmpty) title = defaultChatTitle;

        final contactIdRaw = (m['contactId'] ?? '').toString().trim();
        final contactId = contactIdRaw.isEmpty ? null : contactIdRaw;
        final category = ChatThread.normalize(
          (m['category'] ?? '').toString().trim(),
        );

        loaded.add(
          ChatThread(
            id: id,
            title: title,
            createdAt: createdAt,
            category: category,
            sharedSecret:
                ((m['sharedSecret'] ?? m['shared_secret'] ?? '')
                        .toString()
                        .trim())
                    .isEmpty
                ? null
                : (m['sharedSecret'] ?? m['shared_secret']).toString().trim(),
            contactId: contactId,
          ),
        );
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

  static Map<String, dynamic> _buildPersistedPayload(List<ChatThread> chats) {
    return {
      _payloadVersionKey: _persistVersion,
      _payloadChatsKey: chats.map((c) => c.toJson()).toList(),
    };
  }

  static _ChatPersistResult? _decodeAndMigrate(dynamic decoded) {
    var version = 0;
    List<Map<String, dynamic>> chatMaps;
    var needsSave = false;

    if (decoded is List) {
      needsSave = true;
      chatMaps = decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } else if (decoded is Map) {
      final payload = Map<String, dynamic>.from(decoded);
      final rawChats = payload[_payloadChatsKey];
      if (rawChats is! List) return null;

      chatMaps = rawChats
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final parsedVersion = _parsePersistVersion(payload[_payloadVersionKey]);
      if (parsedVersion == null) {
        version = 0;
        needsSave = true;
      } else {
        version = parsedVersion;
        if (version < 0) {
          version = 0;
          needsSave = true;
        } else if (version < _persistVersion) {
          needsSave = true;
        }
      }
    } else {
      return null;
    }

    if (version < _persistVersion) {
      chatMaps = _migrateChatMaps(version, _persistVersion, chatMaps);
      needsSave = true;
    }

    return _ChatPersistResult(chatMaps: chatMaps, needsSave: needsSave);
  }

  static int? _parsePersistVersion(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  static List<Map<String, dynamic>> _migrateChatMaps(
    int fromVersion,
    int toVersion,
    List<Map<String, dynamic>> chatMaps,
  ) {
    var current = chatMaps;
    var version = fromVersion;

    while (version < toVersion) {
      switch (version) {
        case 0:
          current = current.map(_normalizeForV1).toList();
          break;
        default:
          break;
      }
      version++;
    }

    return current;
  }

  static Map<String, dynamic> _normalizeForV1(Map<String, dynamic> chat) {
    final normalized = Map<String, dynamic>.from(chat);
    final title = (normalized['title'] ?? '').toString().trim();
    if (title.isEmpty) {
      normalized['title'] = defaultChatTitle;
    }
    return normalized;
  }
}

class _ChatPersistResult {
  final List<Map<String, dynamic>> chatMaps;
  final bool needsSave;

  const _ChatPersistResult({required this.chatMaps, required this.needsSave});
}
