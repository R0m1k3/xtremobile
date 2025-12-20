import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class IpService {
  static final IpService _instance = IpService._internal();

  factory IpService() {
    return _instance;
  }

  IpService._internal();

  String? _cachedCountry;
  String? _cachedCountryCode;

  Future<void> fetchIpDetails() async {
    if (_cachedCountry != null) return;

    try {
      // Using ip-api.com (free tier, HTTP)
      final response = await http.get(Uri.parse('http://ip-api.com/json'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          _cachedCountry = data['country'];
          _cachedCountryCode = data['countryCode'];
          debugPrint(
            'IpService: Detected country: $_cachedCountry ($_cachedCountryCode)',
          );
        }
      }
    } catch (e) {
      debugPrint('IpService: Error fetching IP details: $e');
    }
  }

  String? get country => _cachedCountry;
  String? get countryCode => _cachedCountryCode;
}
