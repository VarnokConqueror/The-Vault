import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/identity_store.dart';
import '../state/security_store.dart';

class StickerRef {
  final String packId;
  final String stickerId;

  const StickerRef({
    required this.packId,
    required this.stickerId,
  });

  String get key => '$packId::$stickerId';

  Map<String, dynamic> toJson() => {
        'packId': packId,
        'stickerId': stickerId,
      };

  static StickerRef? fromJson(Map<String, dynamic> json) {
    final packId = (json['packId'] ?? '').toString().trim();
    final stickerId = (json['stickerId'] ?? '').toString().trim();
    if (packId.isEmpty || stickerId.isEmpty) return null;
    return StickerRef(packId: packId, stickerId: stickerId);
  }
}

class StickerStore {
  static const _prefRecents = 'cc_stickers_recents_v1';
  static const _prefFavorites = 'cc_stickers_favorites_v1';

  static List<int> _keyBytes = const <int>[];

  static final ValueNotifier<List<StickerRef>> recentsNotifier =
      ValueNotifier<List<StickerRef>>(<StickerRef>[]);
  static final ValueNotifier<List<StickerRef>> favoritesNotifier =
      ValueNotifier<List<StickerRef>>(<StickerRef>[]);

  static String _userKey(String base) {
    final user = IdentityStore.publicId.trim();
    if (user.isEmpty) return base;
    return '${base}_$user';
  }

  static Future<void> init() async {
    _keyBytes = await _deriveKey();
    await _loadRecents();
    await _loadFavorites();
  }

  static List<StickerRef> get recents =>
      List.unmodifiable(recentsNotifier.value);
  static List<StickerRef> get favorites =>
      List.unmodifiable(favoritesNotifier.value);

  static bool isFavorite(StickerRef ref) {
    return favoritesNotifier.value.any((f) => f.key == ref.key);
  }

  static Future<void> addRecent(StickerRef ref) async {
    final next = <StickerRef>[
      ref,
      ...recentsNotifier.value.where((r) => r.key != ref.key),
    ];
    recentsNotifier.value = next.take(40).toList();
    await _saveRecents();
  }

  static Future<void> removeRecent(StickerRef ref) async {
    recentsNotifier.value =
        recentsNotifier.value.where((r) => r.key != ref.key).toList();
    await _saveRecents();
  }

  static Future<void> toggleFavorite(StickerRef ref) async {
    final exists = isFavorite(ref);
    if (exists) {
      favoritesNotifier.value =
          favoritesNotifier.value.where((r) => r.key != ref.key).toList();
    } else {
      favoritesNotifier.value = <StickerRef>[
        ref,
        ...favoritesNotifier.value.where((r) => r.key != ref.key),
      ];
    }
    await _saveFavorites();
  }

  static Future<void> _loadRecents() async {
    recentsNotifier.value = await _loadList(_userKey(_prefRecents));
  }

  static Future<void> _loadFavorites() async {
    favoritesNotifier.value = await _loadList(_userKey(_prefFavorites));
  }

  static Future<void> _saveRecents() async {
    await _saveList(_userKey(_prefRecents), recentsNotifier.value);
  }

  static Future<void> _saveFavorites() async {
    await _saveList(_userKey(_prefFavorites), favoritesNotifier.value);
  }

  static Future<List<StickerRef>> _loadList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return <StickerRef>[];
    final decoded = _decrypt(raw);
    if (decoded.trim().isEmpty) return <StickerRef>[];
    try {
      final json = jsonDecode(decoded);
      if (json is! List) return <StickerRef>[];
      final out = <StickerRef>[];
      for (final item in json) {
        if (item is! Map) continue;
        final ref = StickerRef.fromJson(Map<String, dynamic>.from(item));
        if (ref != null) out.add(ref);
      }
      return out;
    } catch (_) {
      return <StickerRef>[];
    }
  }

  static Future<void> _saveList(String key, List<StickerRef> refs) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(refs.map((r) => r.toJson()).toList());
    await prefs.setString(key, _encrypt(payload));
  }

  static String _encrypt(String input) {
    if (_keyBytes.isEmpty) return input;
    final bytes = utf8.encode(input);
    final key = _keyBytes;
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ key[i % key.length];
    }
    return base64Encode(out);
  }

  static String _decrypt(String input) {
    if (_keyBytes.isEmpty) return input;
    try {
      final data = base64Decode(input);
      final key = _keyBytes;
      final out = Uint8List(data.length);
      for (var i = 0; i < data.length; i++) {
        out[i] = data[i] ^ key[i % key.length];
      }
      return utf8.decode(out);
    } catch (_) {
      return '';
    }
  }

  static Future<List<int>> _deriveKey() async {
    try {
      final secret = await SecurityStore.getOrCreateAuthSecret();
      return sha256.convert(utf8.encode(secret)).bytes;
    } catch (_) {
      return const <int>[];
    }
  }
}
