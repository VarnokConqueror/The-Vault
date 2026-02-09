import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

class CallSignalingClient {
  CallSignalingClient({
    required this.mailboxId,
    required this.deviceId,
  });

  final String mailboxId;
  final String deviceId;

  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;

  void Function(Map<String, dynamic> event)? onEvent;
  void Function(Object error)? onError;
  void Function()? onDone;

  static const String _baseUrl = String.fromEnvironment(
    'RELAY_BASE_URL',
    defaultValue: 'https://relay.theconquerorscourt.com',
  );
  static const String _relayToken = String.fromEnvironment(
    'RELAY_TOKEN',
    defaultValue: '',
  );
  static const bool _relayTokenEnabled = bool.fromEnvironment(
    'RELAY_TOKEN_ENABLED',
    defaultValue: false,
  );

  bool get isConnected => _channel != null;

  static Uri _wsEndpoint(String path, Map<String, String> query) {
    final base = Uri.parse(_baseUrl);
    final scheme = base.scheme == 'https'
        ? 'wss'
        : base.scheme == 'http'
            ? 'ws'
            : base.scheme;
    return base.replace(
      scheme: scheme,
      path: '${base.path}$path',
      queryParameters: query,
    );
  }

  Future<void> connect() async {
    if (_channel != null) return;

    final mb = mailboxId.trim();
    final dev = deviceId.trim();
    if (mb.isEmpty || dev.isEmpty) {
      throw StateError('mailboxId and deviceId are required');
    }

    final uri = _wsEndpoint('/ws/call', {
      'mailboxId': mb,
      'deviceId': dev,
    });

    final headers = <String, String>{};
    if (_relayTokenEnabled && _relayToken.trim().isNotEmpty) {
      headers['X-Court-Relay-Token'] = _relayToken.trim();
    }

    _channel = IOWebSocketChannel.connect(uri, headers: headers);
    _sub = _channel!.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw.toString());
          if (decoded is Map) {
            onEvent?.call(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      },
      onError: (e) => onError?.call(e),
      onDone: () => onDone?.call(),
      cancelOnError: false,
    );
  }

  void send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[CallSignal] send failed: $e');
    }
  }

  Future<void> close() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    final ch = _channel;
    _channel = null;
    try {
      await ch?.sink.close(ws_status.goingAway);
    } catch (_) {}
  }
}

