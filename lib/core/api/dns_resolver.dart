import 'dart:convert';
import 'dart:io';

/// DNS Resolver utility using DNS-over-HTTPS
/// Provides manual hostname resolution when system DNS fails
class DnsResolver {
  static final Map<String, String> _cache = {};

  /// Resolve hostname to IP address using DoH
  /// Returns null if resolution fails
  static Future<String?> resolve(String hostname) async {
    // Check cache first
    if (_cache.containsKey(hostname)) {
      print('DnsResolver: Cache hit for $hostname -> ${_cache[hostname]}');
      return _cache[hostname];
    }

    print('DnsResolver: Attempting to resolve $hostname');

    // Try Google DNS via IP (8.8.8.8) - NO DNS NEEDED!
    String? ip = await _queryDoH(
      'https://8.8.8.8/resolve?name=$hostname&type=A',
    );

    // Fallback to Cloudflare via IP (1.1.1.1)
    ip ??= await _queryDoH(
      'https://1.1.1.1/dns-query?name=$hostname&type=A',
      headers: {'accept': 'application/dns-json'},
    );

    if (ip != null) {
      print('DnsResolver: Resolved $hostname -> $ip');
      _cache[hostname] = ip;
    } else {
      print('DnsResolver: Failed to resolve $hostname');
    }

    return ip;
  }

  static Future<String?> _queryDoH(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));
      request.headers.add('accept', 'application/dns-json');
      if (headers != null) {
        headers.forEach((k, v) => request.headers.add(k, v));
      }

      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);

        if (json['Status'] == 0 && json['Answer'] != null) {
          final answers = json['Answer'] as List;
          for (final ans in answers) {
            if (ans['type'] == 1) {
              // Type A
              client.close();
              return ans['data'];
            }
          }
        }
      }
      client.close();
    } catch (e) {
      print('DnsResolver: DoH query failed: $e');
    }
    return null;
  }

  /// Clear the DNS cache
  static void clearCache() {
    _cache.clear();
  }
}
