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
import '../../state/chat_unread_store.dart';
import '../../state/chat_appearance_store.dart';
import '../../state/contact_appearance_store.dart';
import '../../state/contacts_store.dart';
import '../../state/identity_store.dart';
import '../../state/message_store.dart';
import '../../state/push_store.dart';
import '../../state/push_runtime_store.dart';
import '../../state/security_store.dart';
import '../../state/vault_store.dart';
import '../ui/desktop_overlay_card.dart';
import '../relay/relay_client.dart';
import '../tones/tone_storage.dart';
import 'push_background_handler.dart';
import '../calls/call_service.dart';
import '../vault/direct_thread_routing.dart';

class PushService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _initialized = false;

  static const String _defaultChannelId = 'cc_messages';
  static const String _callChannelId = 'cc_calls';
  static const String _callCategoryId = 'cc_calls_actions';
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

  static String _encodeMessagePayload({
    required String mailboxId,
    required String senderId,
    required String senderName,
    String? threadChatId,
  }) {
    return jsonEncode(<String, dynamic>{
      't': 'message',
      'mailboxId': mailboxId,
      'senderId': senderId,
      'senderName': senderName,
      'threadChatId': (threadChatId ?? '').trim(),
    });
  }

  static void resync() {
    _scheduleResync();
  }

  static Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    await _initLocalNotifications();
    if (!Platform.isAndroid && !Platform.isIOS) {
      PushRuntimeStore.setFirebaseReady(
        false,
        status: 'Not used on this platform',
      );
      PushRuntimeStore.setPermissionStatus('Not used on this platform');
      PushRuntimeStore.setApnsStatus('Not used on this platform');
      PushRuntimeStore.setFcmStatus('Not used on this platform');
      return;
    }
    try {
      await _initFirebaseMessaging();
    } catch (error) {
      debugPrint('[Push] Firebase messaging init failed: $error');
      PushRuntimeStore.setFirebaseReady(false, status: 'Messaging unavailable');
      PushRuntimeStore.markRelayFailure(
        'Push runtime unavailable',
        error: 'Firebase Messaging init failed: $error',
      );
    }

    PushRuntimeStore.setPermissionStatus('Not requested');
    if (Platform.isIOS) {
      PushRuntimeStore.setApnsStatus('Waiting for APNs token');
    } else {
      PushRuntimeStore.setApnsStatus('Not used on Android');
    }
    PushRuntimeStore.setFcmStatus('Waiting for FCM token');

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

    await _ensureChannelForChatInternal(
      android,
      chat,
      channelById: channelById,
    );
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
    final needsUpdate =
        hasCustomSound &&
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
    final resolvedAndroid =
        android ??
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
    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: false,
      defaultPresentBadge: false,
      defaultPresentSound: false,
      defaultPresentBanner: false,
      defaultPresentList: false,
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          _callCategoryId,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              'decline_call',
              'Decline',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.destructive,
              },
            ),
            DarwinNotificationAction.plain(
              'answer_call',
              'Answer',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    );
    const windowsInit = WindowsInitializationSettings(
      appName: 'The Vault',
      appUserModelId: 'VarnokSystemsLLC.TheVault',
      guid: '24564ba2-857a-4ba9-b998-b31f2b87cb42',
    );
    final settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      windows: windowsInit,
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = (response.payload ?? '').trim();
        if (payload.isEmpty) return;
        if (_tryHandleCallNotificationResponse(payload, response.actionId)) {
          return;
        }
        if (_tryHandleMessageNotificationResponse(payload)) {
          return;
        }
        if (!payload.startsWith('{')) {
          unawaited(_handleMailboxOpen(payload));
        }
      },
    );

    // If the app was cold-started from tapping a local notification, honor the
    // payload and deep-link into the thread once the navigator is ready.
    try {
      final details = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = (details?.notificationResponse?.payload ?? '').trim();
        if (payload.isNotEmpty) {
          if (!_tryHandleCallNotificationResponse(
            payload,
            details?.notificationResponse?.actionId,
          )) {
            if (!_tryHandleMessageNotificationResponse(payload)) {
              if (!payload.startsWith('{')) {
                unawaited(_handleMailboxOpen(payload));
              }
            }
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

    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
    }

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

  static Future<bool> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return true;
      try {
        final granted = await android.requestNotificationsPermission();
        final allowed = granted ?? true;
        PushRuntimeStore.setPermissionStatus(
          allowed ? 'Allowed' : 'Denied by user',
        );
        return allowed;
      } catch (_) {
        PushRuntimeStore.setPermissionStatus('Allowed');
        return true;
      }
    }

    if (Platform.isIOS) {
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        try {
          await _localNotifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
        } catch (_) {}
        final authorized =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
        final label = switch (settings.authorizationStatus) {
          AuthorizationStatus.authorized => 'Allowed',
          AuthorizationStatus.provisional => 'Provisional',
          AuthorizationStatus.denied => 'Denied by user',
          AuthorizationStatus.notDetermined => 'Not determined',
        };
        PushRuntimeStore.setPermissionStatus(label);
        return authorized;
      } catch (_) {
        PushRuntimeStore.setPermissionStatus('Request failed');
        return false;
      }
    }

    return true;
  }

  static String _mailboxIdFromMessage(RemoteMessage message) {
    return _mailboxIdFromMap(message.data);
  }

  static String _mailboxIdFromMap(Map<Object?, Object?> data) {
    final id =
        (data['mailbox_id'] ??
                data['mailboxId'] ??
                data['vault_mailbox'] ??
                data['vaultMailbox'] ??
                data['signal_mailbox'] ??
                data['signalMailbox'] ??
                '')
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
    final id =
        (data['senderId'] ??
                data['sender_id'] ??
                data['from_user_id'] ??
                data['fromUserId'] ??
                data['device_id'] ??
                data['deviceId'] ??
                '')
            .toString()
            .trim();
    return id;
  }

  static String _routingSenderIdFromMap(Map<Object?, Object?> data) {
    return (data['senderId'] ??
            data['sender_id'] ??
            data['from_user_id'] ??
            data['fromUserId'] ??
            '')
        .toString()
        .trim();
  }

  static String _senderNameFromMessage(RemoteMessage message) {
    final data = message.data;
    final raw =
        (data['senderName'] ??
                data['sender_name'] ??
                data['sender'] ??
                data['displayName'] ??
                data['display_name'] ??
                '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;

    final senderId = _routingSenderIdFromMap(data);
    if (senderId.isEmpty) return '';

    for (final c in ContactsStore.contacts) {
      if (c.id.trim() == senderId) {
        final name = c.displayName.trim();
        return name.isEmpty ? '' : name;
      }
    }

    return '';
  }

  static String _threadChatIdFromMessage(RemoteMessage message) {
    final data = message.data;
    return (data['threadChatId'] ?? data['thread_chat_id'] ?? '')
        .toString()
        .trim();
  }

  static String _previewTextFromMessage(RemoteMessage message) {
    final data = message.data;
    const previewKeys = <String>[
      'preview',
      'preview_text',
      'previewText',
      'body',
      'message',
      'message_body',
      'messageBody',
      'text',
      'content',
    ];
    for (final key in previewKeys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    final notificationBody = (message.notification?.body ?? '').trim();
    if (notificationBody.isNotEmpty) return notificationBody;
    return _previewFallbackFromPayload(data);
  }

  static String _previewFallbackFromPayload(Map<Object?, Object?> data) {
    final type =
        (data['type'] ?? data['messageType'] ?? data['message_type'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final mime =
        (data['attachmentMime'] ??
                data['attachment_mime'] ??
                data['mime'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final name = (data['attachmentName'] ?? data['attachment_name'] ?? '')
        .toString()
        .trim();
    if (type == RelayMessage.typeVoice) return 'Voice note';
    if (type == RelayMessage.typeSticker) return 'Sticker';
    if (type == RelayMessage.typeAttachmentChunk || mime.isNotEmpty) {
      if (mime == 'image/gif' ||
          mime.endsWith('/gif') ||
          name.toLowerCase().endsWith('.gif')) {
        return 'GIF';
      }
      if (mime.startsWith('image/')) return 'Photo';
      if (mime.startsWith('video/')) return 'Video';
      return name.isEmpty ? 'Attachment' : name;
    }
    return 'New message';
  }

  static bool _isNonMessageNotificationEvent(Map<Object?, Object?> data) {
    const eventKeys = <String>[
      'type',
      'event',
      'kind',
      'messageType',
      'message_type',
      'receiptKind',
      'receipt_kind',
    ];
    const ignoreValues = <String>{
      'receipt',
      'read_receipt',
      'delivery_receipt',
      'delivered',
      'open',
      'message_open',
      'opened',
      'read',
      'seen',
      'ack',
      'acknowledged',
    };

    for (final key in eventKeys) {
      final value = (data[key] ?? '').toString().trim().toLowerCase();
      if (value.isEmpty) continue;
      if (value == 'incoming_call' || value == 'message') continue;
      if (ignoreValues.contains(value) ||
          value.contains('receipt') ||
          value.contains('open') ||
          value.contains('read') ||
          value.contains('seen') ||
          value.contains('delivered') ||
          value.contains('ack')) {
        return true;
      }
    }

    for (final key in data.keys) {
      final normalized = key.toString().trim().toLowerCase();
      if (normalized == 'receiptkind' ||
          normalized == 'receiptmessageid' ||
          normalized == 'receipt_message_id' ||
          normalized == 'openmessageid' ||
          normalized == 'open_message_id' ||
          normalized == 'openedmessageid' ||
          normalized == 'opened_message_id') {
        return true;
      }
    }

    return false;
  }

  static bool _isLikelyMessageNotification(RemoteMessage message) {
    final data = message.data;
    if (_isNonMessageNotificationEvent(data)) return false;
    final type =
        (data['type'] ?? data['messageType'] ?? data['message_type'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (type == 'incoming_call') return false;
    if (_mailboxIdFromMessage(message).isEmpty) return false;
    if (type == 'message' ||
        type == RelayMessage.typeText ||
        type == RelayMessage.typeVoice ||
        type == RelayMessage.typeSticker ||
        type == RelayMessage.typeAttachmentChunk ||
        type == RelayMessage.typeAttachmentManifest ||
        type == 'attachment') {
      return true;
    }
    if (_senderIdFromMessage(message).isNotEmpty ||
        _routingSenderIdFromMap(data).isNotEmpty ||
        _senderNameFromMessage(message).isNotEmpty) {
      return true;
    }
    final preview = _previewTextFromMessage(message);
    if (preview.isNotEmpty && preview != 'New message') {
      return true;
    }
    return (message.notification?.title ?? '').trim().isNotEmpty ||
        (message.notification?.body ?? '').trim().isNotEmpty;
  }

  static bool _isSelfNotification({
    required String mailboxId,
    required String senderId,
    required String envelopeId,
  }) {
    final myUserId = IdentityStore.publicId.trim();
    final myDeviceId = VaultStore.localAddress?.deviceId.toString();
    final cleanSenderId = senderId.trim();
    if (cleanSenderId.isNotEmpty &&
        (cleanSenderId == myUserId ||
            (myDeviceId != null && cleanSenderId == myDeviceId))) {
      return true;
    }

    final cleanEnvelopeId = envelopeId.trim();
    if (cleanEnvelopeId.isEmpty) return false;
    return MessageStore.messages.any((message) {
      if (message.id != cleanEnvelopeId) return false;
      final localSenderId = message.senderId.trim();
      return localSenderId == 'local' ||
          localSenderId == myUserId ||
          (myDeviceId != null && localSenderId == myDeviceId);
    });
  }

  static Future<String> _resolveTargetMailboxId({
    required String mailboxId,
    String? senderId,
    String? senderName,
  }) async {
    var targetMailboxId = mailboxId.trim();
    if (targetMailboxId.isEmpty) return '';

    final cleanSenderId = (senderId ?? '').trim();
    final resolvedMailboxId = _resolveNotificationMailboxId(
      mailboxId: targetMailboxId,
      senderId: cleanSenderId,
    );
    if (resolvedMailboxId.isNotEmpty) {
      targetMailboxId = resolvedMailboxId;
    }

    final wantsDirectChat =
        cleanSenderId.isNotEmpty &&
        targetMailboxId == ChatStore.directChatIdForContact(cleanSenderId);

    if (wantsDirectChat) {
      return resolveIncomingVaultChatId(
        rawChatId: targetMailboxId,
        directPeerHint: cleanSenderId,
        senderId: cleanSenderId,
        senderName: (senderName ?? '').trim(),
        fallbackChatId: targetMailboxId,
      );
    }

    return targetMailboxId;
  }

  static String _resolveNotificationMailboxId({
    required String mailboxId,
    String? senderId,
  }) {
    final targetMailboxId = mailboxId.trim();
    if (targetMailboxId.isEmpty) return '';
    if (targetMailboxId.startsWith('direct:')) return targetMailboxId;

    final deviceMailboxId = VaultStore.deviceMailboxId.trim();
    final cleanSenderId = (senderId ?? '').trim();
    final myUserId = IdentityStore.publicId.trim();

    if (deviceMailboxId.isNotEmpty &&
        targetMailboxId == deviceMailboxId &&
        cleanSenderId.isNotEmpty &&
        cleanSenderId != myUserId) {
      return ChatStore.directChatIdForContact(cleanSenderId);
    }

    return targetMailboxId;
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final type = (message.data['type'] ?? '').toString().trim();
    if (type == 'incoming_call') {
      await _handleIncomingCallForeground(message);
      return;
    }
    if (!_isLikelyMessageNotification(message)) return;

    if (!PushStore.enabled) return;
    if (!PushStore.notifyOnNewMessages) return;

    final senderId = _senderIdFromMessage(message);
    final routingSenderId = _routingSenderIdFromMap(message.data);
    final effectiveSenderId = routingSenderId.isNotEmpty
        ? routingSenderId
        : senderId;
    final senderName = _senderNameFromMessage(message);
    final rawMailboxId = _mailboxIdFromMessage(message);
    if (rawMailboxId.isEmpty) return;
    final threadChatId = _threadChatIdFromMessage(message);
    final envelopeId = _envelopeIdFromMessage(message);
    if (_isSelfNotification(
      mailboxId: rawMailboxId,
      senderId: effectiveSenderId,
      envelopeId: envelopeId,
    )) {
      return;
    }

    if (envelopeId.isNotEmpty) {
      final isNew = await PushStore.rememberEnvelopeId(envelopeId);
      if (!isNew) return;
    }

    final mailboxId = await _resolveTargetMailboxId(
      mailboxId: rawMailboxId,
      senderId: routingSenderId,
      senderName: senderName,
    );
    if (mailboxId.isEmpty) return;
    if (PushStore.isMuted(mailboxId)) return;
    if (ChatUnreadStore.isChatOpen(mailboxId)) return;

    final title = senderName.isNotEmpty
        ? senderName
        : (() {
            final notificationTitle = (message.notification?.title ?? '')
                .trim();
            return notificationTitle.isNotEmpty
                ? notificationTitle
                : 'New message';
          })();

    // Enforce local privacy preferences. If previews are off locally, never
    // display remote notification bodies that might contain message text.
    String body;
    if (PushStore.showPreview) {
      final preview = _previewTextFromMessage(message);
      body = preview.isNotEmpty ? preview : 'New message';
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
      senderId: routingSenderId,
      senderName: senderName,
      threadChatId: threadChatId.isNotEmpty ? threadChatId : mailboxId,
    );
  }

  static void _handleNotificationOpen(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString().trim();
    if (type == 'incoming_call') {
      final data = message.data;
      final callId = (data['callId'] ?? data['call_id'] ?? '')
          .toString()
          .trim();
      final mailboxId = _mailboxIdFromMap(data);
      final callerId =
          (data['callerId'] ??
                  data['caller_id'] ??
                  data['senderId'] ??
                  data['sender_id'] ??
                  '')
              .toString()
              .trim();
      final callerName =
          (data['callerName'] ??
                  data['caller_name'] ??
                  data['senderName'] ??
                  data['sender_name'] ??
                  '')
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
    if (!_isLikelyMessageNotification(message)) return;

    final mailboxId = _mailboxIdFromMessage(message);
    if (mailboxId.isEmpty) return;
    final threadChatId = _threadChatIdFromMessage(message);
    unawaited(
      _openMailboxForMessage(
        mailboxId: mailboxId,
        senderId: _routingSenderIdFromMap(message.data),
        senderName: _senderNameFromMessage(message),
        targetChatId: threadChatId.isNotEmpty ? threadChatId : null,
      ),
    );
  }

  static bool _tryHandleMessageNotificationResponse(String payload) {
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

    if ((map['t'] ?? '').toString().trim() != 'message') return false;

    final mailboxId = _mailboxIdFromMap(map);
    final threadChatId = (map['threadChatId'] ?? map['thread_chat_id'] ?? '')
        .toString()
        .trim();
    final senderId = (map['senderId'] ?? map['sender_id'] ?? '')
        .toString()
        .trim();
    final senderName = (map['senderName'] ?? map['sender_name'] ?? '')
        .toString()
        .trim();
    if (mailboxId.isEmpty) return true;

    unawaited(
      _openMailboxForMessage(
        mailboxId: mailboxId,
        senderId: senderId,
        senderName: senderName,
        targetChatId: threadChatId,
      ),
    );
    return true;
  }

  static Future<void> _openMailboxForMessage({
    required String mailboxId,
    String? senderId,
    String? senderName,
    String? targetChatId,
  }) async {
    final requestedChatId = (targetChatId ?? '').trim();
    final needsResolution =
        requestedChatId.isEmpty ||
        (requestedChatId.startsWith('direct:') &&
            ChatStore.getChat(requestedChatId) == null);
    final resolvedChatId = needsResolution
        ? await _resolveTargetMailboxId(
            mailboxId: mailboxId,
            senderId: senderId,
            senderName: senderName,
          )
        : requestedChatId;
    if (resolvedChatId.isEmpty) return;

    await _cancelMessageNotification(mailboxId);
    if (resolvedChatId != mailboxId) {
      await _cancelMessageNotification(resolvedChatId);
    }
    await _handleMailboxOpen(resolvedChatId);
  }

  static Future<void> _handleIncomingCallForeground(
    RemoteMessage message,
  ) async {
    final data = message.data;
    final callId = (data['callId'] ?? data['call_id'] ?? '').toString().trim();
    final mailboxId = _mailboxIdFromMap(data);
    final callerId =
        (data['callerId'] ??
                data['caller_id'] ??
                data['senderId'] ??
                data['sender_id'] ??
                '')
            .toString()
            .trim();
    final callerName =
        (data['callerName'] ??
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
    unawaited(_cancelMessageNotification(mailboxId));
    if (ChatUnreadStore.isChatOpen(mailboxId)) return;
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    final navContext = nav.context;

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
      if (useDesktopOverlayCards(navContext)) {
        pushOrPresentDesktopCard<void>(
          navContext,
          settings: RouteSettings(name: '/thread/$mailboxId'),
          maxWidth: 980,
          builder: (_) => ThreadScreen(
            chatId: mailboxId,
            chatTitle: title,
            contactId: contactId,
          ),
        );
        return;
      }

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

  static Future<void> _cancelMessageNotification(String mailboxId) async {
    final cleanMailboxId = mailboxId.trim();
    if (cleanMailboxId.isEmpty) return;
    try {
      await _localNotifications.cancel(
        _notificationIdForMailbox(cleanMailboxId),
      );
    } catch (_) {}
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
    final mailboxId = _mailboxIdFromMap(map);
    final callerId = (map['callerId'] ?? map['caller_id'] ?? '')
        .toString()
        .trim();
    final callerName = (map['callerName'] ?? map['caller_name'] ?? '')
        .toString()
        .trim();

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
      iOS: DarwinNotificationDetails(
        categoryIdentifier: _callCategoryId,
        interruptionLevel: InterruptionLevel.active,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        threadIdentifier: mailboxId,
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
    String? senderId,
    String? senderName,
    String? threadChatId,
  }) async {
    final channelId =
        _channelIdByMailbox[mailboxId] ?? _channelIdForMailbox(mailboxId);
    final safeBody = PushStore.showPreview
        ? (body.trim().isEmpty ? 'New message' : body.trim())
        : 'New message';
    final payload = _encodeMessagePayload(
      mailboxId: mailboxId,
      senderId: (senderId ?? '').trim(),
      senderName: (senderName ?? '').trim(),
      threadChatId: threadChatId,
    );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Messages',
        channelDescription: 'New messages',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        number: ChatUnreadStore.totalUnread > 0
            ? ChatUnreadStore.totalUnread
            : null,
      ),
      iOS: DarwinNotificationDetails(
        presentBanner: true,
        presentList: true,
        presentSound: true,
        threadIdentifier: mailboxId,
      ),
      windows: const WindowsNotificationDetails(),
    );
    await _localNotifications.show(
      _notificationIdForMailbox(mailboxId),
      title,
      safeBody,
      details,
      payload: payload,
    );
  }

  static Future<void> showDesktopMessageNotification({
    required String mailboxId,
    required String title,
    required String body,
    String? senderId,
    String? senderName,
    String? threadChatId,
  }) async {
    if (!_initialized || !Platform.isWindows) return;
    await _showLocalNotification(
      mailboxId: mailboxId,
      title: title,
      body: body,
      senderId: senderId,
      senderName: senderName,
      threadChatId: threadChatId,
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
      if (!Platform.isAndroid && !Platform.isIOS) return;
      PushRuntimeStore.markSyncStarted();

      if (!PushRuntimeStore.firebaseReady) {
        PushRuntimeStore.markRelayFailure(
          'Firebase unavailable',
          error: 'Firebase is not initialized for this build.',
        );
        return;
      }

      // Keep notification channels in sync with chat tones/mutes.
      if (Platform.isAndroid) {
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
        await _ensureChannelsForKnownChats(
          android: android,
          channelById: channelById,
        );
      }

      final deviceId = IdentityStore.publicId.trim();
      if (deviceId.isEmpty) {
        PushRuntimeStore.markRelayFailure(
          'Local identity missing',
          error: 'No local device identity is available yet.',
        );
        return;
      }

      final chats = ChatStore.chats;
      final mailboxIds = <String>{
        for (final chat in chats)
          if (chat.id.trim().isNotEmpty) chat.id.trim(),
      };
      final deviceMailboxId = VaultStore.deviceMailboxId.trim();
      if (deviceMailboxId.isNotEmpty) {
        mailboxIds.add(deviceMailboxId);
      }
      final mailboxIdList = mailboxIds.toList(growable: false);

      if (!PushStore.enabled) {
        for (final mailboxId in mailboxIdList) {
          final ok = await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
          allOk = allOk && ok;
        }
        if (allOk) {
          _cancelRetry();
          PushRuntimeStore.markRelaySuccess('Push disabled locally');
        } else {
          _scheduleRetry();
          PushRuntimeStore.markRelayFailure('Failed to disable push cleanly');
        }
        return;
      }

      final permissionOk = await _requestNotificationPermission();
      if (!permissionOk) {
        await PushStore.setEnabled(false);
        for (final mailboxId in mailboxIdList) {
          final ok = await RelayClient.unregisterPush(
            mailboxId: mailboxId,
            deviceId: deviceId,
          );
          allOk = allOk && ok;
        }
        _cancelRetry();
        PushRuntimeStore.markRelayFailure(
          'Notifications denied',
          error: 'Notification permission is required for push on this device.',
        );
        return;
      }

      if (Platform.isIOS) {
        final apnsToken =
            (await FirebaseMessaging.instance.getAPNSToken())?.trim() ?? '';
        if (apnsToken.isEmpty) {
          debugPrint('[Push] APNs token not available yet; retrying sync.');
          PushRuntimeStore.setApnsStatus('Waiting for APNs token');
          PushRuntimeStore.markRelayFailure(
            'Waiting for APNs token',
            error: 'APNs token is not available yet on this iPhone build.',
          );
          _scheduleRetry();
          return;
        }
        PushRuntimeStore.setApnsStatus('Ready');
      }

      final fcmToken =
          (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
      if (fcmToken.isEmpty) {
        PushRuntimeStore.setFcmStatus('Waiting for FCM token');
        PushRuntimeStore.markRelayFailure(
          'Waiting for FCM token',
          error: 'Firebase Messaging token is not available yet.',
        );
        _scheduleRetry();
        return;
      }
      PushRuntimeStore.setFcmStatus('Ready');

      final muted = PushStore.mutedMailboxes;
      for (final mailboxId in mailboxIdList) {
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
          platform: Platform.isIOS ? 'ios' : 'android',
          fcmToken: fcmToken,
          notifyOnNewMessages: PushStore.notifyOnNewMessages,
          showPreview: PushStore.showPreview,
          androidChannelId: Platform.isAndroid
              ? (_channelIdByMailbox[mailboxId] ??
                    _channelIdForMailbox(mailboxId))
              : null,
        );
        allOk = allOk && ok;
      }

      if (allOk) {
        _cancelRetry();
        final targetCount = mailboxIdList
            .where((id) => !muted.contains(id))
            .length;
        PushRuntimeStore.markRelaySuccess(
          targetCount > 0
              ? 'Registered for $targetCount chat${targetCount == 1 ? '' : 's'}'
              : 'No active chat registrations',
        );
      } else {
        _scheduleRetry();
        PushRuntimeStore.markRelayFailure(
          'Relay registration failed',
          error: 'At least one relay push registration request failed.',
        );
      }
    } catch (error) {
      debugPrint('[Push] sync failed: $error');
      PushRuntimeStore.markRelayFailure('Sync failed', error: error.toString());
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
