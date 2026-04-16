class PendingDeepLinkStore {
  static String? _pendingRoute;

  static String? get peek => _pendingRoute;

  static void set(String? route) {
    final trimmed = route?.trim() ?? '';
    if (trimmed.isEmpty) return;
    _pendingRoute = trimmed;
  }

  static String? consume() {
    final current = _pendingRoute;
    _pendingRoute = null;
    return current;
  }

  static void clear() {
    _pendingRoute = null;
  }
}
