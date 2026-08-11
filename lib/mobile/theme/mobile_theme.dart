import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// XtremFlow Mobile Theme — "Warm Cinema", phone-scaled.
///
/// Derived from [AppTheme] rather than redefined: the palette, typography and
/// component styling stay in one place, and this layer only shrinks the type
/// scale and tightens paddings for a handset.
class MobileTheme {
  MobileTheme._();

  // ============ SPACING ============
  static const double spacing4 = AppTheme.spacing4;
  static const double spacing8 = AppTheme.spacing8;
  static const double spacing12 = AppTheme.spacing12;
  static const double spacing16 = AppTheme.spacing16;
  static const double spacing24 = AppTheme.spacing24;

  // ============ RADIUS ============
  static const double radiusSm = AppTheme.radiusSm;
  static const double radiusMd = AppTheme.radiusMd;
  static const double radiusLg = AppTheme.radiusLg;

  /// Phone type scale: display sizes come down ~20%, body stays legible.
  static TextTheme _mobileTextTheme(TextTheme base) {
    TextStyle? shrink(TextStyle? style, double factor) {
      if (style?.fontSize == null) return style;
      return style!.copyWith(fontSize: style.fontSize! * factor);
    }

    return base.copyWith(
      displayLarge: shrink(base.displayLarge, 0.70),
      displayMedium: shrink(base.displayMedium, 0.76),
      displaySmall: shrink(base.displaySmall, 0.84),
      headlineLarge: shrink(base.headlineLarge, 0.78),
      headlineMedium: shrink(base.headlineMedium, 0.86),
      headlineSmall: shrink(base.headlineSmall, 0.92),
      titleLarge: shrink(base.titleLarge, 0.94),
      bodyLarge: shrink(base.bodyLarge, 0.90),
      bodyMedium: shrink(base.bodyMedium, 0.92),
    );
  }

  static ThemeData _scaled(ThemeData base) {
    return base.copyWith(
      textTheme: _mobileTextTheme(base.textTheme),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing16,
          vertical: spacing12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing12),
          ),
        ),
      ),
    );
  }

  // ============ DARK THEME (Mobile Main) ============
  static ThemeData get darkTheme => _scaled(AppTheme.darkTheme);

  // ============ LIGHT THEME ============
  static ThemeData get lightTheme => _scaled(AppTheme.lightTheme);

  /// Returns the appropriate MobileTheme based on the current [BuildContext]
  /// brightness.
  static ThemeData themeOf(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkTheme : lightTheme;
  }

  /// Accent used for active/selected affordances on mobile.
  static const Color accent = AppColors.primaryContainer;
}
