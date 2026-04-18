import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'identity_store.dart';

class ChatUnreadStore {
  static const String _prefsKey = 'cc_chat_unread_v1';

  static final ValueNotifier<Map<String, int>> unreadNotifier =
      ValueNotifier<Map<String, int>>(<String, int>{});

  static final Set<String> _openChatIds = <String>{};
  static final Map<String, _ChatUnreadState> _stateByChat =
      <String, _ChatUnreadState>{};

  static Future<void> init() async {
    await _loadFromPrefs();
  }

  static Future<void> reloadFromDisk() async {
    await _loadFromPrefs();
  }

  static Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _stateByChat.clear();
    if (raw == null || raw.trim().isEmpty) {
      unreadNotifier.value = <String, int>{};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        unreadNotifier.value = <String, int>{};
        return;
      }
      final parsed = <String, int>{};
      for (final entry in decoded.entries) {
        final id = entry.key.toString().trim();
        if (id.isEmpty) continue;
        final state = _ChatUnreadState.fromJson(entry.value);
        if (state != null) {
          _stateByChat[id] = state;
          if (state.unreadCount > 0) {
            parsed[id] = state.unreadCount;
          }
          continue;
        }
        final value = int.tryParse(entry.value.toString()) ?? 0;
        final migrated = _ChatUnreadState(unreadCount: value);
        _stateByChat[id] = migrated;
        if (value > 0) parsed[id] = value;
      }
      unreadNotifier.value = parsed;
    } catch (_) {
      _stateByChat.clear();
      unreadNotifier.value = <String, int>{};
    }
  }

  static int unreadForChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return 0;
    return unreadNotifier.value[id] ?? 0;
  }

  static int get totalUnread {
    var total = 0;
    for (final value in unreadNotifier.value.values) {
      total += value;
    }
    return total;
  }

  static bool isChatOpen(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return false;
    return _openChatIds.contains(id);
  }

  static void trackChatOpen(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _openChatIds.add(id);
  }

  static Future<void> noteChatOpened(String chatId) async {
    trackChatOpen(chatId);
    await markChatRead(chatId);
  }

  static void noteChatClosed(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _openChatIds.remove(id);
  }

  static Future<void> markChatRead(String chatId) async {
    await markChatReadThrough(chatId, messageId: null);
  }

  static Future<void> markChatReadThrough(
    String chatId, {
    String? messageId,
    DateTime? seenAt,
  }) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    final current = _stateByChat[id] ?? const _ChatUnreadState();
    final cleanMessageId = (messageId ?? '').trim();
    final nextState = current.copyWith(
      unreadCount: 0,
      lastReadMessageId: cleanMessageId.isEmpty
          ? current.lastReadMessageId
          : cleanMessageId,
      lastReadAt: seenAt ?? DateTime.now(),
    );
    _stateByChat[id] = nextState;
    final nextUnread = Map<String, int>.from(unreadNotifier.value);
    nextUnread.remove(id);
    unreadNotifier.value = nextUnread;
    await _save();
  }

  static Future<bool> recordIncomingMessage({
    required String chatId,
    required String senderId,
    String? messageId,
    String? envelopeId,
  }) async {
    final id = chatId.trim();
    final sender = senderId.trim();
    if (id.isEmpty || sender.isEmpty || _isSelfSender(sender)) {
      return false;
    }
    final cleanMessageId = (messageId ?? '').trim();
    final cleanEnvelopeId = (envelopeId ?? '').trim();
    final current = _stateByChat[id] ?? const _ChatUnreadState();
    if ((cleanMessageId.isNotEmpty &&
            cleanMessageId == current.lastIncomingMessageId) ||
        (cleanEnvelopeId.isNotEmpty &&
            cleanEnvelopeId == current.lastIncomingEnvelopeId)) {
      return false;
    }

    final isOpen = _openChatIds.contains(id);
    if (isOpen) {
      final nextState = current.copyWith(
        unreadCount: 0,
        lastIncomingMessageId: cleanMessageId.isEmpty
            ? current.lastIncomingMessageId
            : cleanMessageId,
        lastIncomingEnvelopeId: cleanEnvelopeId.isEmpty
            ? current.lastIncomingEnvelopeId
            : cleanEnvelopeId,
        lastReadMessageId: cleanMessageId.isEmpty
            ? current.lastReadMessageId
            : cleanMessageId,
        lastReadAt: DateTime.now(),
      );
      _stateByChat[id] = nextState;
      final nextUnread = Map<String, int>.from(unreadNotifier.value);
      nextUnread.remove(id);
      unreadNotifier.value = nextUnread;
      await _save();
      return false;
    }

    final nextState = current.copyWith(
      unreadCount: current.unreadCount + 1,
      lastIncomingMessageId: cleanMessageId.isEmpty
          ? current.lastIncomingMessageId
          : cleanMessageId,
      lastIncomingEnvelopeId: cleanEnvelopeId.isEmpty
          ? current.lastIncomingEnvelopeId
          : cleanEnvelopeId,
    );
    _stateByChat[id] = nextState;

    final nextUnread = Map<String, int>.from(unreadNotifier.value);
    if (nextState.unreadCount > 0) {
      nextUnread[id] = nextState.unreadCount;
    } else {
      nextUnread.remove(id);
    }
    unreadNotifier.value = nextUnread;
    await _save();
    return !isOpen;
  }

  static bool _isSelfSender(String senderId) {
    if (senderId == 'local') return true;
    final publicId = IdentityStore.publicId.trim();
    if (publicId.isNotEmpty && senderId == publicId) return true;
    final userId = IdentityStore.userId.trim();
    return userId.isNotEmpty && senderId == userId;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      for (final entry in _stateByChat.entries) entry.key: entry.value.toJson(),
    };
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}

