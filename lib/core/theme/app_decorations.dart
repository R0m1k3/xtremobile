import 'package:flutter/material.dart';

/// Theme-aware decoration helpers.
/// Returns dark (Apple TV glossy) or light (iOS clean white) styles
/// based on current [BuildContext] brightness.
class AppDecorations {
  AppDecorations._();

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // ─── Backgrounds ────────────────────────────────────────────────────────────

  /// Full-screen gradient background for tab content areas.
  static BoxDecoration background(BuildContext context) {
    if (_isDark(context)) {
      return const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C1C1E), Color(0xFF000000)],
          stops: [0.0, 1.0],
        ),
      );
    }
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEAEAF0), Color(0xFFD8D8E0)],
        stops: [0.0, 1.0],
      ),
    );
  }

  // ─── Nav Pill ────────────────────────────────────────────────────────────────

  /// Floating pill navigation bar background.
  static BoxDecoration navPill(BuildContext context) {
    if (_isDark(context)) {
      return BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color(0x20FFFFFF), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 20,
            spreadRadius: 0,
            offset: Offset(0, 6),
          ),
        ],
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(40),
      border: Border.all(color: const Color(0x1A000000), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 16,
          spreadRadius: 0,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  // ─── Cards ───────────────────────────────────────────────────────────────────

  /// Glossy category / channel card — primary card style.
  static BoxDecoration glossyCard(
    BuildContext context, {
    double radius = 16,
  }) {
    if (_isDark(context)) {
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A4A4E), Color(0xFF1C1C1E)],
          stops: [0.0, 1.0],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x28FFFFFF), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 20,
            spreadRadius: 0,
            offset: Offset(0, 8),
          ),
        ],
      );
    }
    return BoxDecoration(
      color: const Color(0xFFF2F2F7),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0x1A000000), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 8,
          spreadRadius: 0,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  /// Gloss shimmer overlay — placed on top-left of a card Stack.
  static BoxDecoration glossShimmer(
    BuildContext context, {
    double radius = 16,
  }) {
    if (_isDark(context)) {
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
          stops: [0.0, 0.55],
        ),
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(radius)),
      );
    }
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x0A000000), Color(0x00000000)],
        stops: [0.0, 0.55],
      ),
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(radius)),
    );
  }

  /// Smaller channel card base (top area behind the logo).
  static BoxDecoration channelCardBase(BuildContext context) {
    if (_isDark(context)) {
      return const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A3A3C), Color(0xFF1C1C1E)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      );
    }
    return const BoxDecoration(
      color: Color(0xFFE4E4EC),
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    );
  }

  // ─── Search Bar ──────────────────────────────────────────────────────────────

  /// Search / text field container.
  static BoxDecoration searchBar(BuildContext context) {
    if (_isDark(context)) {
      return BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x18FFFFFF), width: 1),
      );
    }
    return BoxDecoration(
      color: const Color(0xFFEEEEF4),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x18000000), width: 1),
    );
  }

  // ─── Colours ─────────────────────────────────────────────────────────────────

  static Color textPrimary(BuildContext context) =>
      _isDark(context) ? Colors.white : const Color(0xFF000000);

  static Color textSecondary(BuildContext context) =>
      _isDark(context)
          ? const Color(0x99EBEBF5)
          : const Color(0x993C3C43);

  static Color iconMuted(BuildContext context) =>
      _isDark(context) ? Colors.white38 : Colors.black26;

  static Color divider(BuildContext context) =>
      _isDark(context)
          ? const Color(0x1FFFFFFF)
          : const Color(0x1A000000);
}
