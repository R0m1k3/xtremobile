import 'dns_service.dart';

/// [P2-1 FIX] DNS Resolver now delegates to Unified DNS Service
///
/// This class is now a thin wrapper around UnifiedDnsService
/// to maintain backward compatibility while consolidating DNS logic.
/// All DNS calls now share a single cache and request deduplication.
class DnsResolver {
  static final UnifiedDnsService _dnsService = UnifiedDnsService();

  /// Resolve hostname to IP address using DoH (delegates to unified service)
  /// Returns null if resolution fails
  /// Uses shared cache to prevent duplicate calls
  static Future<String?> resolve(String hostname) async {
    return _dnsService.resolve(hostname);
  }

  /// Clear the DNS cache (delegates to unified service)
  static void clearCache() {
    _dnsService.clearCache();
  }

  /// Get cache stats for debugging
  static Map<String, dynamic> getCacheStats() {
    return _dnsService.getCacheStats();
  }
}
