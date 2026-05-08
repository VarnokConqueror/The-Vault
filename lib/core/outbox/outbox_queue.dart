import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OutboxEntry {
  const OutboxEntry({
    required this.chatId,
    required this.messageId,
    this.retryCount = 0,
    this.lastRetryAt,
    this.relayPayload,
  });

  final String chatId;
  final String messageId;
  final int retryCount;
  final DateTime? lastRetryAt;
  final Map<String, dynamic>? relayPayload;

  String get key => '${chatId.trim()}::${messageId.trim()}';
  bool get isRelayAction => relayPayload != null;

  OutboxEntry copyWith({
    String? chatId,
    String? messageId,
    int? retryCount,
    DateTime? lastRetryAt,
    Map<String, dynamic>? relayPayload,
  }) {
    return OutboxEntry(
      chatId: chatId ?? this.chatId,
      messageId: messageId ?? this.messageId,
      retryCount: retryCount ?? this.retryCount,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
      relayPayload: relayPayload ?? this.relayPayload,
    );
  }

  Map<String, dynamic> toJson() => {
    'chatId': chatId,
    'messageId': messageId,
    'retryCount': retryCount,
    if (lastRetryAt != null) 'lastRetryAt': lastRetryAt!.toIso8601String(),
    if (relayPayload != null) 'relayPayload': relayPayload,
  };

  static OutboxEntry? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final chatId = (json['chatId'] ?? '').toString().trim();
    final messageId = (json['messageId'] ?? '').toString().trim();
    if (chatId.isEmpty || messageId.isEmpty) {
      return null;
    }
    final retryCountRaw = json['retryCount'];
    int retryCount = 0;
    if (retryCountRaw is int) {
      retryCount = retryCountRaw;
    } else if (retryCountRaw is double) {
      retryCount = retryCountRaw.toInt();
    } else if (retryCountRaw is String) {
      retryCount = int.tryParse(retryCountRaw.trim()) ?? 0;
    }
    return OutboxEntry(
      chatId: chatId,
      messageId: messageId,
      retryCount: retryCount < 0 ? 0 : retryCount,
      lastRetryAt: DateTime.tryParse(
        (json['lastRetryAt'] ?? json['last_retry_at'] ?? '').toString(),
      ),
      relayPayload: json['relayPayload'] is Map
          ? Map<String, dynamic>.from(json['relayPayload'] as Map)
          : null,
    );
  }
}

class OutboxQueue {
  static const String _prefsKey = 'cc_outbox_queue_v1';

  static Future<List<OutboxEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <OutboxEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <OutboxEntry>[];
      }
      final entries = <OutboxEntry>[];
      for (final item in decoded) {
        final parsed = OutboxEntry.fromJson(item);
        if (parsed != null) {
          entries.add(parsed);
        }
      }
      return entries;
    } catch (_) {
      return const <OutboxEntry>[];
    }
  }

  static Future<void> upsert(OutboxEntry entry) async {
    final entries = await loadAll();
    final next = <OutboxEntry>[
      for (final existing in entries)
        if (existing.key != entry.key) existing,
      entry,
    ];
    await _save(next);
  }

  static Future<void> remove({
    required String chatId,
    required String messageId,
  }) async {
    final key = '${chatId.trim()}::${messageId.trim()}';
    final entries = await loadAll();
    final next = entries.where((entry) => entry.key != key).toList();
    if (next.length == entries.length) return;
    await _save(next);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Future<void> _save(List<OutboxEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}
