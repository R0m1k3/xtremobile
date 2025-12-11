import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/mobile/widgets/tv_focusable.dart';

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
        // Focusable Poster
        Expanded(
          child: TVFocusable(
            onPressed: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: imageUrl != null && imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surface,
                            child: Icon(placeholderIcon, color: Colors.white38),
                          ),
                          placeholder: (_, __) => Container(
                            color: AppColors.surface,
                            child: Icon(placeholderIcon, color: Colors.white24),
                          ),
                        )
                      : Container(
                          color: AppColors.surface,
                          child: Icon(placeholderIcon, color: Colors.white38),
                        ),
                ),
                
                // Overlays
                if (rating != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 10),
                          const SizedBox(width: 2),
                          Text(
                            rating!,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (isWatched)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
