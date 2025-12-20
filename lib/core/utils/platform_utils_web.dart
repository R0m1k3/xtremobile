/// Platform-specific utilities for web
/// This file is used when compiling for web
library;

import 'dart:html' as html;

/// Check if we're running on HTTPS
bool isHttps() {
  return html.window.location.protocol == 'https:';
}

/// Get the current window origin
String getWindowOrigin() {
  return html.window.location.origin;
}
