import 'package:flutter/foundation.dart';

class PushRuntimeStore {
  static final ValueNotifier<bool> firebaseReadyNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<String> firebaseStatusNotifier =
      ValueNotifier<String>('Not initialized');
  static final ValueNotifier<String> permissionStatusNotifier =
      ValueNotifier<String>('Not requested');
  static final ValueNotifier<String> apnsStatusNotifier =
      ValueNotifier<String>('Waiting');
  static final ValueNotifier<String> fcmStatusNotifier =
      ValueNotifier<String>('Waiting');
  static final ValueNotifier<String> relayStatusNotifier =
      ValueNotifier<String>('Idle');
  static final ValueNotifier<String> lastErrorNotifier =
      ValueNotifier<String>('');
  static final ValueNotifier<int?> lastSyncAtMsNotifier =
      ValueNotifier<int?>(null);
  static final ValueNotifier<int?> lastSuccessAtMsNotifier =
      ValueNotifier<int?>(null);

  static bool get firebaseReady => firebaseReadyNotifier.value;
  static String get firebaseStatus => firebaseStatusNotifier.value;
  static String get permissionStatus => permissionStatusNotifier.value;
  static String get apnsStatus => apnsStatusNotifier.value;
  static String get fcmStatus => fcmStatusNotifier.value;
  static String get relayStatus => relayStatusNotifier.value;
  static String get lastError => lastErrorNotifier.value;
  static int? get lastSyncAtMs => lastSyncAtMsNotifier.value;
  static int? get lastSuccessAtMs => lastSuccessAtMsNotifier.value;

  static void setFirebaseReady(bool ready, {required String status}) {
    firebaseReadyNotifier.value = ready;
    firebaseStatusNotifier.value = status;
  }

  static void setPermissionStatus(String status) {
    permissionStatusNotifier.value = status.trim();
  }

  static void setApnsStatus(String status) {
    apnsStatusNotifier.value = status.trim();
  }

  static void setFcmStatus(String status) {
    fcmStatusNotifier.value = status.trim();
  }

  static void markSyncStarted([String status = 'Syncing…']) {
    relayStatusNotifier.value = status.trim();
    lastSyncAtMsNotifier.value = DateTime.now().millisecondsSinceEpoch;
  }

  static void markRelaySuccess(String status) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    relayStatusNotifier.value = status.trim();
    lastSyncAtMsNotifier.value = nowMs;
    lastSuccessAtMsNotifier.value = nowMs;
    lastErrorNotifier.value = '';
  }

  static void markRelayFailure(String status, {String? error}) {
    relayStatusNotifier.value = status.trim();
    lastSyncAtMsNotifier.value = DateTime.now().millisecondsSinceEpoch;
    final nextError = (error ?? '').trim();
    if (nextError.isNotEmpty) {
      lastErrorNotifier.value = nextError;
    }
  }
}
