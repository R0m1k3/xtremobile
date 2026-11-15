import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The three ways the app is used, each with its own navigation and density.
enum FormFactor {
  /// Fire TV / Android TV: remote control, D-pad focus, seen from 3 m.
  tv,

  /// Touch, shortest side ≥ 600 dp (tablet, or the web build on a desktop).
  tablet,

  /// Touch, handset.
  phone,
}

/// Detects the form factor. TV is a device capability, not a width: a
/// landscape tablet (1280 dp) is wider than a Fire TV (960 dp at 1080p), so
/// width alone would hand the TV layout to tablets.
class FormFactors {
  FormFactors._();

  static bool _isTv = false;

  /// True on Android TV / Fire TV (leanback feature).
  static bool get isTv => _isTv;

  /// Lets widget tests pick a form factor.
  @visibleForTesting
  static set debugIsTv(bool value) => _isTv = value;

  /// Call once at startup, before `runApp`.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _isTv = isTvFeatureSet(info.systemFeatures);
    } catch (e) {
      debugPrint('XtremFlow: TV detection failed, assuming touch device: $e');
    }
  }

  /// Leanback is declared by Android TV and Fire TV alike.
  static bool isTvFeatureSet(List<String> features) =>
      features.contains('android.software.leanback') ||
      features.contains('android.software.leanback_only') ||
      features.contains('amazon.hardware.fire_tv');

  static FormFactor of(BuildContext context) {
    if (_isTv) return FormFactor.tv;
    return MediaQuery.sizeOf(context).shortestSide >= 600
        ? FormFactor.tablet
        : FormFactor.phone;
  }
}
