import 'dart:convert';
import 'dart:io';

import '../relay/relay_config.dart';
import '../security/relay_tls_pinning.dart';

class FeedbackClient {
  static Uri _endpoint(String path) {
    final base = Uri.parse(RelayConfig.baseUrl);
    return base.replace(path: '${base.path}$path');
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

  static Future<bool> submitAnonymousFeedback({
    required String message,
    String? category,
    Map<String, dynamic>? diagnostics,
  }) async {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) return false;

    HttpClient? client;
    try {
      final uri = _endpoint('/v1/feedback');
      await RelayTlsPinning.verifyUri(uri);
      client = HttpClient();
      final request = await client.postUrl(uri);
      _applyHeaders(request);
      request.add(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'message': cleanMessage,
            'anonymous': true,
            if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
            if (diagnostics != null && diagnostics.isNotEmpty)
              'diagnostics': diagnostics,
          }),
        ),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}
