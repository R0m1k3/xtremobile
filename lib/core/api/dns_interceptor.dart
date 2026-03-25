import 'dart:io';
import 'package:dio/dio.dart';
import 'dns_service.dart';

/// [P2-1 FIX] DNS Fallback Interceptor using Unified DNS Service
/// Consolidates with DnsResolver to share a single cache
/// Prevents duplicate DNS calls for the same hostname
class DnsFallbackInterceptor extends Interceptor {
  final Dio _dio;
  final UnifiedDnsService _dnsService = UnifiedDnsService();

  DnsFallbackInterceptor(this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Check for connection/host lookup errors
    if (_isDnsError(err)) {
      final uri = err.requestOptions.uri;
      final host = uri.host;

      // Use unified DNS service (shared cache, deduplication)
      final ip = await _dnsService.resolve(host);

      if (ip != null) {
        try {
          // Clone options but replace host with IP
          final newUri = uri.replace(host: ip);
          final options = err.requestOptions.copyWith(path: newUri.toString());

          // IMPORTANT: Set Host header so the server handles it correctly
          options.headers['Host'] = host;

          // Retry request with resolved IP
          final response = await _dio.fetch(options);
          return handler.resolve(response);
        } catch (e) {
          // Retry with resolved IP failed
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
}