class _ChatUnreadState {
  const _ChatUnreadState({
    this.unreadCount = 0,
    this.lastIncomingMessageId,
    this.lastIncomingEnvelopeId,
    this.lastReadMessageId,
    this.lastReadAt,
  });

  final int unreadCount;
  final String? lastIncomingMessageId;
  final String? lastIncomingEnvelopeId;
  final String? lastReadMessageId;
  final DateTime? lastReadAt;

  _ChatUnreadState copyWith({
    int? unreadCount,
    String? lastIncomingMessageId,
    String? lastIncomingEnvelopeId,
    String? lastReadMessageId,
    DateTime? lastReadAt,
  }) {
    return _ChatUnreadState(
      unreadCount: unreadCount ?? this.unreadCount,
      lastIncomingMessageId:
          lastIncomingMessageId ?? this.lastIncomingMessageId,
      lastIncomingEnvelopeId:
          lastIncomingEnvelopeId ?? this.lastIncomingEnvelopeId,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'unreadCount': unreadCount,
    if ((lastIncomingMessageId ?? '').trim().isNotEmpty)
      'lastIncomingMessageId': lastIncomingMessageId,
    if ((lastIncomingEnvelopeId ?? '').trim().isNotEmpty)
      'lastIncomingEnvelopeId': lastIncomingEnvelopeId,
    if ((lastReadMessageId ?? '').trim().isNotEmpty)
      'lastReadMessageId': lastReadMessageId,
    if (lastReadAt != null) 'lastReadAt': lastReadAt!.toIso8601String(),
  };

  static _ChatUnreadState? fromJson(dynamic raw) {
    if (raw is int) {
      return _ChatUnreadState(unreadCount: raw);
    }
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final unreadCount = switch (json['unreadCount']) {
      final int value => value,
      final double value => value.toInt(),
      final String value => int.tryParse(value.trim()) ?? 0,
      _ => 0,
    };
    return _ChatUnreadState(
      unreadCount: unreadCount < 0 ? 0 : unreadCount,
      lastIncomingMessageId:
          (json['lastIncomingMessageId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['lastIncomingMessageId'] ?? '').toString().trim(),
      lastIncomingEnvelopeId:
          (json['lastIncomingEnvelopeId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['lastIncomingEnvelopeId'] ?? '').toString().trim(),
      lastReadMessageId:
          (json['lastReadMessageId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['lastReadMessageId'] ?? '').toString().trim(),
      lastReadAt: DateTime.tryParse((json['lastReadAt'] ?? '').toString()),
    );
  }
}
