import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/call_policy_store.dart';
import '../calls/call_signaling.dart';

const String _messageChannelId = 'cc_messages';
const String _callChannelId = 'cc_calls';
const String _callCategoryId = 'cc_calls_actions';
const String _pushEnabledPref = 'cc_push_enabled_v1';
const String _pushNotifyPref = 'cc_push_notify_new_messages_v1';
const String _pushPreviewPref = 'cc_push_show_preview_v1';
const String _pushMutedPref = 'cc_push_muted_mailboxes_v1';
const String _pushRecentEnvelopesPref = 'cc_push_recent_envelope_ids_v1';
const String _chatUnreadPref = 'cc_chat_unread_v1';
const String _messagesPref = 'cc_messages_v1';
const String _localUserIdPref = 'local_user_id';
const String _localUsernamePref = 'local_username';
const String _deviceIdPrefix = 'vault_device_id_';
const String _legacyDeviceIdPrefix = 'signal_device_id_';
const String _deviceMailboxIdPrefix = 'vault_device_mailbox_id_';
const String _legacyDeviceMailboxIdPrefix = 'signal_device_mailbox_id_';

String _mailboxIdFromData(Map<Object?, Object?> data) {
  return (data['mailbox_id'] ??
          data['mailboxId'] ??
          data['vault_mailbox'] ??
          data['vaultMailbox'] ??
          data['signal_mailbox'] ??
          data['signalMailbox'] ??
          '')
      .toString()
      .trim();
}

String _envelopeIdFromData(Map<Object?, Object?> data) {
  return (data['envelope_id'] ?? data['envelopeId'] ?? '').toString().trim();
}

String _senderIdFromData(Map<Object?, Object?> data) {
  return (data['senderId'] ??
          data['sender_id'] ??
          data['from_user_id'] ??
          data['fromUserId'] ??
          data['device_id'] ??
          data['deviceId'] ??
          '')
      .toString()
      .trim();
}

String _routingSenderIdFromData(Map<Object?, Object?> data) {
  return (data['senderId'] ??
          data['sender_id'] ??
          data['from_user_id'] ??
          data['fromUserId'] ??
          '')
      .toString()
      .trim();
}

String _senderNameFromData(Map<Object?, Object?> data) {
  return (data['senderName'] ??
          data['sender_name'] ??
          data['sender'] ??
          data['displayName'] ??
          data['display_name'] ??
          '')
      .toString()
      .trim();
}

