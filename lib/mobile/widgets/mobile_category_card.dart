import 'package:flutter/material.dart';

import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/utils/form_factor.dart';
import 'package:xtremobile/core/utils/group_label.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';

/// A group (category) of movies or series. On TV, the 72 dp card of the Live
/// TV grid, lit when focused; on touch screens, a row with a chevron.
/// `FR | Action` reads `Action`, with `France` quietly under it.
class MobileCategoryCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isFavorite;

  /// Ignored: tabs no longer get their own icon and colour. Kept so older
  /// call sites compile.
  final IconData icon;
  final Color iconColor;

  const MobileCategoryCard({
    super.key,
    required this.title,
    required this.onTap,
    this.onLongPress,
    this.isFavorite = false,
    this.icon = Icons.folder_outlined,
    this.iconColor = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final label = GroupLabel.parse(title);
    final tv = FormFactors.of(context) == FormFactor.tv;
    final radius = BorderRadius.circular(12);

    return TVFocusable(
      paintsOwnFocus: true,
      onPressed: onTap,
      onLongPress: onLongPress,
      borderRadius: radius,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: lit ? AppColors.focus : AppColors.surface,
              borderRadius: radius,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: tv ? 17 : 16,
                          fontWeight: FontWeight.w500,
                          color:
                              lit ? AppColors.onFocus : AppColors.textPrimary,
                        ),
                      ),
                      if (label.country != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          label.country!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: tv ? 14 : 13,
                            color: lit
                                ? AppColors.onFocusMuted
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isFavorite)
                  Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: lit ? AppColors.onFocus : AppColors.textSecondary,
                  ),
                if (!tv)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
