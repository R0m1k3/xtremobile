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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Shadow lives on this outer Container so ClipRRect doesn't swallow it
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0x99000000)
                      : const Color(0x28000000),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
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
                            memCacheWidth: 120,
                            memCacheHeight: 180,
                            maxWidthDiskCache: 120,
                            maxHeightDiskCache: 180,
                            cacheManager: AppCacheManager.instance,
                            errorWidget: (_, __, ___) => Container(
                              decoration:
                                  AppDecorations.channelCardBase(context),
                              child: Icon(
                                placeholderIcon,
                                color: AppDecorations.iconMuted(context),
                              ),
                            ),
                            placeholder: (_, __) => Container(
                              decoration:
                                  AppDecorations.channelCardBase(context),
                              child: Icon(
                                placeholderIcon,
                                color: AppDecorations.iconMuted(context),
                              ),
                            ),
                          )
                        : Container(
                            decoration: AppDecorations.channelCardBase(context),
                            child: Icon(
                              placeholderIcon,
                              color: AppDecorations.iconMuted(context),
                            ),
                          ),
                  ),

                  // Rating badge
                  if (rating != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 10,
                            ),
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
                    ),

                  // Watched badge
                  if (isWatched)
                    Positioned(
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
                    ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppDecorations.textPrimary(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