String _previewTextFromData(
  Map<Object?, Object?> data, {
  String? notificationBody,
}) {
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
  final body = (notificationBody ?? '').trim();
  if (body.isNotEmpty) return body;
  final type =
      (data['type'] ?? data['messageType'] ?? data['message_type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  final mime =
      (data['attachmentMime'] ?? data['attachment_mime'] ?? data['mime'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  final name = (data['attachmentName'] ?? data['attachment_name'] ?? '')
      .toString()
      .trim();
  if (type == 'voice') return 'Voice note';
  if (type == 'sticker') return 'Sticker';
  if (type == 'attachment_chunk' || mime.isNotEmpty) {
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

bool _isLikelyMessageEvent(
  Map<Object?, Object?> data, {
  String? notificationTitle,
  String? notificationBody,
}) {
  if (_isNonMessageNotificationEvent(data)) return false;
  final type =
      (data['type'] ?? data['messageType'] ?? data['message_type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  if (type == 'incoming_call') return false;
  if (_mailboxIdFromData(data).isEmpty) return false;
  if (type == 'message' ||
      type == 'text' ||
      type == 'voice' ||
      type == 'sticker' ||
      type == 'attachment_chunk' ||
      type == 'attachment_manifest' ||
      type == 'attachment') {
    return true;
  }
  if (_senderIdFromData(data).isNotEmpty ||
      _routingSenderIdFromData(data).isNotEmpty ||
      _senderNameFromData(data).isNotEmpty) {
    return true;
  }
  if (_previewTextFromData(
        data,
        notificationBody: notificationBody,
      ).trim().isNotEmpty &&
      _previewTextFromData(data, notificationBody: notificationBody).trim() !=
          'New message') {
    return true;
  }
  return (notificationTitle ?? '').trim().isNotEmpty ||
      (notificationBody ?? '').trim().isNotEmpty;
}

bool _isNonMessageNotificationEvent(Map<Object?, Object?> data) {
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

int _callNotificationId(String callId) {
  var hash = 0;
  for (final code in callId.codeUnits) {
    hash = ((hash << 5) - hash + code) & 0x7fffffff;
  }
  return hash;
}

int _messageNotificationId(String mailboxId) {
  return mailboxId.hashCode & 0x7fffffff;
}

String _encodeCallPayload({
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

String _encodeMessagePayload({
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
    'thread_chat_id': (threadChatId ?? '').trim(),
  });
}

Future<void> _ensureMessagesChannel(
  FlutterLocalNotificationsPlugin plugin,
) async {
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return;
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      _messageChannelId,
      'Messages',
      description: 'New messages',
      importance: Importance.high,
    ),
  );
}

Future<void> _ensureCallsChannel(FlutterLocalNotificationsPlugin plugin) async {
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return;
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      _callChannelId,
      'Calls',
      description: 'Incoming calls',
      importance: Importance.max,
    ),
  );
}

Future<void> _sendRejectOneShot({
  required String mailboxId,
  required String callId,
  required String deviceId,
  required String displayName,
}) async {
  final client = CallSignalingClient(mailboxId: mailboxId, deviceId: deviceId);
  try {
    await client.connect();
    client.send(<String, dynamic>{
      'type': 'reject',
      'callId': callId,
      'call_id': callId,
      'fromChatId': mailboxId,
      'from_chat_id': mailboxId,
      'toChatId': mailboxId,
      'to_chat_id': mailboxId,
      'senderId': deviceId,
      'sender_id': deviceId,
      'senderName': displayName,
      'sender_name': displayName,
    });
  } catch (_) {
    // ignore
  } finally {
    await client.close();
  }
}

Future<void> _showIncomingCallNotification({
  required FlutterLocalNotificationsPlugin plugin,
  required String callId,
  required String mailboxId,
  required String callerId,
  required String callerName,
}) async {
  await _ensureCallsChannel(plugin);

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

  await plugin.show(
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

Future<void> _showIncomingMessageNotification({
  required FlutterLocalNotificationsPlugin plugin,
  required String mailboxId,
  required String title,
  required String body,
  required String senderId,
  required String senderName,
  int? badgeCount,
  String? threadChatId,
}) async {
  await _ensureMessagesChannel(plugin);
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _messageChannelId,
      'Messages',
      channelDescription: 'New messages',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      channelShowBadge: true,
      number: badgeCount != null && badgeCount > 0 ? badgeCount : null,
    ),
    iOS: DarwinNotificationDetails(
      presentBanner: true,
      presentList: true,
      presentSound: true,
      threadIdentifier: mailboxId,
    ),
  );

  await plugin.show(
    _messageNotificationId(mailboxId),
    title,
    body,
    details,
    payload: _encodeMessagePayload(
      mailboxId: mailboxId,
      senderId: senderId,
      senderName: senderName,
      threadChatId: threadChatId,
    ),
  );
}

bool _isMutedMailbox(SharedPreferences prefs, String mailboxId) {
  final mailbox = mailboxId.trim();
  if (mailbox.isEmpty) return false;
  final muted = prefs.getStringList(_pushMutedPref) ?? const <String>[];
  return muted.any((value) => value.trim() == mailbox);
}

Future<bool> _rememberEnvelopeId(
  SharedPreferences prefs,
  String envelopeId,
) async {
  final id = envelopeId.trim();
  if (id.isEmpty) return true;

  final current =
      (prefs.getStringList(_pushRecentEnvelopesPref) ?? const <String>[])
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: true);
  if (current.contains(id)) return false;

  current.add(id);
  if (current.length > 200) {
    current.removeRange(0, current.length - 200);
  }
  await prefs.setStringList(_pushRecentEnvelopesPref, current);
  return true;
}

int? _localDeviceId(SharedPreferences prefs, String userId) {
  final trimmedUserId = userId.trim();
  if (trimmedUserId.isEmpty) return null;
  return prefs.getInt('$_deviceIdPrefix$trimmedUserId') ??
      prefs.getInt('$_legacyDeviceIdPrefix$trimmedUserId');
}

String _localDeviceMailboxId(SharedPreferences prefs, String userId) {
  final trimmedUserId = userId.trim();
  if (trimmedUserId.isEmpty) return '';
  return (prefs.getString('$_deviceMailboxIdPrefix$trimmedUserId') ??
          prefs.getString('$_legacyDeviceMailboxIdPrefix$trimmedUserId') ??
          '')
      .trim();
}

String _directChatIdForContact(String contactId) {
  final trimmed = contactId.trim();
  return trimmed.isEmpty ? '' : 'direct:$trimmed';
}

String _resolveNotificationMailboxId({
  required String mailboxId,
  required String localDeviceMailboxId,
  required String senderId,
  required String localUserId,
}) {
  final cleanMailboxId = mailboxId.trim();
  if (cleanMailboxId.isEmpty) return '';
  if (cleanMailboxId.startsWith('direct:')) return cleanMailboxId;

  final cleanSenderId = senderId.trim();
  final cleanLocalDeviceMailboxId = localDeviceMailboxId.trim();
  final cleanLocalUserId = localUserId.trim();
  if (cleanMailboxId == cleanLocalDeviceMailboxId &&
      cleanSenderId.isNotEmpty &&
      cleanSenderId != cleanLocalUserId) {
    return _directChatIdForContact(cleanSenderId);
  }
  return cleanMailboxId;
}

bool _hasOutgoingLocalMessage(
  SharedPreferences prefs, {
  required String envelopeId,
  required String mailboxId,
  required String userId,
  required int? deviceId,
}) {
  final raw = (prefs.getString(_messagesPref) ?? '').trim();
  if (raw.isEmpty) return false;

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return false;
    final localUserId = userId.trim();
    final localDeviceId = deviceId?.toString();
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final messageId = (map['id'] ?? '').toString().trim();
      if (messageId != envelopeId) continue;
      final senderId = (map['senderId'] ?? '').toString().trim();
      if (senderId == 'local' ||
          senderId == localUserId ||
          (localDeviceId != null && senderId == localDeviceId)) {
        return true;
      }
    }
  } catch (_) {
    return false;
  }

  return false;
}

Map<String, dynamic> _loadUnreadMap(SharedPreferences prefs) {
  final raw = (prefs.getString(_chatUnreadPref) ?? '').trim();
  if (raw.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return <String, dynamic>{};
}

int _readUnreadCount(dynamic raw) {
  if (raw is int) return raw;
  if (raw is double) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  if (raw is Map) {
    final count = raw['unreadCount'];
    if (count is int) return count;
    if (count is double) return count.toInt();
    if (count is String) return int.tryParse(count.trim()) ?? 0;
  }
  return 0;
}

String _readLastIncomingMessageId(dynamic raw) {
  if (raw is Map) {
    return (raw['lastIncomingMessageId'] ?? '').toString().trim();
  }
  return '';
}

Future<int> _recordBackgroundUnread(
  SharedPreferences prefs, {
  required String chatId,
  required String messageId,
}) async {
  final cleanChatId = chatId.trim();
  if (cleanChatId.isEmpty) return 0;

  final nextMap = _loadUnreadMap(prefs);
  final existing = nextMap[cleanChatId];
  final cleanMessageId = messageId.trim();
  final lastIncomingId = _readLastIncomingMessageId(existing);
  final currentUnread = _readUnreadCount(existing);
  final nextUnread =
      cleanMessageId.isNotEmpty && cleanMessageId == lastIncomingId
      ? currentUnread
      : currentUnread + 1;

  nextMap[cleanChatId] = <String, dynamic>{
    'unreadCount': nextUnread < 0 ? 0 : nextUnread,
    if (cleanMessageId.isNotEmpty) 'lastIncomingMessageId': cleanMessageId,
  };
  await prefs.setString(_chatUnreadPref, jsonEncode(nextMap));

  var total = 0;
  for (final value in nextMap.values) {
    final unread = _readUnreadCount(value);
    if (unread > 0) {
      total += unread;
    }
  }
  return total;
}

Future<FlutterLocalNotificationsPlugin> _initBackgroundNotifications() async {
  final plugin = FlutterLocalNotificationsPlugin();
  try {
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
    final settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await plugin.initialize(settings);
  } catch (_) {}
  return plugin;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  final data = message.data;
  final type = (data['type'] ?? '').toString().trim();
  final prefs = await SharedPreferences.getInstance();

  if (type == 'incoming_call') {
    final callId = (data['callId'] ?? data['call_id'] ?? '').toString().trim();
    final mailboxId = _mailboxIdFromData(data);
    final callerId = (data['callerId'] ?? data['caller_id'] ?? '')
        .toString()
        .trim();
    final callerName = (data['callerName'] ?? data['caller_name'] ?? '')
        .toString()
        .trim();

    if (callId.isEmpty || mailboxId.isEmpty || callerId.isEmpty) return;

    final callActive = prefs.getBool('cc_call_active_v1') ?? false;
    if (callActive) {
      final myId = (prefs.getString(_localUserIdPref) ?? '').trim();
      if (myId.isEmpty) return;
      final myName = (prefs.getString(_localUsernamePref) ?? 'Conquered')
          .trim();
      final client = CallSignalingClient(mailboxId: mailboxId, deviceId: myId);
      try {
        await client.connect();
        client.send(<String, dynamic>{
          'type': 'busy',
          'callId': callId,
          'call_id': callId,
          'fromChatId': mailboxId,
          'from_chat_id': mailboxId,
          'toChatId': mailboxId,
          'to_chat_id': mailboxId,
          'senderId': myId,
          'sender_id': myId,
          'senderName': myName.isEmpty ? 'Conquered' : myName,
          'sender_name': myName.isEmpty ? 'Conquered' : myName,
        });
      } catch (_) {
        // ignore
      } finally {
        await client.close();
      }
      return;
    }

    final permitted = await CallPolicyStore.isIncomingCallPermittedFromPrefs(
      callerId: callerId,
    );
    if (!permitted) {
      final myId = (prefs.getString(_localUserIdPref) ?? '').trim();
      if (myId.isEmpty) return;
      final myName = (prefs.getString(_localUsernamePref) ?? 'Conquered')
          .trim();
      await _sendRejectOneShot(
        mailboxId: mailboxId,
        callId: callId,
        deviceId: myId,
        displayName: myName.isEmpty ? 'Conquered' : myName,
      );
      return;
    }

    final plugin = await _initBackgroundNotifications();
    await _showIncomingCallNotification(
      plugin: plugin,
      callId: callId,
      mailboxId: mailboxId,
      callerId: callerId,
      callerName: callerName,
    );
    return;
  }

  if (!_isLikelyMessageEvent(
    data,
    notificationTitle: message.notification?.title,
    notificationBody: message.notification?.body,
  )) {
    return;
  }

  if (!(prefs.getBool(_pushEnabledPref) ?? false)) return;
  if (!(prefs.getBool(_pushNotifyPref) ?? true)) return;

  final mailboxId = _mailboxIdFromData(data);
  if (mailboxId.isEmpty) return;

  final senderId = _senderIdFromData(data);
  final routingSenderId = _routingSenderIdFromData(data);
  final effectiveSenderId = routingSenderId.isNotEmpty
      ? routingSenderId
      : senderId;
  final userId = (prefs.getString(_localUserIdPref) ?? '').trim();
  final deviceId = _localDeviceId(prefs, userId);
  final localDeviceMailboxId = _localDeviceMailboxId(prefs, userId);
  if (effectiveSenderId.isNotEmpty &&
      (effectiveSenderId == userId ||
          (deviceId != null && effectiveSenderId == '$deviceId'))) {
    return;
  }

  final envelopeId = _envelopeIdFromData(data);
  if (envelopeId.isNotEmpty) {
    final isNew = await _rememberEnvelopeId(prefs, envelopeId);
    if (!isNew) return;
    if (_hasOutgoingLocalMessage(
      prefs,
      envelopeId: envelopeId,
      mailboxId: mailboxId,
      userId: userId,
      deviceId: deviceId,
    )) {
      return;
    }
  }

  final notificationMailboxId = _resolveNotificationMailboxId(
    mailboxId: mailboxId,
    localDeviceMailboxId: localDeviceMailboxId,
    senderId: routingSenderId,
    localUserId: userId,
  );
  if (notificationMailboxId.isEmpty) {
    return;
  }
  final totalUnread = await _recordBackgroundUnread(
    prefs,
    chatId: notificationMailboxId,
    messageId: envelopeId,
  );
  if (_isMutedMailbox(prefs, mailboxId) ||
      _isMutedMailbox(prefs, notificationMailboxId)) {
    return;
  }

  final senderName = _senderNameFromData(data);
  final title = senderName.isNotEmpty
      ? senderName
      : (() {
          final notificationTitle = (message.notification?.title ?? '').trim();
          return notificationTitle.isEmpty ? 'New message' : notificationTitle;
        })();
  final previewEnabled = prefs.getBool(_pushPreviewPref) ?? false;
  final body = previewEnabled
      ? (() {
          final preview = _previewTextFromData(
            data,
            notificationBody: message.notification?.body,
          );
          return preview.isEmpty ? 'New message' : preview;
        })()
      : 'New message';

  final plugin = await _initBackgroundNotifications();
  await _showIncomingMessageNotification(
    plugin: plugin,
    mailboxId: notificationMailboxId,
    title: title,
    body: body,
    senderId: routingSenderId,
    senderName: senderName,
    badgeCount: totalUnread,
    threadChatId: notificationMailboxId,
  );
}
