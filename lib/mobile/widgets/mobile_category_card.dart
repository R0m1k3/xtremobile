import 'package:flutter/material.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';
import 'package:xtremobile/core/theme/app_colors.dart';

class MobileCategoryCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData icon;
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

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      onPressed: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // Base glossy background
          Container(
            decoration: AppDecorations.glossyCard(context, radius: 16),
          ),
          // Glossy highlight overlay (shimmer)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 60,
            child: IgnorePointer(
              child: Container(
                decoration: AppDecorations.glossShimmer(context, radius: 16),
              ),
            ),
          ),
          if (isFavorite)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.ratingGold.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          if (isFavorite)
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.star_rounded,
                color: AppColors.ratingGold,
                size: 18,
              ),
            ),
          // Content
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: iconColor,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: AppDecorations.textPrimary(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
