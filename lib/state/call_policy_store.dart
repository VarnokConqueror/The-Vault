import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contacts_store.dart';

enum WhoCanCallMode {
  allowAll,
  contactsOnly,
  enabledContactsOnly,
  noPhoneCalls,
}

class CallPolicyStore {
  static const _prefMode = 'cc_calls_who_can_call_v1';
  static const _prefAlwaysAllow = 'cc_calls_always_allow_v1';
  static const _prefNeverAllow = 'cc_calls_never_allow_v1';
  static const _prefEnabledContacts = 'cc_calls_enabled_contacts_v1';
  static const _prefRecentCallers = 'cc_calls_recent_callers_v1';

  static final ValueNotifier<WhoCanCallMode> modeNotifier =
      ValueNotifier<WhoCanCallMode>(WhoCanCallMode.enabledContactsOnly);
  static final ValueNotifier<Set<String>> alwaysAllowNotifier =
      ValueNotifier<Set<String>>(<String>{});
  static final ValueNotifier<Set<String>> neverAllowNotifier =
      ValueNotifier<Set<String>>(<String>{});
  static final ValueNotifier<Set<String>> enabledContactsNotifier =
      ValueNotifier<Set<String>>(<String>{});
  static final ValueNotifier<List<String>> recentCallersNotifier =
      ValueNotifier<List<String>>(<String>[]);

  static WhoCanCallMode get mode => modeNotifier.value;
  static Set<String> get alwaysAllow => Set.unmodifiable(alwaysAllowNotifier.value);
  static Set<String> get neverAllow => Set.unmodifiable(neverAllowNotifier.value);
  static Set<String> get enabledContacts =>
      Set.unmodifiable(enabledContactsNotifier.value);
  static List<String> get recentCallers =>
      List.unmodifiable(recentCallersNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    modeNotifier.value = _parseMode(prefs.getString(_prefMode));
    alwaysAllowNotifier.value = _parseStringSet(prefs.getStringList(_prefAlwaysAllow));
    neverAllowNotifier.value = _parseStringSet(prefs.getStringList(_prefNeverAllow));
    enabledContactsNotifier.value =
        _parseStringSet(prefs.getStringList(_prefEnabledContacts));
    recentCallersNotifier.value =
        _parseStringList(prefs.getStringList(_prefRecentCallers));
  }

  static Future<void> setMode(WhoCanCallMode mode) async {
    modeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, _modeToString(mode));
  }

  static Future<void> setAlwaysAllow(String contactId, bool allowed) async {
    final id = contactId.trim();
    if (id.isEmpty) return;
    final next = <String>{...alwaysAllowNotifier.value};
    if (allowed) {
      next.add(id);
    } else {
      next.remove(id);
    }
    alwaysAllowNotifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefAlwaysAllow, next.toList()..sort());
  }

  static Future<void> setNeverAllow(String contactId, bool blocked) async {
    final id = contactId.trim();
    if (id.isEmpty) return;
    final next = <String>{...neverAllowNotifier.value};
    if (blocked) {
      next.add(id);
    } else {
      next.remove(id);
    }
    neverAllowNotifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefNeverAllow, next.toList()..sort());
  }

  static Future<void> setCallsEnabled(String contactId, bool enabled) async {
    final id = contactId.trim();
    if (id.isEmpty) return;
    final next = <String>{...enabledContactsNotifier.value};
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    enabledContactsNotifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefEnabledContacts, next.toList()..sort());
  }

  static Future<void> rememberRecentCaller(String contactId) async {
    final id = contactId.trim();
    if (id.isEmpty) return;
    final next = <String>[id, ...recentCallersNotifier.value.where((e) => e != id)];
    if (next.length > 25) {
      next.removeRange(25, next.length);
    }
    recentCallersNotifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefRecentCallers, next);
  }

  static bool isIncomingCallPermitted({
    required String callerId,
  }) {
    final id = callerId.trim();
    if (id.isEmpty) return false;

    if (neverAllowNotifier.value.contains(id)) return false;
    if (alwaysAllowNotifier.value.contains(id)) return true;

    final m = modeNotifier.value;
    if (m == WhoCanCallMode.noPhoneCalls) return false;

    final isContact = ContactsStore.contacts.any((c) => c.id == id);
    if (!isContact && m != WhoCanCallMode.allowAll) return false;

    if (m == WhoCanCallMode.enabledContactsOnly) {
      return enabledContactsNotifier.value.contains(id);
    }

    // allowAll or contactsOnly
    return true;
  }

  // Background isolates may not have ContactsStore initialized; this helper reads
  // contacts and call policy directly from SharedPreferences.
  static Future<bool> isIncomingCallPermittedFromPrefs({
    required String callerId,
  }) async {
    final id = callerId.trim();
    if (id.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final neverAllow = _parseStringSet(prefs.getStringList(_prefNeverAllow));
    if (neverAllow.contains(id)) return false;
    final alwaysAllow = _parseStringSet(prefs.getStringList(_prefAlwaysAllow));
    if (alwaysAllow.contains(id)) return true;

    final mode = _parseMode(prefs.getString(_prefMode));
    if (mode == WhoCanCallMode.noPhoneCalls) return false;

    if (mode == WhoCanCallMode.allowAll) return true;

    final isContact = _isCallerInContactsPrefs(prefs, id);
    if (!isContact) return false;

    if (mode == WhoCanCallMode.enabledContactsOnly) {
      final enabledContacts =
          _parseStringSet(prefs.getStringList(_prefEnabledContacts));
      return enabledContacts.contains(id);
    }

    return true;
  }

  static bool _isCallerInContactsPrefs(SharedPreferences prefs, String callerId) {
    final raw = prefs.getString('cc_contacts_v1');
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return false;
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        if (id == callerId) return true;
      }
    } catch (_) {}
    return false;
  }

  static WhoCanCallMode _parseMode(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'allow_all':
        return WhoCanCallMode.allowAll;
      case 'contacts_only':
        return WhoCanCallMode.contactsOnly;
      case 'enabled_contacts_only':
        return WhoCanCallMode.enabledContactsOnly;
      case 'no_phone_calls':
        return WhoCanCallMode.noPhoneCalls;
    }
    // Default: strict (opt-in per contact).
    return WhoCanCallMode.enabledContactsOnly;
  }

  static String _modeToString(WhoCanCallMode mode) {
    switch (mode) {
      case WhoCanCallMode.allowAll:
        return 'allow_all';
      case WhoCanCallMode.contactsOnly:
        return 'contacts_only';
      case WhoCanCallMode.enabledContactsOnly:
        return 'enabled_contacts_only';
      case WhoCanCallMode.noPhoneCalls:
        return 'no_phone_calls';
    }
  }

  static Set<String> _parseStringSet(List<String>? raw) {
    final list = _parseStringList(raw);
    return list.toSet();
  }

  static List<String> _parseStringList(List<String>? raw) {
    if (raw == null || raw.isEmpty) return <String>[];
    return raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
}

