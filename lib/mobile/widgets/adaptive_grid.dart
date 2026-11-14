import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Grids that follow the screen width instead of a fixed column count.
///
/// A Fire TV (≈ 960 dp wide) keeps the historical column counts; a phone in
/// portrait gets fewer, larger tiles; a wide desktop/web window gets more.
class AdaptiveGrid {
  AdaptiveGrid._();

  /// Horizontal padding the tabs put around their grids.
  static const double horizontalPadding = 16;

  static int columns(
    BuildContext context, {
    required int tv,
    required int phone,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return phone;
    if (width < 900) return ((tv + phone) / 2).round();
    return math.max(tv, (tv * width / 960).floor());
  }

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  /// Live TV groups and channels: squares on TV, slightly wider on a phone.
  static SliverGridDelegate liveTiles(BuildContext context) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns(context, tv: 5, phone: 2),
      childAspectRatio: isCompact(context) ? 1.2 : 1.0,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );
  }

  /// Movie / series groups: wide tiles.
  static SliverGridDelegate categoryTiles(BuildContext context) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns(context, tv: 6, phone: 2),
      childAspectRatio: isCompact(context) ? 2.4 : 2.0,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );
  }

  /// Posters: a 2:3 image plus the title line under it, so the title never
  /// overflows the cell.
  static SliverGridDelegate posters(BuildContext context) {
    const spacing = 10.0;
    final count = columns(context, tv: 8, phone: 3);
    final width = MediaQuery.sizeOf(context).width - 2 * horizontalPadding;
    final tileWidth = (width - spacing * (count - 1)) / count;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: count,
      mainAxisExtent: tileWidth * 1.5 + 26,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );
  }
}
