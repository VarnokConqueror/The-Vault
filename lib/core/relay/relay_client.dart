import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'relay_config.dart';

class RelayMessage {
  static const String typeText = 'text';
  static const String typeVoice = 'voice';
  static const String typeSticker = 'sticker';
  static const String typeAttachmentChunk = 'attachment_chunk';

  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String type;
  final String body;
  final String? stickerPackId;
  final String? stickerId;
  final String? stickerVariant;
  final String? attachmentId;
  final String? attachmentName;
  final String? attachmentMime;
  final int? attachmentSize;
  final int? attachmentChunkIndex;
  final int? attachmentChunkCount;
  final String? attachmentChunkB64;
  final bool? attachmentInline;
  final String? voiceB64;
  final String? voiceMime;
  final int? voiceDurationMs;
  final DateTime createdAt;

  RelayMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    this.type = typeText,
    required this.body,
    this.stickerPackId,
    this.stickerId,
    this.stickerVariant,
    this.attachmentId,
    this.attachmentName,
    this.attachmentMime,
    this.attachmentSize,
    this.attachmentChunkIndex,
    this.attachmentChunkCount,
    this.attachmentChunkB64,
    this.attachmentInline,
    this.voiceB64,
    this.voiceMime,
    this.voiceDurationMs,
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

  RelayMailboxFetch({required this.mailboxId, required this.envelopes});
}

class RelayClient {
  static const bool logSuccess = bool.fromEnvironment(
    'RELAY_LOG_SUCCESS',
    defaultValue: false,
  );

  static Uri _endpoint(String path, [Map<String, String>? query]) {
    final base = Uri.parse(RelayConfig.baseUrl);
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }

