import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class RelayMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  RelayMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });
}

class RelayEnvelope {
  final String envelopeId;
  final String payloadB64;
  final DateTime createdAt;

  RelayEnvelope({
    required this.envelopeId,
    required this.payloadB64,
    required this.createdAt,
  });
}

class RelayMailboxFetch {
  final String mailboxId;
  final List<RelayEnvelope> envelopes;

  RelayMailboxFetch({
    required this.mailboxId,
    required this.envelopes,
  });
}

class RelayClient {
  static const bool logSuccess = bool.fromEnvironment(
    'RELAY_LOG_SUCCESS',
    defaultValue: false,
  );

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

  static Uri _endpoint(String path, [Map<String, String>? query]) {
    final base = Uri.parse(_baseUrl);
    return base.replace(
      path: '${base.path}$path',
      queryParameters: query,
    );
  }

  static void _applyHeaders(HttpClientRequest request) {
    request.headers.contentType = ContentType.json;
    if (_relayTokenEnabled && _relayToken.trim().isNotEmpty) {
      request.headers.set('X-Court-Relay-Token', _relayToken.trim());
    }
  }

  static void _log2xx(
    String method,
    Uri uri,
    int status, {
    String? mailboxId,
    String? extra,
  }) {
    if (!logSuccess) return;
    final mb = (mailboxId == null || mailboxId.trim().isEmpty)
        ? ''
        : ' mailbox=$mailboxId';
    final ex = (extra == null || extra.trim().isEmpty) ? '' : ' $extra';
    debugPrint('[Relay] $method $uri -> $status$mb$ex');
  }

  static Future<bool> sendMessage(RelayMessage message) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/envelope');
      final payload = <String, dynamic>{
        'mailbox_id': message.chatId,
        'mailboxId': message.chatId,
        'envelope_id': message.id,
        'envelopeId': message.id,
        'payload_b64': _encodePayload(message),
        'payloadB64': _encodePayload(message),
      };
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return false;
      }
      _log2xx(
        'POST',
        uri,
        response.statusCode,
        mailboxId: message.chatId,
        extra: 'envelope=${message.id}',
      );
      return true;
    } catch (error) {
      debugPrint('[Relay] POST /envelope failed: $_baseUrl ($error)');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<RelayMailboxFetch?> fetchMailbox({
    required String mailboxId,
    int limit = 50,
  }) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/mailbox/$mailboxId', {
        'limit': limit.toString(),
      });
      final request = await client.getUrl(uri);
      _applyHeaders(request);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('GET', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        _log2xx('GET', uri, response.statusCode,
            mailboxId: mailboxId, extra: 'parse_failed');
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final rawEnvelopes = map['envelopes'];
      if (rawEnvelopes is! List) {
        _log2xx('GET', uri, response.statusCode,
            mailboxId: mailboxId, extra: 'parse_failed');
        return null;
      }
      final envelopes = <RelayEnvelope>[];
      for (final item in rawEnvelopes) {
        if (item is! Map) continue;
        final parsed = _parseEnvelope(Map<String, dynamic>.from(item));
        if (parsed != null) {
          envelopes.add(parsed);
        }
      }
      _log2xx(
        'GET',
        uri,
        response.statusCode,
        mailboxId: mailboxId,
        extra: 'envelopes=${envelopes.length}',
      );
      return RelayMailboxFetch(mailboxId: mailboxId, envelopes: envelopes);
    } catch (error) {
      debugPrint('[Relay] GET /mailbox failed: $mailboxId ($error)');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> ackEnvelopes({
    required String mailboxId,
    required List<String> envelopeIds,
  }) async {
    if (envelopeIds.isEmpty) return true;
    final client = HttpClient();
    try {
      final uri = _endpoint('/ack');
      final payload = <String, dynamic>{
        'mailbox_id': mailboxId,
        'mailboxId': mailboxId,
        'envelope_ids': envelopeIds,
        'envelopeIds': envelopeIds,
      };
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return false;
      }
      _log2xx(
        'POST',
        uri,
        response.statusCode,
        mailboxId: mailboxId,
        extra: 'acked=${envelopeIds.length}',
      );
      return true;
    } catch (error) {
      debugPrint('[Relay] POST /ack failed: $mailboxId ($error)');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static RelayEnvelope? _parseEnvelope(Map<String, dynamic> map) {
    final envelopeId =
        (map['envelope_id'] ?? map['envelopeId'] ?? '').toString().trim();
    final payloadB64 =
        (map['payload_b64'] ?? map['payloadB64'] ?? '').toString().trim();
    final createdAt = _parseDate(map['created_at'] ?? map['createdAt']);
    if (envelopeId.isEmpty || payloadB64.isEmpty || createdAt == null) {
      return null;
    }
    return RelayEnvelope(
      envelopeId: envelopeId,
      payloadB64: payloadB64,
      createdAt: createdAt,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) {
      return _fromEpoch(raw);
    }
    if (raw is double) {
      return _fromEpoch(raw.toInt());
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final numeric = int.tryParse(trimmed);
      if (numeric != null) {
        return _fromEpoch(numeric);
      }
      return DateTime.tryParse(trimmed);
    }
    return null;
  }

  static DateTime _fromEpoch(int value) {
    if (value < 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: false);
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: false);
  }

  static String _encodePayload(RelayMessage message) {
    final payload = <String, dynamic>{
      'chatId': message.chatId,
      'senderId': message.senderId,
      'body': message.body,
      'createdAt': message.createdAt.toIso8601String(),
      'timestamp': message.createdAt.millisecondsSinceEpoch,
      'messageId': message.id,
    };
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  static RelayMessage? decodePayload(RelayEnvelope envelope) {
    try {
      final decoded = utf8.decode(base64Decode(envelope.payloadB64));
      final json = jsonDecode(decoded);
      if (json is! Map) return null;
      final map = Map<String, dynamic>.from(json);
      final chatId = (map['chatId'] ?? '').toString().trim();
      final senderId = (map['senderId'] ?? '').toString().trim();
      final body = (map['body'] ?? '').toString();
      final createdAt =
          _parseDate(map['createdAt'] ?? map['timestamp']) ?? envelope.createdAt;
      final id =
          (map['messageId'] ?? map['id'] ?? envelope.envelopeId).toString();
      if (chatId.isEmpty || senderId.isEmpty || body.trim().isEmpty) {
        return null;
      }
      return RelayMessage(
        id: id.trim().isEmpty ? envelope.envelopeId : id.trim(),
        chatId: chatId,
        senderId: senderId,
        body: body,
        createdAt: createdAt,
      );
    } catch (_) {
      return null;
    }
  }

  static void _logNon200(
    String method,
    Uri uri,
    int status,
    String body,
  ) {
    final snippet = body.length > 300 ? body.substring(0, 300) : body;
    debugPrint('[Relay] $method $uri -> $status :: $snippet');
  }
}
