import 'package:flutter/material.dart';

/// XtremFlow Apple TV Grey Glossy Palette
///
/// Premium Apple TV design language:
/// - Background: Deep dark grey (#1C1C1E) to black (#000000) gradient
/// - Surface cards: Glossy dark grey (#2C2C2E to #3A3A3C) with glass reflections
/// - Primary accent: Bright white (#FFFFFF) and light grey (#EBEBF5)
/// - Secondary accent: Apple Blue (#0A84FF)
/// - Borders: Subtle white 8% opacity for glass effect
/// - Glossy highlight: White 10-15% at top fading to transparent
class AppColors {
  AppColors._();

  // ============ BACKGROUNDS ============
  /// Pure black — infinite depth, OLED-friendly
  static const Color background = Color(0xFF000000);

  /// Apple deep dark grey — primary app background (alias)
  static const Color backgroundSecondary = Color(0xFF1C1C1E);

  /// Apple deep dark grey — primary surface
  static const Color surface = Color(0xFF1C1C1E);

  /// Mid grey — elevated cards, sheets
  static const Color surfaceVariant = Color(0xFF2C2C2E);

  /// Light grey surface — tertiary elevation
  static const Color surfaceElevated = Color(0xFF3A3A3C);

  /// Focus/selected element background
  static const Color focusColor = Color(0xFFFFFFFF);

  // ============ ACCENTS ============
  /// Primary: Pure white — focus rings, active labels
  static const Color primary = Color(0xFFFFFFFF);

  /// Light grey — secondary text / inactive elements
  static const Color accent = Color(0xFFEBEBF5);

  /// Apple Blue — CTAs, links, active indicators
  static const Color appleBlue = Color(0xFF0A84FF);

  // ============ GRADIENTS ============

  /// Apple TV background: deep dark top → pure black bottom
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1C1C1E), // Deep dark grey
      Color(0xFF000000), // Pure black
    ],
    stops: [0.0, 1.0],
  );

  /// Legacy alias for backward compatibility
  static const RadialGradient appleTvGradient = RadialGradient(
    center: Alignment.center,
    radius: 1.5,
    colors: [
      Color(0xFF1A1A1C), // Slightly lighter than pure black
      Color(0xFF000000), // Pure black edge
    ],
    stops: [0.0, 1.0],
  );

  /// Glossy card gradient: bright highlight at top fading to dark base
  static const LinearGradient glossyCardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF484848), // Lighter top for gloss highlight
      Color(0xFF2C2C2E), // Dark mid
      Color(0xFF1C1C1E), // Deeper bottom
    ],
    stops: [0.0, 0.45, 1.0],
  );

  /// Glossy inner highlight (white shimmer layer, overlaid on top of card)
  static const LinearGradient glossyHighlight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x26FFFFFF), // White ~15% at top
      Color(0x00FFFFFF), // Transparent at bottom
    ],
    stops: [0.0, 0.5],
  );

  /// Card glossy gradient (Apple TV spec alias — dark base)
  static const LinearGradient cardGlossyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF48484A), Color(0xFF2C2C2E)],
  );

  /// Card glossy highlight (Apple TV spec alias — top-left shimmer)
  static const LinearGradient cardGlossyHighlight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.5],
  );

  /// Primary silver gradient (used for buttons/badges)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFCCCCCC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ TEXT ============
  /// Pure white — headings, active labels
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Light grey 60% — secondary info, captions
  static const Color textSecondary = Color(0x99EBEBF5); // #EBEBF5 @ 60%

  /// Darker grey — hints, placeholders
  static const Color textTertiary = Color(0xFF636366);

  // ============ FUNCTIONAL COLORS ============
  static const Color success = Color(0xFF30D158); // Apple Green
  static const Color warning = Color(0xFFFF9F0A); // Apple Orange
  static const Color error = Color(0xFFFF453A);   // Apple Red
  static const Color live = Color(0xFFFF453A);    // Apple Red (live badge)

  // ============ BORDERS ============
  /// Invisible border — unfocused state
  static const Color border = Color(0xFF2C2C2E);

  /// Glass border: white at 8% opacity for subtle edge definition
  static const Color glassBorderColor = Color(0x14FFFFFF); // 8% white

  /// Focus border: pure white ring
  static const Color focusBorder = Color(0xFFFFFFFF);

  /// Alias: focused border — pure white (Apple TV spec)
  static const Color borderFocused = Color(0xFFFFFFFF);

  // ============ GLASSMORPHISM ============
  static final Color glassBackground = const Color(0xFF1E1E1E).withValues(alpha: 0.75);
  static final Color glassBorder = const Color(0xFFFFFFFF).withValues(alpha: 0.08);

  // ============ THEME SCHEMES ============
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: appleBlue,
        secondary: accent,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: textPrimary,
        onError: Colors.white,
        brightness: Brightness.dark,
      );

  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: Colors.black,
        secondary: Colors.grey,
        surface: Color(0xFFF2F2F7),
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.black,
        onError: Colors.white,
        brightness: Brightness.light,
      );
}
