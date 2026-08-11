import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-aware decoration helpers — "Warm Cinema" charter.
///
/// Depth comes from warm shadows and contrast, never from `BackdropFilter`:
/// a blur layer repaints every frame and is the first thing to drop frames on
/// low-end Android.
class AppDecorations {
  AppDecorations._();

  // Force Dark mode for the IPTV experience regardless of system theme.
  static bool _isDark(BuildContext context) => true;

  // ─── Backgrounds ────────────────────────────────────────────────────────────

  /// Full-screen gradient background for tab content areas.
  static BoxDecoration background(BuildContext context) {
    if (_isDark(context)) {
      return const BoxDecoration(gradient: AppColors.backgroundGradient);
    }
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFBF3EC), Color(0xFFEFE2D6)],
        stops: [0.0, 1.0],
      ),
    );
  }

  // ─── Nav Pill ────────────────────────────────────────────────────────────────

  /// Floating pill navigation bar background.
  static BoxDecoration navPill(BuildContext context) {
    if (_isDark(context)) {
      return BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.glassLevel2Border, width: 1),
        boxShadow: AppColors.lift(),
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(40),
      border: Border.all(color: const Color(0x1A201A16), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A201A16),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  // ─── Cards ───────────────────────────────────────────────────────────────────

  /// Category / channel card — primary card style.
  static BoxDecoration glossyCard(
    BuildContext context, {
    double radius = 16,
  }) {
    if (_isDark(context)) {
      return BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.glassLevel2Border, width: 1),
        boxShadow: AppColors.lift(intensity: 0.8),
      );
    }
    return BoxDecoration(
      color: const Color(0xFFFBF3EC),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x1A201A16), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14201A16),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  /// Warm highlight overlay — placed on top of a card Stack.
  static BoxDecoration glossShimmer(
    BuildContext context, {
    double radius = 16,
  }) {
    if (_isDark(context)) {
      return BoxDecoration(
        gradient: AppColors.cardHighlight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      );
    }
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x0A201A16), Color(0x00201A16)],
        stops: [0.0, 0.55],
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
    );
  }

  /// Smaller channel card base (top area behind the logo).
  static BoxDecoration channelCardBase(BuildContext context) {
    if (_isDark(context)) {
      return const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surfaceContainerHigh,
            AppColors.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          top: BorderSide(color: AppColors.glassLevel2Border, width: 0.5),
        ),
      );
    }
    return const BoxDecoration(
      color: Color(0xFFEFE2D6),
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    );
  }

  // ─── Search Bar ──────────────────────────────────────────────────────────────

  /// Search / text field container.
  static BoxDecoration searchBar(BuildContext context) {
    if (_isDark(context)) {
      return BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassLevel2Border, width: 1),
      );
    }
    return BoxDecoration(
      color: const Color(0xFFF3E7DB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x18201A16), width: 1),
    );
  }

  // ─── Colours ─────────────────────────────────────────────────────────────────

  static Color textPrimary(BuildContext context) =>
      _isDark(context) ? AppColors.textPrimary : const Color(0xFF201A16);

  static Color textSecondary(BuildContext context) =>
      _isDark(context) ? AppColors.textSecondary : const Color(0xFF52443B);

  static Color iconMuted(BuildContext context) =>
      _isDark(context) ? AppColors.onSurface38 : Colors.black26;

  static Color divider(BuildContext context) =>
      _isDark(context) ? AppColors.onSurface12 : const Color(0x1A201A16);
}