  static void _applyHeaders(HttpClientRequest request) {
    request.headers.contentType = ContentType.json;
    if (RelayConfig.shouldAttachRelayToken) {
      request.headers.set(
        RelayConfig.relayAuthHeader,
        RelayConfig.relayTokenTrimmed,
      );
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
      debugPrint(
        '[Relay] POST /envelope failed: ${RelayConfig.baseUrl} ($error)',
      );
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
      final uri = _endpoint('/mailbox/$mailboxId', {'limit': limit.toString()});
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
        _log2xx(
          'GET',
          uri,
          response.statusCode,
          mailboxId: mailboxId,
          extra: 'parse_failed',
        );
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final rawEnvelopes = map['envelopes'];
      if (rawEnvelopes is! List) {
        _log2xx(
          'GET',
          uri,
          response.statusCode,
          mailboxId: mailboxId,
          extra: 'parse_failed',
        );
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
    final envelopeId = (map['envelope_id'] ?? map['envelopeId'] ?? '')
        .toString()
        .trim();
    final payloadB64 = (map['payload_b64'] ?? map['payloadB64'] ?? '')
        .toString()
        .trim();
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
    final type = message.type.trim().isEmpty
        ? RelayMessage.typeText
        : message.type.trim();
    final isVoice = type == RelayMessage.typeVoice;
    final isSticker = type == RelayMessage.typeSticker;
    final isAttachmentChunk = type == RelayMessage.typeAttachmentChunk;
    final payload = <String, dynamic>{
      'chatId': message.chatId,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'body': message.body,
      'createdAt': message.createdAt.toIso8601String(),
      'timestamp': message.createdAt.millisecondsSinceEpoch,
      'messageId': message.id,
      'type': type,
      'messageType': type,
      if (isSticker && (message.stickerPackId ?? '').trim().isNotEmpty)
        'stickerPackId': message.stickerPackId!.trim(),
      if (isSticker && (message.stickerId ?? '').trim().isNotEmpty)
        'stickerId': message.stickerId!.trim(),
      if (isSticker && (message.stickerVariant ?? '').trim().isNotEmpty)
        'stickerVariant': message.stickerVariant!.trim(),
      if (isAttachmentChunk && (message.attachmentId ?? '').trim().isNotEmpty)
        'attachmentId': message.attachmentId!.trim(),
      if (isAttachmentChunk && (message.attachmentName ?? '').trim().isNotEmpty)
        'attachmentName': message.attachmentName!.trim(),
      if (isAttachmentChunk && (message.attachmentMime ?? '').trim().isNotEmpty)
        'attachmentMime': message.attachmentMime!.trim(),
      if (isAttachmentChunk && message.attachmentSize != null)
        'attachmentSize': message.attachmentSize,
      if (isAttachmentChunk && message.attachmentChunkIndex != null)
        'attachmentChunkIndex': message.attachmentChunkIndex,
      if (isAttachmentChunk && message.attachmentChunkCount != null)
        'attachmentChunkCount': message.attachmentChunkCount,
      if (isAttachmentChunk &&
          (message.attachmentChunkB64 ?? '').trim().isNotEmpty)
        'attachmentChunkB64': message.attachmentChunkB64!.trim(),
      if (isAttachmentChunk && message.attachmentInline != null)
        'attachmentInline': message.attachmentInline,
      if (isVoice && (message.voiceB64 ?? '').trim().isNotEmpty)
        'voiceB64': message.voiceB64!.trim(),
      if (isVoice && (message.voiceMime ?? '').trim().isNotEmpty)
        'voiceMime': message.voiceMime!.trim(),
      if (isVoice && message.voiceDurationMs != null)
        'voiceDurationMs': message.voiceDurationMs,
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
      final senderName = (map['senderName'] ?? map['sender_name'] ?? '')
          .toString()
          .trim();
      final rawType = (map['type'] ?? map['messageType'] ?? '')
          .toString()
          .trim();
      final type = rawType.isEmpty ? RelayMessage.typeText : rawType;
      final isVoice = type == RelayMessage.typeVoice;
      final isSticker = type == RelayMessage.typeSticker;
      final isAttachmentChunk = type == RelayMessage.typeAttachmentChunk;

      final bodyRaw = (map['body'] ?? '').toString();
      final body = bodyRaw.trim().isEmpty && (isVoice || isSticker)
          ? (isSticker ? 'Sticker' : 'Voice message')
          : bodyRaw;

      final stickerPackId =
          (map['stickerPackId'] ?? map['sticker_pack_id'] ?? '')
              .toString()
              .trim();
      final stickerId = (map['stickerId'] ?? map['sticker_id'] ?? '')
          .toString()
          .trim();
      final stickerVariant =
          (map['stickerVariant'] ?? map['sticker_variant'] ?? '')
              .toString()
              .trim();
      final attachmentId = (map['attachmentId'] ?? map['attachment_id'] ?? '')
          .toString()
          .trim();
      final attachmentName =
          (map['attachmentName'] ?? map['attachment_name'] ?? '')
              .toString()
              .trim();
      final attachmentMime =
          (map['attachmentMime'] ?? map['attachment_mime'] ?? '')
              .toString()
              .trim();
      int? attachmentSize;
      final attachmentSizeRaw = map['attachmentSize'] ?? map['attachment_size'];
      if (attachmentSizeRaw is int) {
        attachmentSize = attachmentSizeRaw;
      } else if (attachmentSizeRaw is double) {
        attachmentSize = attachmentSizeRaw.toInt();
      } else if (attachmentSizeRaw is String) {
        attachmentSize = int.tryParse(attachmentSizeRaw.trim());
      }
      int? attachmentChunkIndex;
      final chunkIndexRaw =
          map['attachmentChunkIndex'] ?? map['attachment_chunk_index'];
      if (chunkIndexRaw is int) {
        attachmentChunkIndex = chunkIndexRaw;
      } else if (chunkIndexRaw is double) {
        attachmentChunkIndex = chunkIndexRaw.toInt();
      } else if (chunkIndexRaw is String) {
        attachmentChunkIndex = int.tryParse(chunkIndexRaw.trim());
      }
      int? attachmentChunkCount;
      final chunkCountRaw =
          map['attachmentChunkCount'] ?? map['attachment_chunk_count'];
      if (chunkCountRaw is int) {
        attachmentChunkCount = chunkCountRaw;
      } else if (chunkCountRaw is double) {
        attachmentChunkCount = chunkCountRaw.toInt();
      } else if (chunkCountRaw is String) {
        attachmentChunkCount = int.tryParse(chunkCountRaw.trim());
      }
      final attachmentChunkB64 =
          (map['attachmentChunkB64'] ?? map['attachment_chunk_b64'] ?? '')
              .toString()
              .trim();
      final attachmentInline = map['attachmentInline'] is bool
          ? map['attachmentInline'] as bool
          : (map['attachment_inline'] is bool
                ? map['attachment_inline'] as bool
                : null);

      final voiceB64 = (map['voiceB64'] ?? map['voice_b64'] ?? '')
          .toString()
          .trim();
      final voiceMime = (map['voiceMime'] ?? map['voice_mime'] ?? '')
          .toString()
          .trim();
      int? voiceDurationMs;
      final durationRaw = map['voiceDurationMs'] ?? map['voice_duration_ms'];
      if (durationRaw is int) {
        voiceDurationMs = durationRaw;
      } else if (durationRaw is double) {
        voiceDurationMs = durationRaw.toInt();
      } else if (durationRaw is String) {
        voiceDurationMs = int.tryParse(durationRaw.trim());
      }

      final createdAt =
          _parseDate(map['createdAt'] ?? map['timestamp']) ??
          envelope.createdAt;
      final id = (map['messageId'] ?? map['id'] ?? envelope.envelopeId)
          .toString();
      if (chatId.isEmpty || senderId.isEmpty) return null;
      if (!isVoice && !isSticker && !isAttachmentChunk && body.trim().isEmpty) {
        return null;
      }
      if (isVoice && voiceB64.isEmpty) return null;
      if (isSticker && (stickerPackId.isEmpty || stickerId.isEmpty))
        return null;
      if (isAttachmentChunk &&
          (attachmentId.isEmpty ||
              attachmentChunkB64.isEmpty ||
              attachmentChunkIndex == null ||
              attachmentChunkCount == null)) {
        return null;
      }
      return RelayMessage(
        id: id.trim().isEmpty ? envelope.envelopeId : id.trim(),
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        type: type,
        body: body,
        stickerPackId: stickerPackId.isEmpty ? null : stickerPackId,
        stickerId: stickerId.isEmpty ? null : stickerId,
        stickerVariant: stickerVariant.isEmpty ? null : stickerVariant,
        attachmentId: attachmentId.isEmpty ? null : attachmentId,
        attachmentName: attachmentName.isEmpty ? null : attachmentName,
        attachmentMime: attachmentMime.isEmpty ? null : attachmentMime,
        attachmentSize: attachmentSize,
        attachmentChunkIndex: attachmentChunkIndex,
        attachmentChunkCount: attachmentChunkCount,
        attachmentChunkB64: attachmentChunkB64.isEmpty
            ? null
            : attachmentChunkB64,
        attachmentInline: attachmentInline,
        voiceB64: voiceB64.isEmpty ? null : voiceB64,
        voiceMime: voiceMime.isEmpty ? null : voiceMime,
        voiceDurationMs: voiceDurationMs,
        createdAt: createdAt,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> registerPush({
    required String mailboxId,
    required String deviceId,
    required String platform,
    required String fcmToken,
    required bool notifyOnNewMessages,
    required bool showPreview,
    String? androidChannelId,
  }) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/push/register');
      final channelId = (androidChannelId ?? '').trim();
      final payload = <String, dynamic>{
        'mailbox_id': mailboxId,
        'mailboxId': mailboxId,
        'device_id': deviceId,
        'deviceId': deviceId,
        'platform': platform,
        'fcm_token': fcmToken,
        'fcmToken': fcmToken,
        'notify_on_new_messages': notifyOnNewMessages,
        'notifyOnNewMessages': notifyOnNewMessages,
        'show_preview': showPreview,
        'showPreview': showPreview,
        if (channelId.isNotEmpty) 'android_channel_id': channelId,
        if (channelId.isNotEmpty) 'androidChannelId': channelId,
        if (channelId.isNotEmpty) 'channel_id': channelId,
        if (channelId.isNotEmpty) 'channelId': channelId,
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
        extra: 'device=$deviceId',
      );
      return true;
    } catch (error) {
      debugPrint(
        '[Relay] POST /push/register failed: ${RelayConfig.baseUrl} ($error)',
      );
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> unregisterPush({
    required String mailboxId,
    required String deviceId,
  }) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/push/unregister');
      final payload = <String, dynamic>{
        'mailbox_id': mailboxId,
        'mailboxId': mailboxId,
        'device_id': deviceId,
        'deviceId': deviceId,
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
        extra: 'device=$deviceId',
      );
      return true;
    } catch (error) {
      debugPrint(
        '[Relay] POST /push/unregister failed: ${RelayConfig.baseUrl} ($error)',
      );
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/turn/credentials');
      final request = await client.getUrl(uri);
      _applyHeaders(request);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('GET', uri, response.statusCode, body);
        return <Map<String, dynamic>>[];
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) return <Map<String, dynamic>>[];
      final map = Map<String, dynamic>.from(decoded);
      final raw = map['iceServers'] ?? map['ice_servers'];
      if (raw is! List) return <Map<String, dynamic>>[];

      final servers = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final s = Map<String, dynamic>.from(item);
        final urlsRaw = s['urls'] ?? s['url'] ?? s['uris'];
        List<dynamic> urls;
        if (urlsRaw is String) {
          urls = <dynamic>[urlsRaw];
        } else if (urlsRaw is List) {
          urls = urlsRaw;
        } else {
          urls = const <dynamic>[];
        }
        if (urls.isEmpty) continue;
        final out = <String, dynamic>{'urls': urls};
        final username = (s['username'] ?? '').toString().trim();
        final credential = (s['credential'] ?? s['password'] ?? '')
            .toString()
            .trim();
        if (username.isNotEmpty) out['username'] = username;
        if (credential.isNotEmpty) out['credential'] = credential;
        servers.add(out);
      }
      return servers;
    } catch (error) {
      debugPrint(
        '[Relay] GET /turn/credentials failed: ${RelayConfig.baseUrl} ($error)',
      );
      return <Map<String, dynamic>>[];
    } finally {
      client.close(force: true);
    }
  }

  static void _logAuth401(String method, Uri uri) {
    debugPrint(
      '[Relay][401] $method $uri header=${RelayConfig.relayAuthHeader}'
      ' enabled=${RelayConfig.relayTokenEnabled}'
      ' attached=${RelayConfig.shouldAttachRelayToken}'
      ' token=${RelayConfig.maskedRelayToken}',
    );
  }

  static void _logNon200(String method, Uri uri, int status, String body) {
    if (status == 401) {
      _logAuth401(method, uri);
    }
    final snippet = body.length > 300 ? body.substring(0, 300) : body;
    debugPrint('[Relay] $method $uri -> $status :: $snippet');
  }
}
