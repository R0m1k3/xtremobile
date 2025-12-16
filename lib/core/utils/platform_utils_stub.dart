/// Platform-specific utilities for web
/// This file is used when compiling for web

/// Check if we're running on HTTPS
bool isHttps() {
  // Implemented in platform_utils_web.dart
  return true;
}

/// Get the current window origin
String getWindowOrigin() {
  // Implemented in platform_utils_web.dart
  return '';
}
