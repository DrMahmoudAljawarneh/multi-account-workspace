import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Local favicon cache.
///
/// Shares `~/.config/webspace/favicon-cache.json` with the Electron build:
/// `{ "<domain>": { "data": "data:image/...", "ts": 1712345 } }` with a 7-day
/// TTL. On a miss it fetches the site's own `/favicon.ico` first and falls
/// back to the DuckDuckGo icon service — no third-party tracking calls at
/// launch once an icon is cached.
class FaviconService {
  static const ttl = Duration(days: 7);

  static String get _cachePath {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return '$home/.config/webspace/favicon-cache.json';
  }

  /// Decoded icons memoized for the process lifetime.
  static final Map<String, Uint8List?> _memory = {};
  static Map<String, dynamic>? _cache;
  static final Set<String> _inFlight = {};

  static Map<String, dynamic> _loadCache() {
    if (_cache != null) return _cache!;
    try {
      final file = File(_cachePath);
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) return _cache = decoded;
      }
    } catch (_) {
      // Corrupt cache → start fresh
    }
    return _cache = {};
  }

  static void _persistCache() {
    try {
      final file = File(_cachePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_cache));
    } catch (_) {}
  }

  /// Returns the cached icon bytes for [url]'s domain, kicking off a fetch
  /// on miss. Never throws; returns null when no icon can be found.
  static Future<Uint8List?> iconFor(String url) async {
    final domain = _domainOf(url);
    if (domain == null) return null;

    if (_memory.containsKey(domain)) return _memory[domain];

    final cache = _loadCache();
    final entry = cache[domain];
    if (entry is Map && entry['data'] is String && entry['ts'] is num) {
      final ageMs =
          DateTime.now().millisecondsSinceEpoch - (entry['ts'] as num).toInt();
      if (ageMs < ttl.inMilliseconds) {
        final bytes = _decodeDataUrl(entry['data'] as String);
        if (bytes != null) {
          _memory[domain] = bytes;
          return bytes;
        }
      }
    }

    if (_inFlight.contains(domain)) return null; // retry next build
    _inFlight.add(domain);
    try {
      final bytes = await _fetchIcon(domain);
      if (bytes != null) {
        _memory[domain] = bytes;
        final mime = _sniffMime(bytes);
        cache[domain] = {
          'data': 'data:$mime;base64,${base64Encode(bytes)}',
          'ts': DateTime.now().millisecondsSinceEpoch,
        };
        _persistCache();
      } else {
        _memory[domain] = null;
      }
      return bytes;
    } finally {
      _inFlight.remove(domain);
    }
  }

  static Future<Uint8List?> _fetchIcon(String domain) async {
    final candidates = [
      'https://$domain/favicon.ico',
      'https://icons.duckduckgo.com/ip3/$domain.ico',
    ];
    for (final uri in candidates) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse(uri));
        final response = await request.close().timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) {
          client.close(force: true);
          continue;
        }
        final type = response.headers.contentType?.mimeType ?? '';
        if (!type.startsWith('image/')) {
          client.close(force: true);
          continue;
        }
        final bytes = await response.foldBytes();
        client.close(force: true);
        if (bytes.isEmpty || bytes.length > 200 * 1024) continue;
        return bytes;
      } catch (_) {
        // try the next candidate
      }
    }
    return null;
  }

  static String? _domainOf(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _decodeDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:') || comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static String _sniffMime(Uint8List bytes) {
    if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
    if (bytes.length > 2 && bytes[0] == 0x47 && bytes[1] == 0x49) return 'image/gif';
    if (bytes.length > 3 && bytes[0] == 0x52 && bytes[1] == 0x49) return 'image/webp';
    if (bytes.length > 2 && bytes[0] == 0x00 && bytes[1] == 0x00) return 'image/x-icon';
    return 'image/png';
  }
}

extension on HttpClientResponse {
  Future<Uint8List> foldBytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in this) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
