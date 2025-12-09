import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API Client for communicating with the backend
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  
  late final Dio _dio;
  String? _token;

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _getBaseUrl(),
      headers: {'Content-Type': 'application/json'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),);
    
    // Add interceptor for logging
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ),);
  }

  /// Get base URL (same origin for production)
  String _getBaseUrl() {
    // For mobile, this needs to be configured or passed in.
    // For now, returning empty string implies relative path (works for web).
    // TODO: Configure base URL for mobile
    return '';
  }

  /// Set authentication token
  Future<void> setToken(String? token) async {
    _token = token;
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
      // Store in SharedPreferences for persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } else {
      _dio.options.headers.remove('Authorization');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    }
  }

  /// Get stored token from memory
  String? getToken() {
    return _token;
  }

  /// Restore token from SharedPreferences
  Future<void> restoreToken() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('auth_token');
    if (storedToken != null) {
      // We call setToken but avoid the async loop? 
      // Just set memory and header directly to avoid double SP call
      _token = storedToken;
      _dio.options.headers['Authorization'] = 'Bearer $storedToken';
    }
  }

  /// Clear token
  Future<void> clearToken() async {
    await setToken(null);
  }

  /// GET request
  Future<Response> get(String path) async {
    return _dio.get(path);
  }

  /// POST request
  Future<Response> post(String path, {dynamic data}) async {
    return _dio.post(path, data: data);
  }

  /// PUT request
  Future<Response> put(String path, {dynamic data}) async {
    return _dio.put(path, data: data);
  }

  /// DELETE request
  Future<Response> delete(String path) async {
    return _dio.delete(path);
  }
}
