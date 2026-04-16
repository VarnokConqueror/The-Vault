import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_thread.dart';

class ChatCategoryStore {
  static const String _prefsKey = 'cc_chat_categories_v1';
  static const String _prefsCustomizedKey = 'cc_chat_categories_customized_v1';
  static const List<String> _legacySeededCategories = <String>[
    'Personal',
    'Work',
    'Family',
    'Important',
  ];

  static final ValueNotifier<List<String>> categoriesNotifier =
      ValueNotifier<List<String>>(<String>[]);

  static List<String> get categories =>
      List.unmodifiable(categoriesNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey);
    final customized = prefs.getBool(_prefsCustomizedKey) ?? false;
    if (stored == null) {
      categoriesNotifier.value = const <String>[];
      await prefs.setBool(_prefsCustomizedKey, false);
      return;
    }
    final sanitized = _sanitize(stored);
    final migrated = !customized && _matchesLegacySeededCategories(sanitized)
        ? const <String>[]
        : sanitized;
    categoriesNotifier.value = migrated;
    if (!_sameList(stored, migrated)) {
      await prefs.setStringList(_prefsKey, migrated);
    }
    if (prefs.getBool(_prefsCustomizedKey) == null) {
      await prefs.setBool(_prefsCustomizedKey, customized);
    }
  }

  static List<String> categoriesForChats(Iterable<ChatThread> chats) {
    final result = <String>[ChatThread.allCategory];
    final seen = <String>{ChatThread.allCategory};

    void addCategory(String? raw) {
      final category = normalize(raw);
      if (category.isEmpty || !seen.add(category)) return;
      result.add(category);
    }

    for (final category in categories) {
      addCategory(category);
    }
    for (final chat in chats) {
      addCategory(chat.category);
    }
    return result;
  }

  static String normalize(String? raw) {
    final category = (raw ?? '').trim();
    if (category.isEmpty || category == ChatThread.legacyDefaultCategory) {
      return ChatThread.defaultCategory;
    }
    return category;
  }

  static Future<void> setCategories(List<String> next) async {
    final sanitized = _sanitize(next);
    categoriesNotifier.value = sanitized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, sanitized);
    await prefs.setBool(_prefsCustomizedKey, true);
  }

  static Future<void> addCategory(String raw) async {
    final category = normalize(raw);
    if (category.isEmpty) return;
    await setCategories(<String>[...categories, category]);
  }

  static Future<void> removeCategory(String raw) async {
    final category = normalize(raw);
    if (category.isEmpty) return;
    await setCategories(
      categories.where((item) => item != category).toList(growable: false),
    );
  }

  static List<String> _sanitize(List<String> values) {
    final sanitized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final category = normalize(value);
      if (category.isEmpty || !seen.add(category)) continue;
      sanitized.add(category);
    }
    return sanitized;
  }

  static bool _matchesLegacySeededCategories(List<String> values) {
    if (values.length != _legacySeededCategories.length) {
      return false;
    }
    for (var i = 0; i < values.length; i++) {
      if (values[i] != _legacySeededCategories[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
