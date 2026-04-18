import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../security/relay_tls_pinning.dart';

class GiphyGif {
  final String id;
  final String title;
  final String previewUrl;
  final String downloadUrl;
  final double aspectRatio;

  const GiphyGif({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.downloadUrl,
    required this.aspectRatio,
  });
}

class GiphySearchResult {
  final List<GiphyGif> items;
  final bool hasMore;
  final int nextOffset;
  final String? errorMessage;

  const GiphySearchResult({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
    this.errorMessage,
  });
}

class GiphyService {
  static const String _apiKey = String.fromEnvironment(
    'GIPHY_API_KEY',
    defaultValue: '',
  );
  static const String _rating = String.fromEnvironment(
    'GIPHY_RATING',
    defaultValue: 'pg-13',
  );
  static const String _bundle = 'messaging_non_clips';

  static bool get isConfigured => _apiKey.trim().isNotEmpty;

  static Future<GiphySearchResult> trending({int limit = 24, int offset = 0}) {
    return _fetch(
      Uri.https('api.giphy.com', '/v1/gifs/trending', {
        'api_key': _apiKey,
        'limit': '$limit',
        'offset': '$offset',
        'rating': _rating,
        'bundle': _bundle,
      }),
    );
  }

  static Future<GiphySearchResult> search(
    String query, {
    int limit = 24,
    int offset = 0,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return trending(limit: limit, offset: offset);
    }
    return _fetch(
      Uri.https('api.giphy.com', '/v1/gifs/search', {
        'api_key': _apiKey,
        'q': trimmed,
        'limit': '$limit',
        'offset': '$offset',
        'rating': _rating,
        'bundle': _bundle,
      }),
    );
  }

  static Future<GiphySearchResult> _fetch(Uri uri) async {
    if (!isConfigured) {
      return const GiphySearchResult(
        items: <GiphyGif>[],
        hasMore: false,
        nextOffset: 0,
        errorMessage: 'GIPHY API key is not configured for this build.',
      );
    }

    HttpClient? client;
    try {
      await RelayTlsPinning.verifyUri(uri);
      client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return GiphySearchResult(
          items: const <GiphyGif>[],
          hasMore: false,
          nextOffset: 0,
          errorMessage: 'GIPHY search failed (${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const GiphySearchResult(
          items: <GiphyGif>[],
          hasMore: false,
          nextOffset: 0,
          errorMessage: 'GIPHY returned malformed data.',
        );
      }
      final data = Map<String, dynamic>.from(decoded);
      final rawItems = data['data'];
      final items = <GiphyGif>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          final parsed = _parseGif(item);
          if (parsed != null) {
            items.add(parsed);
          }
        }
      }
      final pagination = Map<String, dynamic>.from(
        (data['pagination'] as Map?) ?? const <String, dynamic>{},
      );
      final count = (pagination['count'] as num?)?.toInt() ?? items.length;
      final offset = (pagination['offset'] as num?)?.toInt() ?? 0;
      final total =
          (pagination['total_count'] as num?)?.toInt() ?? items.length;
      final nextOffset = offset + count;
      return GiphySearchResult(
        items: items,
        hasMore: nextOffset < total,
        nextOffset: nextOffset,
      );
    } catch (_) {
      return const GiphySearchResult(
        items: <GiphyGif>[],
        hasMore: false,
        nextOffset: 0,
        errorMessage: 'Could not reach GIPHY right now.',
      );
    } finally {
      client?.close(force: true);
    }
  }

  static GiphyGif? _parseGif(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = (json['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final title = (json['title'] ?? 'GIF').toString().trim();
    final images = Map<String, dynamic>.from(
      (json['images'] as Map?) ?? const <String, dynamic>{},
    );

    Map<String, dynamic> image(String key) => Map<String, dynamic>.from(
      (images[key] as Map?) ?? const <String, dynamic>{},
    );
    String valueFrom(Map<String, dynamic> map, String key) {
      final value = map[key];
      return value == null ? '' : value.toString().trim();
    }

    Map<String, dynamic>? firstAvailableImage(List<String> keys) {
      for (final key in keys) {
        final candidate = image(key);
        if (valueFrom(candidate, 'url').isNotEmpty) {
          return candidate;
        }
      }
      return null;
    }

    final previewImage = firstAvailableImage(<String>[
      'fixed_width_small',
      'fixed_width',
      'fixed_height_small',
      'fixed_height',
      'fixed_height_downsampled',
      'fixed_width_downsampled',
      'original',
    ]);
    final downloadImage = firstAvailableImage(<String>[
      'original',
      'fixed_width',
      'fixed_height',
      'fixed_width_small',
      'fixed_height_small',
    ]);
    final preview = previewImage == null ? '' : valueFrom(previewImage, 'url');
    final download = downloadImage == null
        ? ''
        : valueFrom(downloadImage, 'url');
    if (preview.isEmpty || download.isEmpty) {
      return null;
    }
    final width =
        double.tryParse(previewImage?['width']?.toString() ?? '') ??
        double.tryParse(downloadImage?['width']?.toString() ?? '') ??
        200;
    final height =
        double.tryParse(previewImage?['height']?.toString() ?? '') ??
        double.tryParse(downloadImage?['height']?.toString() ?? '') ??
        200;
    final aspectRatio = width > 0 && height > 0 ? width / height : 1.0;

    return GiphyGif(
      id: id,
      title: title.isEmpty ? 'GIF' : title,
      previewUrl: preview,
      downloadUrl: download,
      aspectRatio: aspectRatio,
    );
  }

  static Future<String?> downloadGif(GiphyGif gif) async {
    HttpClient? client;
    try {
      final uri = Uri.parse(gif.downloadUrl);
      await RelayTlsPinning.verifyUri(uri);
      client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}vault_giphy_${gif.id}.gif',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
