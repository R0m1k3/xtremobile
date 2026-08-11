import 'package:flutter/material.dart';
import 'package:xtremobile/core/theme/app_colors.dart';

class ThemedLoading extends StatelessWidget {
  const ThemedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.5,
          colors: [
            AppColors.surfaceContainerHigh,
            Color(0xFF000000),
          ],
          stops: [0.0, 1.0],
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: AppColors.onSurface,
          strokeWidth: 3,
        ),
      ),
    );
  }
}
