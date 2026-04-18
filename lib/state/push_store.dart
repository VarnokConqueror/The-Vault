import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushStore {
  static const _prefEnabled = 'cc_push_enabled_v1';
  static const _prefNotify = 'cc_push_notify_new_messages_v1';
  static const _prefPreview = 'cc_push_show_preview_v1';
  static const _prefRequireUnlockOnOpen = 'cc_push_require_unlock_on_open_v1';
  static const _prefMuted = 'cc_push_muted_mailboxes_v1';
  static const _prefRecentEnvelopes = 'cc_push_recent_envelope_ids_v1';

  static final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> notifyOnNewMessagesNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> showPreviewNotifier = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<bool> requireUnlockOnOpenNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<Set<String>> mutedMailboxesNotifier =
      ValueNotifier<Set<String>>(<String>{});

  static List<String> _recentEnvelopeIds = <String>[];

  static bool get enabled => enabledNotifier.value;
  static bool get notifyOnNewMessages => notifyOnNewMessagesNotifier.value;
  static bool get showPreview => showPreviewNotifier.value;
  static bool get requireUnlockOnNotificationOpen =>
      requireUnlockOnOpenNotifier.value;
  static Set<String> get mutedMailboxes =>
      Set.unmodifiable(mutedMailboxesNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    enabledNotifier.value = prefs.getBool(_prefEnabled) ?? true;
    notifyOnNewMessagesNotifier.value = prefs.getBool(_prefNotify) ?? true;
    showPreviewNotifier.value = prefs.getBool(_prefPreview) ?? false;
    requireUnlockOnOpenNotifier.value =
        prefs.getBool(_prefRequireUnlockOnOpen) ?? true;

    final muted = (prefs.getStringList(_prefMuted) ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    mutedMailboxesNotifier.value = muted;

    _recentEnvelopeIds =
        (prefs.getStringList(_prefRecentEnvelopes) ?? const <String>[])
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: true);
  }

  static Future<void> setEnabled(bool enabled) async {
    enabledNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
  }

  static Future<void> setNotifyOnNewMessages(bool enabled) async {
    notifyOnNewMessagesNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefNotify, enabled);
  }

  static Future<void> setShowPreview(bool enabled) async {
    showPreviewNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPreview, enabled);
  }

  static Future<void> setRequireUnlockOnNotificationOpen(bool enabled) async {
    requireUnlockOnOpenNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRequireUnlockOnOpen, enabled);
  }

  static bool isMuted(String mailboxId) {
    final id = mailboxId.trim();
    if (id.isEmpty) return false;
    return mutedMailboxesNotifier.value.contains(id);
  }

  static Future<void> setMuted(String mailboxId, bool muted) async {
    final id = mailboxId.trim();
    if (id.isEmpty) return;

    final next = <String>{...mutedMailboxesNotifier.value};
    if (muted) {
      next.add(id);
    } else {
      next.remove(id);
    }
    mutedMailboxesNotifier.value = next;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefMuted, next.toList()..sort());
  }

  static Future<void> clearRecentEnvelopeIds() async {
    _recentEnvelopeIds = <String>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefRecentEnvelopes);
  }

  static List<String> _normalizedNotificationIds(Iterable<String> ids) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      normalized.add(id);
    }
    return normalized;
  }

  // Returns true if none of the candidate ids were seen before. If any were
  // already seen, the full candidate set is still merged into the recent cache
  // so envelope ids and client message ids stay linked for future dedupe.
  static Future<bool> rememberNotificationIds(Iterable<String> ids) async {
    final normalized = _normalizedNotificationIds(ids);
    if (normalized.isEmpty) return true;

    final alreadySeen = normalized.any(_recentEnvelopeIds.contains);
    var changed = false;
    for (final id in normalized) {
      if (_recentEnvelopeIds.contains(id)) continue;
      _recentEnvelopeIds.add(id);
      changed = true;
    }
    if (_recentEnvelopeIds.length > 200) {
      _recentEnvelopeIds = _recentEnvelopeIds.sublist(
        _recentEnvelopeIds.length - 200,
      );
      changed = true;
    }

    if (changed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefRecentEnvelopes, _recentEnvelopeIds);
    }
    return !alreadySeen;
  }

  // Returns true if this is a new envelopeId, false if we've already seen it.
  static Future<bool> rememberEnvelopeId(String envelopeId) async {
    return rememberNotificationIds(<String>[envelopeId]);
  }
}
