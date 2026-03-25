/// Platform utilities for Android
/// 
/// These utilities handle Android-specific behavior.
/// Android doesn't have same-origin policy restrictions like web platforms.
library;

/// Check if we're running on HTTPS (not applicable for Android)
/// Android apps don't have same-origin restrictions, so we always return false
bool isHttps() {
  // Android doesn't have same-origin policy restrictions
  // So we never need the HTTPS bridge proxy
  return false;
}

/// Get the window origin (not applicable for Android)
/// Android doesn't have a "window" concept, returns empty string
String getWindowOrigin() {
  // Android doesn't have a window origin
  // Returns empty string as it's never used with isHttps() == false
  return '';
}
