import 'package:flutter/material.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';
import 'package:xtremobile/core/theme/app_colors.dart';

/// Group (category) tile. Square tiles stack the icon over the title; wide
/// tiles (movies / series) put them side by side so two title lines fit.
class MobileCategoryCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData icon;

  /// Accent of the tab (live red, movies blue, series purple).
  final Color iconColor;
  final bool isFavorite;

  const MobileCategoryCard({
    super.key,
    required this.title,
    required this.onTap,
    this.onLongPress,
    this.isFavorite = false,
    this.icon = Icons.folder_rounded,
    this.iconColor = AppColors.primary,
  });

  static const double _radius = 16;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      onPressed: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(_radius),
      child: Stack(
        children: [
          // Base glossy background
          Positioned.fill(
            child: Container(
              decoration: AppDecorations.glossyCard(context, radius: _radius),
            ),
          ),
          // Glossy highlight overlay (shimmer)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 48,
            child: IgnorePointer(
              child: Container(
                decoration:
                    AppDecorations.glossShimmer(context, radius: _radius),
              ),
            ),
          ),
          // Content
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > constraints.maxHeight * 1.4;
                return wide ? _wideContent(context) : _squareContent(context);
              },
            ),
          ),
          if (isFavorite) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(
                      color: AppColors.ratingGold.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.star_rounded,
                color: AppColors.ratingGold,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconChip({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: iconColor.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, color: iconColor, size: size * 0.55),
    );
  }

  Widget _title(BuildContext context, TextAlign align) {
    return Text(
      title,
      style: TextStyle(
        color: AppDecorations.textPrimary(context),
        fontWeight: FontWeight.w600,
        fontSize: 13,
        height: 1.2,
      ),
      textAlign: align,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _squareContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _iconChip(size: 44),
          const SizedBox(height: 10),
          Flexible(child: _title(context, TextAlign.center)),
        ],
      ),
    );
  }

  Widget _wideContent(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, isFavorite ? 28 : 12, 8),
      child: Row(
        children: [
          _iconChip(size: 36),
          const SizedBox(width: 10),
          Expanded(child: _title(context, TextAlign.start)),
        ],
      ),
    );
  }
}
