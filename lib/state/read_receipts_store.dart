import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReadReceiptsStore {
  static const _prefSendReadReceipts = 'cc_send_read_receipts_v1';

  static final ValueNotifier<bool> sendReadReceiptsNotifier =
      ValueNotifier<bool>(false);

  static bool get sendReadReceipts => sendReadReceiptsNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    sendReadReceiptsNotifier.value =
        prefs.getBool(_prefSendReadReceipts) ?? false;
  }

  static Future<void> setSendReadReceipts(bool enabled) async {
    sendReadReceiptsNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefSendReadReceipts, enabled);
  }
}
