import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../relay/relay_config.dart';
import 'vault_models.dart';

class VaultRelayClient {
  static const int defaultOneTimePreKeyCount = 50;

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

  static Future<VaultDeviceRegistration?> registerDevice({
    required String userId,
    int? deviceId,
    required String platform,
    String? appVersion,
    String? deviceLabel,
  }) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/devices/register');
      final payload = <String, dynamic>{
        'userId': userId,
        'platform': platform,
        if (deviceId != null) 'deviceId': deviceId,
        if ((appVersion ?? '').trim().isNotEmpty)
          'appVersion': appVersion!.trim(),
        if ((deviceLabel ?? '').trim().isNotEmpty)
          'deviceLabel': deviceLabel!.trim(),
      };
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultDeviceRegistration.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (error) {
      debugPrint('[VaultRelay] POST /v1/devices/register failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultPreKeyUploadResult?> uploadPreKeys(
    VaultPreKeyUpload upload,
  ) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/prekeys/upload');
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(upload.toJson())));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultPreKeyUploadResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (error) {
      debugPrint('[VaultRelay] POST /v1/prekeys/upload failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultDevicesResponse?> fetchDevices(String userId) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) {
      return null;
    }
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/devices/$cleanUserId');
      final request = await client.getUrl(uri);
      _applyHeaders(request);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('GET', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultDevicesResponse.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('[VaultRelay] GET /v1/devices failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultGroupResponse?> ensureGroup({
    required String groupId,
    required String title,
    required String creatorUserId,
  }) async {
    final cleanGroupId = groupId.trim();
    final cleanCreatorUserId = creatorUserId.trim();
    if (cleanGroupId.isEmpty || cleanCreatorUserId.isEmpty) {
      return null;
    }
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/groups/ensure');
      final payload = <String, dynamic>{
        'groupId': cleanGroupId,
        'title': title.trim(),
        'creatorUserId': cleanCreatorUserId,
      };
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultGroupResponse.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('[VaultRelay] POST /v1/groups/ensure failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultGroupResponse?> joinGroup({
    required String groupId,
    required String userId,
    String? title,
  }) async {
    final cleanGroupId = groupId.trim();
    final cleanUserId = userId.trim();
    if (cleanGroupId.isEmpty || cleanUserId.isEmpty) {
      return null;
    }
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/groups/$cleanGroupId/join');
      final payload = <String, dynamic>{
        'userId': cleanUserId,
        if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      };
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultGroupResponse.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('[VaultRelay] POST /v1/groups/join failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultGroupDevicesResponse?> fetchGroupDevices(
    String groupId,
  ) async {
    final cleanGroupId = groupId.trim();
    if (cleanGroupId.isEmpty) {
      return null;
    }
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/groups/$cleanGroupId/devices');
      final request = await client.getUrl(uri);
      _applyHeaders(request);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('GET', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultGroupDevicesResponse.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (error) {
      debugPrint('[VaultRelay] GET /v1/groups/devices failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultPreKeyBundle?> fetchPreKeyBundle(
    VaultAddress address,
  ) async {
    final client = HttpClient();
    try {
      final uri = _endpoint(
        '/v1/prekeys/${address.userId}/${address.deviceId}',
      );
      final request = await client.getUrl(uri);
      _applyHeaders(request);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('GET', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultPreKeyBundle.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('[VaultRelay] GET /v1/prekeys failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultSendResult?> sendMessages({
    required VaultAddress source,
    required List<VaultOutboundEnvelope> messages,
    String? clientMessageId,
  }) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/messages/send');
      final payload = <String, dynamic>{
        'source': source.toJson(),
        'messages': messages.map((item) => item.toJson()).toList(),
        if ((clientMessageId ?? '').trim().isNotEmpty)
          'clientMessageId': clientMessageId!.trim(),
      };
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return VaultSendResult.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('[VaultRelay] POST /v1/messages/send failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<VaultMailboxFetch?> fetchMailbox({
    required String mailboxId,
    int limit = 50,
  }) async {
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/mailboxes/$mailboxId', {
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
      if (decoded is! Map) return null;
      return VaultMailboxFetch.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('[VaultRelay] GET /v1/mailboxes failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> ackMailbox({
    required String mailboxId,
    required List<String> envelopeIds,
  }) async {
    if (envelopeIds.isEmpty) return true;
    final client = HttpClient();
    try {
      final uri = _endpoint('/v1/mailboxes/$mailboxId/ack');
      final payload = <String, dynamic>{'envelopeIds': envelopeIds};
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logNon200('POST', uri, response.statusCode, body);
        return false;
      }
      return true;
    } catch (error) {
      debugPrint('[VaultRelay] POST /v1/mailboxes/ack failed: $error');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static void _logNon200(String method, Uri uri, int status, String body) {
    final snippet = body.length > 300 ? body.substring(0, 300) : body;
    debugPrint('[VaultRelay] $method $uri -> $status :: $snippet');
  }
}
