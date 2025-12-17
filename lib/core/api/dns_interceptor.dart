import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Interceptor to fallback to DNS-over-HTTPS if standard DNS fails
/// Useful for emulators or restricted networks
class DnsFallbackInterceptor extends Interceptor {
  final Dio _dio;

  // Cache for resolved IPs
  final Map<String, String> _dnsCache = {};

  DnsFallbackInterceptor(this._dio);

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    // Basic check for connection/host lookup errors
    if (_isDnsError(err)) {
      final uri = err.requestOptions.uri;
      final host = uri.host;

      print('DnsFallback: Caught DNS error for $host');

      // Check cache first
      String? ip = _dnsCache[host];

      if (ip == null) {
        try {
          // Attempt resolution attempts
          print('DnsFallback: Attempting DoH resolution...');
          ip = await _resolveWithDoH(host);

          if (ip != null) {
            print('DnsFallback: Resolved $host to $ip');
            _dnsCache[host] = ip;
          } else {
            print('DnsFallback: Failed to resolve $host');
          }
        } catch (e) {
          print('DnsFallback: Resolution error: $e');
          return handler.next(err);
        }
      }

      if (ip != null) {
        try {
          // Clone options but replace host with IP
          final newUri = uri.replace(host: ip);
          final options = err.requestOptions.copyWith(path: newUri.toString());

          // IMPORTANT: Set Host header so the server handles it correctly
          options.headers['Host'] = host;

          // Retry request
          print('DnsFallback: Retrying request to $ip');
          final response = await _dio.fetch(options);
          return handler.resolve(response);
        } catch (e) {
          print('DnsFallback: Retry failed: $e');
          return handler.next(err);
        }
      }
    }

    handler.next(err);
  }

  bool _isDnsError(DioException err) {
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.unknown) {
      if (err.error is SocketException) {
        final msg = (err.error as SocketException).message;
        return msg.contains('Failed host lookup') ||
            msg.contains('No address associated with hostname');
      }
    }
    return false;
  }

  /// Resolve hostname using multiple DoH providers
  Future<String?> _resolveWithDoH(String hostname) async {
    // 1. Google DNS (8.8.8.8)
    String? ip =
        await _queryDoH('https://8.8.8.8/resolve?name=$hostname&type=A');
    if (ip != null) return ip;

    // 2. Cloudflare DNS (1.1.1.1)
    ip = await _queryDoH(
      'https://1.1.1.1/dns-query?name=$hostname&type=A',
      headers: {'accept': 'application/dns-json'},
    );
    if (ip != null) return ip;

    return null;
  }

  Future<String?> _queryDoH(String url, {Map<String, String>? headers}) async {
    try {
      // Create a raw HttpClient to avoid loop and control SSL
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) =>
            true; // IGNORE SSL ERRORS just for DoH IP connectivity

      final request = await client.getUrl(Uri.parse(url));
      if (headers != null) {
        headers.forEach((k, v) => request.headers.add(k, v));
      }

      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);

        // Google/Cloudflare JSON format
        if (json['Status'] == 0 && json['Answer'] != null) {
          final answers = json['Answer'] as List;
          for (final ans in answers) {
            if (ans['type'] == 1) {
              // Type A record
              return ans['data'];
            }
          }
        }
      }
    } catch (e) {
      print('DnsFallback: DoH query to $url failed: $e');
    }
    return null;
  }
}
