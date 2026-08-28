import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// XtremFlow — "Apple Glass Gray" theme.
///
/// Typography: **Fraunces** (serif éditorial) for display/headline, **Karla**
/// (humaniste chaud) for UI and body — very legible at TV distance and on a
/// phone held at arm's length.
class AppTheme {
  AppTheme._();

  // ============ SPACING (8pt base) ============
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0;

  // Semantic aliases
  static const double spacingXs = spacing4;
  static const double spacingSm = spacing8;
  static const double spacingMd = spacing16;
  static const double spacingLg = spacing24;
  static const double spacingXl = spacing32;

  // ============ RADIUS ============
  static const double radiusNone = 0.0;
  static const double radiusXs = 4.0;
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 9999.0;

  // ============ ANIMATION ============
  static const Duration durationXs = Duration(milliseconds: 120);
  static const Duration durationFast = Duration(milliseconds: 180);
  static const Duration durationNormal = Duration(milliseconds: 260);
  static const Duration durationMd = Duration(milliseconds: 260);
  static const Duration durationLg = Duration(milliseconds: 380);
  static const Duration durationXl = Duration(milliseconds: 520);

  static const Curve curveDefault = Curves.easeOutCubic;
  static const Curve curveSmooth = Curves.easeOutCubic;

  /// Ouverture de rideau — décélération très longue, "cinéma".
  static const Curve curveCinema = Cubic(0.16, 1.0, 0.3, 1.0);

  // ============ TYPOGRAPHY HELPERS ============

  /// Display serif éditorial — titres, héros, chiffres marquants.
  static TextStyle display({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
    FontStyle? fontStyle,
  }) {
    return GoogleFonts.fraunces(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      fontStyle: fontStyle,
    );
  }

  /// Corps / UI — humaniste chaud, très lisible à distance.
  static TextStyle body({
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color color = AppColors.onSurface,
  }) {
    return GoogleFonts.karla(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  /// Micro-label capitales espacées — « GÉNÉRIQUE DE FILM ».
  static TextStyle eyebrow({
    double fontSize = 11,
    Color color = AppColors.textTertiary,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return GoogleFonts.karla(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 1.6,
      height: 1.1,
      color: color,
    );
  }

  static TextTheme _textTheme({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      displayLarge: display(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.03,
        color: primary,
      ),
      displayMedium: display(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        height: 1.08,
        color: primary,
      ),
      displaySmall: display(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.15,
        color: primary,
      ),
      headlineLarge: display(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.12,
        color: primary,
      ),
      headlineMedium: display(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.2,
        color: primary,
      ),
      headlineSmall: display(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: primary,
      ),
      titleLarge: body(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: primary,
      ),
      titleMedium: body(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: primary,
      ),
      titleSmall: body(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: primary,
      ),
      bodyLarge: body(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: secondary,
      ),
      bodyMedium: body(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: secondary,
      ),
      bodySmall: body(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: secondary,
      ),
      labelLarge: body(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: primary,
      ),
      labelMedium: body(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: primary,
      ),
    );
  }

  // ============ DARK THEME (principal) ============
  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);

    return baseTheme.copyWith(
      colorScheme: AppColors.darkColorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashColor: AppColors.primaryContainer.withValues(alpha: 0.12),
      highlightColor: AppColors.primaryContainer.withValues(alpha: 0.08),

      textTheme: _textTheme(
        primary: AppColors.textPrimary,
        secondary: AppColors.textSecondary,
      ),

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: Color(0x590A84FF),
        selectionHandleColor: AppColors.primaryContainer,
      ),

      // AppBar: transparente — le dégradé de fond passe au travers.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: display(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainerLow,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textTertiary,
        selectedLabelStyle: body(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: body(fontSize: 11, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing16,
          vertical: spacing16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(
            color: AppColors.primaryContainer,
            width: 2,
          ),
        ),
        hintStyle: body(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textTertiary,
        ),
      ),

      // Boutons : remplissage braise, texte crème (contraste AA).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryFill,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing24,
            vertical: spacing16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: body(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: body(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: AppColors.glassLevel2Border),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: AppColors.glassLevel2Border),
        ),
        titleTextStyle: display(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: body(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),

      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primaryContainer,
        inactiveTrackColor: AppColors.onSurface24,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x290A84FF),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryContainer,
        linearTrackColor: AppColors.onSurface12,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryFill
              : AppColors.surfaceContainerHigh,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.onSurface12,
        thickness: 1,
      ),
    );
  }

  // ============ LIGHT THEME (gris système clair) ============
  static ThemeData get lightTheme {
    final baseTheme = ThemeData.light(useMaterial3: true);

    const bgColor = Color(0xFFF2F2F7);
    const surfaceColor = Color(0xFFFFFFFF);
    const primaryColor = Color(0xFF0066CC);
    const textPrimaryColor = Color(0xFF1C1C1E);
    const textSecondaryColor = Color(0xFF48484E);
    const textTertiaryColor = Color(0xFF8E8E93);
    const borderColor = Color(0xFFD8D8DE);

    return baseTheme.copyWith(
      colorScheme: AppColors.lightColorScheme,
      scaffoldBackgroundColor: bgColor,
      canvasColor: bgColor,

      textTheme: _textTheme(
        primary: textPrimaryColor,
        secondary: textSecondaryColor,
      ),

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionColor: Color(0x4D0066CC),
        selectionHandleColor: primaryColor,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: textPrimaryColor,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: borderColor,
        centerTitle: true,
        titleTextStyle: display(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: textPrimaryColor,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondaryColor,
        selectedLabelStyle: body(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: body(fontSize: 11, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing16,
          vertical: spacing16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        hintStyle: body(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textTertiaryColor,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing24,
            vertical: spacing16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: body(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: borderColor),
        ),
        shadowColor: borderColor,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        elevation: 8,
        shadowColor: borderColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: borderColor),
        ),
        titleTextStyle: display(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimaryColor,
        ),
        contentTextStyle: body(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textSecondaryColor,
        ),
      ),

      dividerTheme: const DividerThemeData(color: borderColor, thickness: 1),
    );
  }
}
