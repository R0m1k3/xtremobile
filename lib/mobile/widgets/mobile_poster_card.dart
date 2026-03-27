import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';
import 'package:xtremobile/core/utils/image_cache_config.dart';

class MobilePosterCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final String? rating;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isWatched;
  final IconData placeholderIcon;

  const MobilePosterCard({
    super.key,
    required this.title,
    required this.imageUrl,
    this.rating,
    required this.onTap,
    this.onLongPress,
    this.isWatched = false,
    this.placeholderIcon = Icons.movie,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // FIXED Aspect Ratio for the image part to avoid stretching
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Container(
            decoration: AppDecorations.glossyCard(context, radius: 12),
            child: TVFocusable(
              onPressed: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image / placeholder (clipped)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl != null && imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            memCacheWidth: 200, // Increased for better quality
                            memCacheHeight: 300,
                            maxWidthDiskCache: 400,
                            maxHeightDiskCache: 600,
                            cacheManager: AppCacheManager.instance,
                            errorWidget: (_, __, ___) => _buildPlaceholder(context),
                            placeholder: (_, __) => _buildPlaceholder(context),
                          )
                        : _buildPlaceholder(context),
                  ),

                  // Rating badge
                  if (rating != null && rating!.isNotEmpty)
                    _buildRatingBadge(),

                  // Watched badge
                  if (isWatched)
                    _buildWatchedBadge(),

                  // Glossy highlight overlay (top shimmer)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 60,
                    child: IgnorePointer(
                      child: Container(
                        decoration: AppDecorations.glossShimmer(context, radius: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),

        // Title with fixed height to avoid pushing the image
        SizedBox(
          height: 16,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppDecorations.textPrimary(context),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      decoration: AppDecorations.channelCardBase(context),
      child: Icon(
        placeholderIcon,
        color: AppDecorations.iconMuted(context),
      ),
    );
  }

  Widget _buildRatingBadge() {
    return Positioned(
      top: 6,
      left: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 10),
            const SizedBox(width: 2),
            Text(
              rating!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchedBadge() {
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Color(0xFF30D158),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check,
          size: 10,
          color: Colors.white,
        ),
      ),
    );
  }
}
