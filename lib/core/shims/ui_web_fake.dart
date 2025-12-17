// Fake implementation for non-web platforms
class PlatformViewRegistry {
  /// Dummy implementation of registerViewFactory
  void registerViewFactory(String viewId, dynamic cb) {
    // No-op on non-web platforms
  }
}

/// Global instance to match dart:ui_web API
final platformViewRegistry = PlatformViewRegistry();
