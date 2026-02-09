import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/call_signaling.dart';
import '../../state/call_policy_store.dart';

const String _callChannelId = 'cc_calls';

int _callNotificationId(String callId) {
  var hash = 0;
  for (final code in callId.codeUnits) {
    hash = ((hash << 5) - hash + code) & 0x7fffffff;
  }
  return hash;
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

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep this handler lightweight: data-only pushes + local notification.
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  final data = message.data;
  final type = (data['type'] ?? '').toString().trim();
  if (type != 'incoming_call') return;

  final callId = (data['callId'] ?? data['call_id'] ?? '').toString().trim();
  final mailboxId =
      (data['mailboxId'] ?? data['mailbox_id'] ?? '').toString().trim();
  final callerId =
      (data['callerId'] ?? data['caller_id'] ?? '').toString().trim();
  final callerName =
      (data['callerName'] ?? data['caller_name'] ?? '').toString().trim();

  if (callId.isEmpty || mailboxId.isEmpty || callerId.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final callActive = prefs.getBool('cc_call_active_v1') ?? false;
  if (callActive) {
    final myId = (prefs.getString('local_user_id') ?? '').trim();
    if (myId.isEmpty) return;
    final myName = (prefs.getString('local_username') ?? 'Conquered').trim();
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
    final myId = (prefs.getString('local_user_id') ?? '').trim();
    if (myId.isEmpty) return;
    final myName = (prefs.getString('local_username') ?? 'Conquered').trim();
    await _sendRejectOneShot(
      mailboxId: mailboxId,
      callId: callId,
      deviceId: myId,
      displayName: myName.isEmpty ? 'Conquered' : myName,
    );
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  try {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await plugin.initialize(settings);
  } catch (_) {}

  await _showIncomingCallNotification(
    plugin: plugin,
    callId: callId,
    mailboxId: mailboxId,
    callerId: callerId,
    callerName: callerName,
  );
}
