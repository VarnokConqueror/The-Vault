import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';

class ContactsStore {
  static const _prefsKey = 'cc_contacts_v1';

  static final ValueNotifier<List<Contact>> contactsNotifier =
      ValueNotifier<List<Contact>>(<Contact>[]);

  static List<Contact> get contacts => List.unmodifiable(contactsNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      contactsNotifier.value = <Contact>[];
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final loaded = decoded
            .whereType<Map>()
            .map((m) => Contact.fromJson(Map<String, dynamic>.from(m)))
            .toList();

        loaded.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        contactsNotifier.value = loaded;
      } else {
        contactsNotifier.value = <Contact>[];
      }
    } catch (_) {
      contactsNotifier.value = <Contact>[];
    }
  }

  static Future<void> addContact({
    required String publicId,
    required String displayName,
  }) async {
    final pid = publicId.trim();
    if (pid.isEmpty) return;

    final nameTrimmed = displayName.trim();
    final name = nameTrimmed.isEmpty ? 'Unknown' : nameTrimmed;

    final handle = _makeHandle(pid);

    // de-dupe by id
    final existingIndex =
        contactsNotifier.value.indexWhere((c) => c.id == pid);
    if (existingIndex != -1) {
      final existing = contactsNotifier.value[existingIndex];
      final updated = Contact(
        id: existing.id,
        displayName: name,
        handle: existing.handle,
        addedAt: existing.addedAt,
      );
      final next = [...contactsNotifier.value];
      next[existingIndex] = updated;
      contactsNotifier.value = next;
      await _save();
      return;
    }

    final contact = Contact(
      id: pid,
      displayName: name,
      handle: handle,
      addedAt: DateTime.now(),
    );

    contactsNotifier.value = <Contact>[contact, ...contactsNotifier.value];
    await _save();
  }

  static Future<void> removeContact(String id) async {
    final next = contactsNotifier.value.where((c) => c.id != id).toList();
    contactsNotifier.value = next;
    await _save();
  }

  static String _makeHandle(String publicId) {
    // short, local-only "fingerprint-ish" display (not crypto)
    final compact = publicId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (compact.length <= 8) return compact;
    return '${compact.substring(0, 4)}…${compact.substring(compact.length - 4)}';
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = contactsNotifier.value.map((c) => c.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
