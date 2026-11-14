import 'package:flutter/material.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';

/// Title of a tab header, with an optional item count in a small pill.
class TabHeaderTitle extends StatelessWidget {
  final String title;
  final int? count;

  const TabHeaderTitle({super.key, required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              color: AppDecorations.textPrimary(context),
              fontWeight: FontWeight.w700,
              fontSize: 22,
              letterSpacing: -0.3,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.onSurface12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
