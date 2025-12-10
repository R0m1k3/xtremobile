import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import 'tv_focusable.dart';

class MobileScaffold extends ConsumerWidget {
  final Widget child;
  final int currentIndex;
  final Function(int) onIndexChanged;

  const MobileScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Top Navigation Bar (TV Friendly)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, 'Live TV', Icons.tv),
                  _buildNavItem(1, 'Films', Icons.movie),
                  _buildNavItem(2, 'Séries', Icons.video_library),
                  _buildNavItem(3, 'Paramètres', Icons.settings),
                ],
              ),
            ),
          ),
          
          // Main Content
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon) {
    final isSelected = currentIndex == index;
    return TVFocusable(
      onPressed: () => onIndexChanged(index),
      scale: 1.1,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.15) : null,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: AppColors.primary.withOpacity(0.5)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
