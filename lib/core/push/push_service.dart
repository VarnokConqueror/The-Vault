import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/chat_thread.dart';
import '../../screens/thread_screen.dart';
import '../../state/chat_store.dart';
import '../../state/identity_store.dart';
import '../../state/push_store.dart';
import '../../state/security_store.dart';
import '../relay/relay_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The OS will display notification payloads automatically while the app is
  // backgrounded/locked. Keep this handler lightweight for data-only messages.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class PushService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _initialized = false;

  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  static StreamSubscription<String>? _tokenRefreshSub;

  static bool _syncInProgress = false;
  static bool _needsResync = false;
  static String? _pendingMailboxId;

  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (!Platform.isAndroid) return;
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    await _initLocalNotifications();
    await _initFirebaseMessaging();

    PushStore.enabledNotifier.addListener(_scheduleResync);
    PushStore.notifyOnNewMessagesNotifier.addListener(_scheduleResync);
    PushStore.showPreviewNotifier.addListener(_scheduleResync);
    PushStore.mutedMailboxesNotifier.addListener(_scheduleResync);
    ChatStore.chatsNotifier.addListener(_scheduleResync);
    SecurityStore.lockedNotifier.addListener(_handleLockStateChanged);

    _scheduleResync();
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final mailboxId = (response.payload ?? '').trim();
        if (mailboxId.isEmpty) return;
        _handleMailboxOpen(mailboxId);
      },
    );

    final android =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'cc_messages',
        'Messages',
        description: 'New messages from The Vault',
        importance: Importance.high,
      ),
    );
  }

  static Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _onMessageOpenedSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      _scheduleResync();
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleNotificationOpen(initial);
    }
  }

  static Future<bool> _requestAndroidNotificationPermission() async {
    final android =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      final granted = await android.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  static String _mailboxIdFromMessage(RemoteMessage message) {
    final data = message.data;
    final id = (data['mailbox_id'] ?? data['mailboxId'] ?? '').toString().trim();
    return id;
  }

  static String _envelopeIdFromMessage(RemoteMessage message) {
    final data = message.data;
    final id =
        (data['envelope_id'] ?? data['envelopeId'] ?? '').toString().trim();
    return id;
  }

  static String _senderIdFromMessage(RemoteMessage message) {
    final data = message.data;
    final id = (data['senderId'] ?? data['sender_id'] ?? '').toString().trim();
    return id;
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!PushStore.enabled) return;
    if (!PushStore.notifyOnNewMessages) return;

    final mailboxId = _mailboxIdFromMessage(message);
    if (mailboxId.isEmpty) return;
    if (PushStore.isMuted(mailboxId)) return;

    final senderId = _senderIdFromMessage(message);
    if (senderId.isNotEmpty && senderId == IdentityStore.publicId.trim()) {
      return;
    }

    final envelopeId = _envelopeIdFromMessage(message);
    if (envelopeId.isNotEmpty) {
      final isNew = await PushStore.rememberEnvelopeId(envelopeId);
      if (!isNew) return;
    }

    final title = message.notification?.title?.trim().isNotEmpty == true
        ? message.notification!.title!.trim()
        : "The Vault";
    final body = message.notification?.body?.trim().isNotEmpty == true
        ? message.notification!.body!.trim()
        : 'New message';

    await _showLocalNotification(
      mailboxId: mailboxId,
      title: title,
      body: body,
    );
  }

  static void _handleNotificationOpen(RemoteMessage message) {
    final mailboxId = _mailboxIdFromMessage(message);
    if (mailboxId.isEmpty) return;
    _handleMailboxOpen(mailboxId);
  }

  static void _handleMailboxOpen(String mailboxId) {
    final id = mailboxId.trim();
    if (id.isEmpty) return;

    if (SecurityStore.isLocked) {
      _pendingMailboxId = id;
      return;
    }

    _pendingMailboxId = null;
    _openThread(id);
  }

  static void _handleLockStateChanged() {
    if (SecurityStore.isLocked) return;
    final pending = _pendingMailboxId;
    if (pending == null || pending.trim().isEmpty) return;
    _pendingMailboxId = null;
    _openThread(pending);
  }

  static void _openThread(String mailboxId) {
    if (!IdentityStore.usernameCustom) return;
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;

    ChatThread? chat;
    for (final c in ChatStore.chats) {
      if (c.id == mailboxId) {
        chat = c;
        break;
      }
    }

    final titleRaw = (chat?.title ?? '').trim();
    final title = titleRaw.isEmpty ? ChatStore.defaultChatTitle : titleRaw;
    final contactId = chat?.contactId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ThreadScreen(
            chatId: mailboxId,
            chatTitle: title,
            contactId: contactId,
          ),
        ),
      );
    });
  }

  static int _notificationIdForMailbox(String mailboxId) {
    // Stable-ish: collapse notifications by mailbox/thread rather than envelope.
    return mailboxId.hashCode & 0x7fffffff;
  }

  static Future<void> _showLocalNotification({
    required String mailboxId,
    required String title,
    required String body,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'cc_messages',
        'Messages',
        channelDescription: 'New messages from The Vault',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
      ),
    );
    await _localNotifications.show(
      _notificationIdForMailbox(mailboxId),
      title,
      body,
      details,
      payload: mailboxId,
    );
  }

  static void _scheduleResync() {
    if (!_initialized) return;
    // Best-effort debounce: coalesce cascaded preference/chat updates.
    scheduleMicrotask(() {
      _syncRegistrations();
    });
  }

  static Future<void> _syncRegistrations() async {
    if (_syncInProgress) {
      _needsResync = true;
      return;
    }
    _syncInProgress = true;
    try {
      if (!Platform.isAndroid) return;

      final deviceId = IdentityStore.publicId.trim();
      if (deviceId.isEmpty) return;

      final chats = ChatStore.chats;
      final mailboxIds = chats.map((c) => c.id.trim()).where((id) => id.isNotEmpty).toList();

      if (!PushStore.enabled) {
        for (final mailboxId in mailboxIds) {
          await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
        }
        return;
      }

      final permissionOk = await _requestAndroidNotificationPermission();
      if (!permissionOk) {
        await PushStore.setEnabled(false);
        for (final mailboxId in mailboxIds) {
          await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
        }
        return;
      }

      final fcmToken = (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
      if (fcmToken.isEmpty) return;

      final muted = PushStore.mutedMailboxes;
      for (final mailboxId in mailboxIds) {
        if (muted.contains(mailboxId)) {
          await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
          continue;
        }

        await RelayClient.registerPush(
          mailboxId: mailboxId,
          deviceId: deviceId,
          platform: 'android',
          fcmToken: fcmToken,
          notifyOnNewMessages: PushStore.notifyOnNewMessages,
          showPreview: PushStore.showPreview,
        );
      }
    } catch (error) {
      debugPrint('[Push] sync failed: $error');
    } finally {
      _syncInProgress = false;
      if (_needsResync) {
        _needsResync = false;
        await _syncRegistrations();
      }
    }
  }

  static Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedSub = null;
    _tokenRefreshSub = null;
  }
}
