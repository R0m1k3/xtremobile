import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/utils/form_factor.dart';
import 'package:xtremobile/core/utils/image_cache_config.dart';
import 'package:xtremobile/mobile/widgets/adaptive_grid.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';

/// A movie or series poster. The artwork carries the colour; the caption is
/// quiet. On TV the focused poster gets a light 4 dp outline and is the only
/// one showing its title, so the wall of posters stays calm.
class MobilePosterCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final String? rating;
  final String? year;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isWatched;
  final IconData placeholderIcon;

  const MobilePosterCard({
    super.key,
    required this.title,
    required this.imageUrl,
    this.rating,
    this.year,
    required this.onTap,
    this.onLongPress,
    this.isWatched = false,
    this.placeholderIcon = Icons.movie_outlined,
  });

  String get _meta => [
        if (year != null && year!.isNotEmpty) year!,
        if (rating != null && rating!.isNotEmpty) '$rating / 10',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final tv = FormFactors.of(context) == FormFactor.tv;

    return TVFocusable(
      onPressed: onTap,
      onLongPress: onLongPress,
      scale: 1.06,
      borderWidth: 4,
      borderRadius: BorderRadius.circular(10),
      // The outline goes on the artwork only, the caption stays outside.
      paintsOwnFocus: true,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: AppTheme.durationFocus,
                  curve: AppTheme.curveFocus,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    // At rest, a light edge keeps dark posters off the page.
                    border: lit
                        ? Border.all(color: AppColors.focus, width: 4)
                        : Border.all(color: AppColors.cardEdge),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: lit ? AppColors.focusShadows : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null && imageUrl!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: imageUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 240,
                            memCacheHeight: 360,
                            maxWidthDiskCache: 400,
                            maxHeightDiskCache: 600,
                            cacheManager: AppCacheManager.instance,
                            fadeInDuration: AppTheme.durationFast,
                            errorWidget: (_, __, ___) => _placeholder(),
                            placeholder: (_, __) => _placeholder(),
                          )
                        else
                          _placeholder(),
                        if (isWatched) const _WatchedMark(),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: AdaptiveGrid.posterCaption,
                child: AnimatedOpacity(
                  opacity: !tv || lit ? 1 : 0,
                  duration: AppTheme.durationFocus,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: tv ? 15 : 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_meta.isNotEmpty)
                          Text(
                            _meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: tv ? 13 : 12,
                              color: AppColors.textMuted,
                              fontFeatures: AppTheme.tabular,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: AppColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(placeholderIcon, size: 22, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Watched: a small neutral check in the corner.
class _WatchedMark extends StatelessWidget {
  const _WatchedMark();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: AppColors.background,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 14, color: AppColors.textPrimary),
      ),
    );
  }
}
