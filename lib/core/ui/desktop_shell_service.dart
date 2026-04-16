import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../state/chat_unread_store.dart';

class DesktopShellService {
  static const MethodChannel _channel = MethodChannel(
    'the_vault/windows_shell',
  );

  static bool _initialized = false;
  static VoidCallback? _unreadListener;

  static Future<void> init() async {
    if (_initialized || kIsWeb || !Platform.isWindows) {
      return;
    }
    _initialized = true;
    _unreadListener = () {
      unawaited(syncUnreadCount());
    };
    ChatUnreadStore.unreadNotifier.addListener(_unreadListener!);
    await syncUnreadCount();
  }

  static Future<void> dispose() async {
    final listener = _unreadListener;
    if (listener != null) {
      ChatUnreadStore.unreadNotifier.removeListener(listener);
    }
    _unreadListener = null;
    _initialized = false;
  }

  static Future<void> syncUnreadCount() async {
    if (kIsWeb || !Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setUnreadCount', <String, dynamic>{
        'count': ChatUnreadStore.totalUnread,
      });
    } on MissingPluginException {
      // Ignore when the native shell hook is unavailable.
    } on PlatformException {
      // Ignore transient shell failures; the next unread change will resync.
    }
  }
}
