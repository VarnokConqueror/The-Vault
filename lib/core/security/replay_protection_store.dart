import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReplayProtectionStore {
  static const String _prefsKey = 'cc_replay_guard_v1';
  static const int _maxEntries = 10000;
  static const Duration _retention = Duration(days: 90);

  static Map<String, int>? _cache;

  static Future<void> remember({
    required String scope,
    required String envelopeId,
    String? senderId,
    String? messageId,
  }) async {
    await _ensureLoaded();
    final cache = _cache!;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cleanScope = scope.trim();
    final cleanEnvelopeId = envelopeId.trim();
    if (cleanScope.isEmpty || cleanEnvelopeId.isEmpty) {
      return;
    }

    cache[_envelopeKey(scope: cleanScope, envelopeId: cleanEnvelopeId)] = nowMs;

    final cleanSenderId = (senderId ?? '').trim();
    final cleanMessageId = (messageId ?? '').trim();
    if (cleanSenderId.isNotEmpty && cleanMessageId.isNotEmpty) {
      cache[_messageKey(
        scope: cleanScope,
        senderId: cleanSenderId,
        messageId: cleanMessageId,
      )] = nowMs;
    }

    _prune(cache, nowMs: nowMs);
    await _save(cache);
  }

  static Future<bool> hasSeen({
    required String scope,
    required String envelopeId,
    String? senderId,
    String? messageId,
  }) async {
    await _ensureLoaded();
    final cache = _cache!;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _prune(cache, nowMs: nowMs);

    final cleanScope = scope.trim();
    final cleanEnvelopeId = envelopeId.trim();
    if (cleanScope.isEmpty || cleanEnvelopeId.isEmpty) {
      return false;
    }

    if (cache.containsKey(
      _envelopeKey(scope: cleanScope, envelopeId: cleanEnvelopeId),
    )) {
      return true;
    }

    final cleanSenderId = (senderId ?? '').trim();
    final cleanMessageId = (messageId ?? '').trim();
    if (cleanSenderId.isEmpty || cleanMessageId.isEmpty) {
      return false;
    }

    return cache.containsKey(
      _messageKey(
        scope: cleanScope,
        senderId: cleanSenderId,
        messageId: cleanMessageId,
      ),
    );
  }

  static Future<void> _ensureLoaded() async {
    if (_cache != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _cache = <String, int>{};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _cache = <String, int>{};
        return;
      }
      _cache = <String, int>{
        for (final entry in decoded.entries)
          entry.key.toString(): _asInt(entry.value),
      };
    } catch (_) {
      _cache = <String, int>{};
    }
  }

  static int _asInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static void _prune(Map<String, int> cache, {required int nowMs}) {
    final minTimestamp = nowMs - _retention.inMilliseconds;
    cache.removeWhere((_, value) => value < minTimestamp);
    if (cache.length <= _maxEntries) {
      return;
    }
    final entries = cache.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final overflow = cache.length - _maxEntries;
    for (var index = 0; index < overflow; index++) {
      cache.remove(entries[index].key);
    }
  }

  static Future<void> _save(Map<String, int> cache) async {
    final prefs = await SharedPreferences.getInstance();
    if (cache.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }
    await prefs.setString(_prefsKey, jsonEncode(cache));
  }

  static String _envelopeKey({
    required String scope,
    required String envelopeId,
  }) => 'env|$scope|$envelopeId';

  static String _messageKey({
    required String scope,
    required String senderId,
    required String messageId,
  }) => 'msg|$scope|$senderId|$messageId';
}
