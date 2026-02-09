import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/chat_thread.dart';
import '../../screens/thread_screen.dart';
import '../../state/chat_store.dart';
import '../../state/chat_appearance_store.dart';
import '../../state/contact_appearance_store.dart';
import '../../state/contacts_store.dart';
import '../../state/identity_store.dart';
import '../../state/push_store.dart';
import '../../state/security_store.dart';
import '../relay/relay_client.dart';
import '../tones/tone_storage.dart';
import 'push_background_handler.dart';
import '../calls/call_service.dart';

class PushService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _initialized = false;

  static const String _defaultChannelId = 'cc_messages';
  static const String _callChannelId = 'cc_calls';
  static final Map<String, String> _channelIdByMailbox = <String, String>{};

  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  static StreamSubscription<String>? _tokenRefreshSub;

  static bool _syncInProgress = false;
  static bool _needsResync = false;
  static Timer? _syncRetryTimer;
  static int _retrySeconds = 15;
  static String? _pendingMailboxId;
  static final Set<String> _attemptedChannelSoundUpdate = <String>{};
  static Timer? _pendingOpenTimer;
  static int _pendingOpenAttempts = 0;

  static int _callNotificationId(String callId) {
    var hash = 0;
    for (final code in callId.codeUnits) {
      hash = ((hash << 5) - hash + code) & 0x7fffffff;
    }
    return hash;
  }

  static String _encodeCallPayload({
    required String callId,
    required String mailboxId,
    required String callerId,
    required String callerName,
  }) {
    return jsonEncode(<String, dynamic>{
      't': 'call',
      'callId': callId,
      'mailboxId': mailboxId,
      'callerId': callerId,
      'callerName': callerName,
    });
  }

  static void resync() {
    _scheduleResync();
  }

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
    ChatAppearanceStore.appearancesNotifier.addListener(_scheduleResync);
    ContactAppearanceStore.appearancesNotifier.addListener(_scheduleResync);
    SecurityStore.lockedNotifier.addListener(_handleLockStateChanged);

    _scheduleResync();
  }

  static String _channelIdForMailbox(String mailboxId) {
    final id = mailboxId.trim();
    if (id.isEmpty) return _defaultChannelId;
    // Per-thread channels allow per-thread tones.
    return 'cc_messages_$id';
  }

  static String _customChannelIdForMailbox(String mailboxId, String soundUri) {
    final id = mailboxId.trim();
    if (id.isEmpty) return _defaultChannelId;

    final sound = soundUri.trim();
    if (sound.isEmpty) return _channelIdForMailbox(id);

    final digest = sha1.convert(utf8.encode(sound)).toString();
    final suffix = digest.substring(0, 10);
    return 'cc_messages_${id}_$suffix';
  }

  static String _toAndroidSoundUri(String uriOrPath) {
    final raw = uriOrPath.trim();
    if (raw.isEmpty) return '';
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.scheme.isNotEmpty) return raw;
    return Uri.file(raw).toString();
  }

  static bool _soundMatches(
    AndroidNotificationSound? existing,
    String? desired,
  ) {
    final desiredClean = (desired ?? '').trim();
    if (existing == null) {
      return desiredClean.isEmpty;
    }
    final ex = existing.sound.trim();
    if (desiredClean.isEmpty) return false;
    return ex == desiredClean;
  }

  static Future<void> _ensureChannelForChat(ChatThread chat) async {
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    Map<String, AndroidNotificationChannel>? channelById;
    try {
      final channels =
          await android.getNotificationChannels() ??
          <AndroidNotificationChannel>[];
      channelById = <String, AndroidNotificationChannel>{
        for (final c in channels) c.id: c,
      };
    } catch (_) {
      channelById = null;
    }

    await _ensureChannelForChatInternal(android, chat, channelById: channelById);
  }

  static Future<void> _ensureChannelForChatInternal(
    AndroidFlutterLocalNotificationsPlugin android,
    ChatThread chat, {
    required Map<String, AndroidNotificationChannel>? channelById,
  }) async {
    final mailboxId = chat.id.trim();
    if (mailboxId.isEmpty) return;

    final chatAppearance = ChatAppearanceStore.getForChat(mailboxId);
    String? toneUri = chatAppearance?.toneUri?.trim();
    String? toneName = chatAppearance?.toneName?.trim();
    if (toneUri == null || toneUri.isEmpty) {
      final contactId = (chat.contactId ?? '').trim();
      if (contactId.isNotEmpty) {
        final contactAppearance = ContactAppearanceStore.getForContact(
          contactId,
        );
        toneUri = contactAppearance?.toneUri?.trim();
        toneName = contactAppearance?.toneName?.trim();
      }
    }

    String? desiredSoundUri;
    if (toneUri != null && toneUri.trim().isNotEmpty) {
      final key = 'chat_$mailboxId';
      final ensured = await ToneStorage.ensureExternallyAccessibleToneUri(
        key: key,
        uri: toneUri,
        fileNameHint: toneName,
      );
      if (ensured != null && ensured.trim().isNotEmpty) {
        desiredSoundUri = _toAndroidSoundUri(ensured);
      }
    }

    final hasCustomSound =
        desiredSoundUri != null && desiredSoundUri.trim().isNotEmpty;

    // Android won't let us change a channel's sound once created. Use a
    // different channel id when a custom tone is configured.
    final channelId = hasCustomSound
        ? _customChannelIdForMailbox(mailboxId, desiredSoundUri.trim())
        : _channelIdForMailbox(mailboxId);
    _channelIdByMailbox[mailboxId] = channelId;

    final existing = channelById == null ? null : channelById[channelId];
    if (existing != null && !hasCustomSound) {
      // Respect user/system overrides for the default (non-custom) channel.
      return;
    }

    final needsCreate = existing == null;
    final needsUpdate = hasCustomSound &&
        (existing?.playSound != true ||
            !_soundMatches(existing?.sound, desiredSoundUri));
    if (!needsCreate && !needsUpdate) return;

    // Avoid repeatedly deleting/recreating channels when Android refuses to
    // apply a requested sound. We'll try once per (channelId, soundUri) combo
    // per app run.
    if (existing != null && needsUpdate) {
      final attemptKey = '$channelId|$desiredSoundUri';
      if (_attemptedChannelSoundUpdate.contains(attemptKey)) return;
      _attemptedChannelSoundUpdate.add(attemptKey);
    }

    // `createNotificationChannel()` won't update the sound if the channel
    // already exists (Android restriction). Prefer deleting first when we know
    // we need a custom sound. If we couldn't fetch existing channels
    // (`channelById == null`), we still delete as a best-effort because the
    // channel may exist even though we couldn't enumerate it.
    final shouldAttemptDelete =
        (existing != null) || (hasCustomSound && channelById == null);
    if (shouldAttemptDelete) {
      try {
        await android.deleteNotificationChannel(channelId);
      } catch (_) {}
      channelById?.remove(channelId);
    }

    final titleRaw = chat.title.trim();
    final chatTitle = titleRaw.isEmpty ? ChatStore.defaultChatTitle : titleRaw;

    final created = AndroidNotificationChannel(
      channelId,
      'Messages: $chatTitle',
      description: 'New messages in $chatTitle',
      importance: Importance.high,
      playSound: true,
      sound: desiredSoundUri == null || desiredSoundUri.trim().isEmpty
          ? null
          : UriAndroidNotificationSound(desiredSoundUri),
      audioAttributesUsage: AudioAttributesUsage.notification,
    );

    await android.createNotificationChannel(created);
    channelById?[channelId] = created;
  }

  static Future<void> _ensureChannelsForKnownChats({
    AndroidFlutterLocalNotificationsPlugin? android,
    Map<String, AndroidNotificationChannel>? channelById,
  }) async {
    if (!Platform.isAndroid) return;
    final resolvedAndroid = android ??
        _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (resolvedAndroid == null) return;

    final chats = ChatStore.chats;
    for (final chat in chats) {
      try {
        await _ensureChannelForChatInternal(
          resolvedAndroid,
          chat,
          channelById: channelById,
        );
      } catch (_) {}
    }
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = (response.payload ?? '').trim();
        if (payload.isEmpty) return;
        if (_tryHandleCallNotificationResponse(payload, response.actionId)) {
          return;
        }
        unawaited(_handleMailboxOpen(payload));
      },
    );

    // If the app was cold-started from tapping a local notification, honor the
    // payload and deep-link into the thread once the navigator is ready.
    try {
      final details = await _localNotifications.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = (details?.notificationResponse?.payload ?? '').trim();
        if (payload.isNotEmpty) {
          if (!_tryHandleCallNotificationResponse(
            payload,
            details?.notificationResponse?.actionId,
          )) {
            unawaited(_handleMailboxOpen(payload));
          }
        }
      }
    } catch (_) {}

    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _defaultChannelId,
        'Messages',
        description: 'New messages',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _callChannelId,
        'Calls',
        description: 'Incoming calls',
        importance: Importance.max,
      ),
    );
  }

  static Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _onMessageSub = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationOpen,
    );
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      _scheduleResync();
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleNotificationOpen(initial);
    }
  }

  static Future<bool> _requestAndroidNotificationPermission() async {
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
    final id = (data['mailbox_id'] ?? data['mailboxId'] ?? '')
        .toString()
        .trim();
    return id;
  }

  static String _envelopeIdFromMessage(RemoteMessage message) {
    final data = message.data;
    final id = (data['envelope_id'] ?? data['envelopeId'] ?? '')
        .toString()
        .trim();
    return id;
  }

  static String _senderIdFromMessage(RemoteMessage message) {
    final data = message.data;
    final id = (data['senderId'] ?? data['sender_id'] ?? '').toString().trim();
    return id;
  }

  static String _senderNameFromMessage(RemoteMessage message) {
    final data = message.data;
    final raw =
        (data['senderName'] ?? data['sender_name'] ?? data['sender'] ?? '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;

    final senderId = _senderIdFromMessage(message);
    if (senderId.isEmpty) return '';

    for (final c in ContactsStore.contacts) {
      if (c.id.trim() == senderId) {
        final name = c.displayName.trim();
        return name.isEmpty ? '' : name;
      }
    }

    return '';
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final type = (message.data['type'] ?? '').toString().trim();
    if (type == 'incoming_call') {
      await _handleIncomingCallForeground(message);
      return;
    }

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

    final senderName = _senderNameFromMessage(message);
    final title = senderName.isNotEmpty ? senderName : 'New message';

    // Enforce local privacy preferences. If previews are off locally, never
    // display remote notification bodies that might contain message text.
    String body;
    if (PushStore.showPreview) {
      final notifBody = message.notification?.body?.trim() ?? '';
      body = notifBody.isNotEmpty ? notifBody : 'New message';
    } else {
      body = 'New message';
    }

    // Make sure the per-thread channel exists before we show anything.
    for (final c in ChatStore.chats) {
      if (c.id == mailboxId) {
        await _ensureChannelForChat(c);
        break;
      }
    }

    await _showLocalNotification(
      mailboxId: mailboxId,
      title: title,
      body: body,
    );
  }

  static void _handleNotificationOpen(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString().trim();
    if (type == 'incoming_call') {
      final data = message.data;
      final callId = (data['callId'] ?? data['call_id'] ?? '').toString().trim();
      final mailboxId =
          (data['mailboxId'] ?? data['mailbox_id'] ?? '').toString().trim();
      final callerId =
          (data['callerId'] ?? data['caller_id'] ?? data['senderId'] ?? data['sender_id'] ?? '')
              .toString()
              .trim();
      final callerName =
          (data['callerName'] ?? data['caller_name'] ?? data['senderName'] ?? data['sender_name'] ?? '')
              .toString()
              .trim();
      if (callId.isNotEmpty && mailboxId.isNotEmpty && callerId.isNotEmpty) {
        CallService.openIncomingCallFromNotification(
          callId: callId,
          mailboxId: mailboxId,
          callerId: callerId,
          callerName: callerName,
        );
      }
      return;
    }

    final mailboxId = _mailboxIdFromMessage(message);
    if (mailboxId.isEmpty) return;
    unawaited(_handleMailboxOpen(mailboxId));
  }

  static Future<void> _handleIncomingCallForeground(RemoteMessage message) async {
    final data = message.data;
    final callId = (data['callId'] ?? data['call_id'] ?? '').toString().trim();
    final mailboxId =
        (data['mailboxId'] ?? data['mailbox_id'] ?? '').toString().trim();
    final callerId = (data['callerId'] ??
            data['caller_id'] ??
            data['senderId'] ??
            data['sender_id'] ??
            '')
        .toString()
        .trim();
    final callerName = (data['callerName'] ??
            data['caller_name'] ??
            data['senderName'] ??
            data['sender_name'] ??
            '')
        .toString()
        .trim();

    if (callId.isEmpty || mailboxId.isEmpty || callerId.isEmpty) return;

    final showUiImmediately = !SecurityStore.isLocked;
    final ok = await CallService.handleIncomingCallPush(
      callId: callId,
      mailboxId: mailboxId,
      callerId: callerId,
      callerName: callerName,
      showUiImmediately: showUiImmediately,
    );

    if (ok && !showUiImmediately) {
      await _showIncomingCallNotification(
        callId: callId,
        mailboxId: mailboxId,
        callerId: callerId,
        callerName: callerName,
      );
    }
  }

  static Future<void> _handleMailboxOpen(String mailboxId) async {
    final id = mailboxId.trim();
    if (id.isEmpty) return;

    _pendingMailboxId = id;

    // Optional privacy hardening: require unlocking the app before deep-linking
    // into a chat from a notification tap.
    if (PushStore.requireUnlockOnNotificationOpen && !SecurityStore.isLocked) {
      try {
        final hasPin = await SecurityStore.hasPin();
        if (hasPin) {
          await SecurityStore.lock();
        }
      } catch (_) {}
    }

    _schedulePendingOpen();
  }

  static void _handleLockStateChanged() {
    if (SecurityStore.isLocked) return;
    _tryOpenPendingMailbox();
  }

  static void _schedulePendingOpen() {
    if (_pendingOpenTimer != null) return;
    _pendingOpenTimer = Timer(const Duration(milliseconds: 150), () {
      _pendingOpenTimer = null;
      _tryOpenPendingMailbox();
    });
  }

  static void _tryOpenPendingMailbox() {
    final pending = (_pendingMailboxId ?? '').trim();
    if (pending.isEmpty) return;
    if (SecurityStore.isLocked) return;
    if (!IdentityStore.usernameCustom) return;

    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      _pendingOpenAttempts++;
      if (_pendingOpenAttempts > 40) return;
      _schedulePendingOpen();
      return;
    }

    _pendingOpenAttempts = 0;
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

  static bool _tryHandleCallNotificationResponse(
    String payload,
    String? actionId,
  ) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return false;

    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return false;
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return false;
    }

    if ((map['t'] ?? '').toString().trim() != 'call') return false;

    final callId = (map['callId'] ?? map['call_id'] ?? '').toString().trim();
    final mailboxId =
        (map['mailboxId'] ?? map['mailbox_id'] ?? '').toString().trim();
    final callerId =
        (map['callerId'] ?? map['caller_id'] ?? '').toString().trim();
    final callerName =
        (map['callerName'] ?? map['caller_name'] ?? '').toString().trim();

    if (callId.isEmpty || mailboxId.isEmpty || callerId.isEmpty) return true;

    unawaited(
      _handleCallNotificationOpen(
        actionId: (actionId ?? '').trim(),
        callId: callId,
        mailboxId: mailboxId,
        callerId: callerId,
        callerName: callerName,
      ),
    );
    return true;
  }

  static Future<void> _handleCallNotificationOpen({
    required String actionId,
    required String callId,
    required String mailboxId,
    required String callerId,
    required String callerName,
  }) async {
    // Privacy: default to requiring unlock before entering a call from a notif tap.
    if (PushStore.requireUnlockOnNotificationOpen && !SecurityStore.isLocked) {
      try {
        final hasPin = await SecurityStore.hasPin();
        if (hasPin) {
          await SecurityStore.lock();
        }
      } catch (_) {}
    }

    if (actionId == 'decline_call') {
      final ok = await CallService.handleIncomingCallPush(
        callId: callId,
        mailboxId: mailboxId,
        callerId: callerId,
        callerName: callerName,
        showUiImmediately: false,
      );
      if (ok) {
        await CallService.declineIncoming();
      }
      return;
    }

    CallService.openIncomingCallFromNotification(
      callId: callId,
      mailboxId: mailboxId,
      callerId: callerId,
      callerName: callerName,
    );
  }

  static Future<void> _showIncomingCallNotification({
    required String callId,
    required String mailboxId,
    required String callerId,
    required String callerName,
  }) async {
    final id = _callNotificationId(callId);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _callChannelId,
        'Calls',
        channelDescription: 'Incoming calls',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        timeoutAfter: 45000,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'decline_call',
            'Decline',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'answer_call',
            'Answer',
            showsUserInterface: true,
            cancelNotification: true,
            semanticAction: SemanticAction.call,
          ),
        ],
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      ),
    );

    await _localNotifications.show(
      id,
      'Incoming call',
      callerName.trim().isEmpty ? 'Unknown caller' : callerName.trim(),
      details,
      payload: _encodeCallPayload(
        callId: callId,
        mailboxId: mailboxId,
        callerId: callerId,
        callerName: callerName,
      ),
    );
  }

  static Future<void> _showLocalNotification({
    required String mailboxId,
    required String title,
    required String body,
  }) async {
    final channelId =
        _channelIdByMailbox[mailboxId] ?? _channelIdForMailbox(mailboxId);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Messages',
        channelDescription: 'New messages',
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

  static void _cancelRetry() {
    _syncRetryTimer?.cancel();
    _syncRetryTimer = null;
    _retrySeconds = 15;
  }

  static void _scheduleRetry() {
    if (!_initialized) return;
    if (!PushStore.enabled) return;

    _syncRetryTimer?.cancel();
    final delay = _retrySeconds.clamp(15, 300);
    _syncRetryTimer = Timer(Duration(seconds: delay), () {
      _scheduleResync();
    });

    // Exponential-ish backoff capped at 5 minutes.
    _retrySeconds = (_retrySeconds * 2).clamp(15, 300);
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
    var allOk = true;
    try {
      if (!Platform.isAndroid) return;

      // Keep notification channels in sync with chat tones/mutes.
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      Map<String, AndroidNotificationChannel>? channelById;
      if (android != null) {
        try {
          final channels =
              await android.getNotificationChannels() ??
              <AndroidNotificationChannel>[];
          channelById = <String, AndroidNotificationChannel>{
            for (final c in channels) c.id: c,
          };
        } catch (_) {
          channelById = null;
        }
      }
      await _ensureChannelsForKnownChats(android: android, channelById: channelById);

      final deviceId = IdentityStore.publicId.trim();
      if (deviceId.isEmpty) return;

      final chats = ChatStore.chats;
      final mailboxIds = chats
          .map((c) => c.id.trim())
          .where((id) => id.isNotEmpty)
          .toList();

      if (!PushStore.enabled) {
        for (final mailboxId in mailboxIds) {
          final ok = await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
          allOk = allOk && ok;
        }
        if (allOk) {
          _cancelRetry();
        } else {
          _scheduleRetry();
        }
        return;
      }

      final permissionOk = await _requestAndroidNotificationPermission();
      if (!permissionOk) {
        await PushStore.setEnabled(false);
        for (final mailboxId in mailboxIds) {
          final ok = await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
          allOk = allOk && ok;
        }
        _cancelRetry();
        return;
      }

      final fcmToken =
          (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
      if (fcmToken.isEmpty) {
        _scheduleRetry();
        return;
      }

      final muted = PushStore.mutedMailboxes;
      for (final mailboxId in mailboxIds) {
        if (muted.contains(mailboxId)) {
          final ok = await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
          allOk = allOk && ok;
          continue;
        }

        final ok = await RelayClient.registerPush(
          mailboxId: mailboxId,
          deviceId: deviceId,
          platform: 'android',
          fcmToken: fcmToken,
          notifyOnNewMessages: PushStore.notifyOnNewMessages,
          showPreview: PushStore.showPreview,
          androidChannelId: _channelIdByMailbox[mailboxId] ??
              _channelIdForMailbox(mailboxId),
        );
        allOk = allOk && ok;
      }

      if (allOk) {
        _cancelRetry();
      } else {
        _scheduleRetry();
      }
    } catch (error) {
      debugPrint('[Push] sync failed: $error');
      _scheduleRetry();
    } finally {
      _syncInProgress = false;
      if (_needsResync) {
        _needsResync = false;
        await _syncRegistrations();
      }
    }
  }

  static Future<void> dispose() async {
    _syncRetryTimer?.cancel();
    _syncRetryTimer = null;
    await _onMessageSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedSub = null;
    _tokenRefreshSub = null;
  }
}
