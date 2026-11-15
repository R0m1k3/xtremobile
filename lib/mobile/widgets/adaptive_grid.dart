import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:xtremobile/core/utils/form_factor.dart';

/// Grids sized from the space they actually get (the TV and tablet rails take
/// part of the screen), with one density per form factor.
class AdaptiveGrid {
  AdaptiveGrid._();

  /// Horizontal padding the tabs put around their grids on touch screens.
  static const double horizontalPadding = 16;

  /// Space under a poster for its title and meta line.
  static const double posterCaption = 52;

  static bool isCompact(BuildContext context) =>
      FormFactors.of(context) == FormFactor.phone;

  /// Movie / series groups: one row per group on a phone, 2–3 columns of
  /// rows on a tablet, the 72 dp cards of the Live TV grid on TV.
  static SliverGridDelegate categoryTiles(BuildContext context) {
    switch (FormFactors.of(context)) {
      case FormFactor.tv:
        return const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 72,
          mainAxisSpacing: 12,
          crossAxisSpacing: 16,
        );
      case FormFactor.tablet:
        return const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 360,
          mainAxisExtent: 64,
          mainAxisSpacing: 8,
          crossAxisSpacing: 12,
        );
      case FormFactor.phone:
        return const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 1,
          mainAxisExtent: 64,
          mainAxisSpacing: 8,
        );
    }
  }

  /// Posters: a 2:3 image plus [posterCaption] under it. Six per row on TV,
  /// three on a phone, as many ~150 dp columns as fit on a tablet.
  static SliverGridDelegate posters(BuildContext context) {
    switch (FormFactors.of(context)) {
      case FormFactor.tv:
        return const _PosterGridDelegate(count: 6, spacing: 16);
      case FormFactor.tablet:
        return const _PosterGridDelegate(minTileWidth: 150, spacing: 16);
      case FormFactor.phone:
        return const _PosterGridDelegate(count: 3, spacing: 12);
    }
  }

  /// Kept for older call sites.
  static SliverGridDelegate liveTiles(BuildContext context) =>
      categoryTiles(context);
}

class _PosterGridDelegate extends SliverGridDelegate {
  const _PosterGridDelegate({
    this.count,
    this.minTileWidth,
    required this.spacing,
  }) : assert(count != null || minTileWidth != null);

  final int? count;
  final double? minTileWidth;
  final double spacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final extent = constraints.crossAxisExtent;
    final columns = count ??
        math.max(3, ((extent + spacing) / (minTileWidth! + spacing)).floor());
    final tileWidth = (extent - spacing * (columns - 1)) / columns;
    final tileHeight = tileWidth * 1.5 + AdaptiveGrid.posterCaption;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: tileHeight + spacing,
      crossAxisStride: tileWidth + spacing,
      childMainAxisExtent: tileHeight,
      childCrossAxisExtent: tileWidth,
      reverseCrossAxis: false,
    );
  }

  @override
  bool shouldRelayout(_PosterGridDelegate oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.minTileWidth != minTileWidth ||
      oldDelegate.spacing != spacing;
}
