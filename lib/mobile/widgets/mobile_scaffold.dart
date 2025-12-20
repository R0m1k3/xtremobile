import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';

class MobileScaffold extends ConsumerStatefulWidget {
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
  ConsumerState<MobileScaffold> createState() => _MobileScaffoldState();
}

class _MobileScaffoldState extends ConsumerState<MobileScaffold> {
  late Stream<DateTime> _clockStream;

  @override
  void initState() {
    super.initState();
    _clockStream =
        Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Top Navigation Bar (Redesigned)
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: 24,
              horizontal: 24,
            ), // Increased vertical padding for floating effect
            decoration: const BoxDecoration(
              color: Colors.transparent, // Transparent background
            ),
            child: SafeArea(
              bottom: false,
              child: Container(
                height: 64, // Taller pill to accommodate larger logo
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A)
                      .withOpacity(0.9), // Slightly more opaque pill
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // --- LEFT: LOGO & BRAND ---
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 8,
                        right: 32,
                      ), // More spacing after logo
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52, // Larger Logo
                            height: 52,
                            // No decoration for free-floating logo
                            child: Image.asset(
                              'assets/images/logo_xtremflow.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.play_circle_filled,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'XtremFlow',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20, // Slightly larger text
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- CENTER: NAVIGATION ---
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildNavItem(0, 'Live TV', Icons.tv),
                          const SizedBox(width: 32), // Increased spacing
                          _buildNavItem(1, 'Movies', Icons.movie),
                          const SizedBox(width: 32),
                          _buildNavItem(2, 'Series', Icons.video_library),
                          const SizedBox(width: 32),
                          _buildNavItem(3, 'Settings', Icons.settings),
                        ],
                      ),
                    ),

                    // --- RIGHT: CLOCK ONLY ---
                    Padding(
                      padding: const EdgeInsets.only(left: 32, right: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(0.08), // Subtle background
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: StreamBuilder<DateTime>(
                          stream: _clockStream,
                          initialData: DateTime.now(),
                          builder: (context, snapshot) {
                            final time =
                                DateFormat('HH:mm').format(snapshot.data!);
                            return Text(
                              time,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Main Content
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon) {
    final isSelected = widget.currentIndex == index;
    return _AppleTVNavItem(
      isSelected: isSelected,
      icon: icon,
      label: label,
      onPressed: () => widget.onIndexChanged(index),
    );
  }
}

/// Apple TV style navigation item - matches desktop style
class _AppleTVNavItem extends StatefulWidget {
  final bool isSelected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _AppleTVNavItem({
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  State<_AppleTVNavItem> createState() => _AppleTVNavItemState();
}

class _AppleTVNavItemState extends State<_AppleTVNavItem> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    // Selected: Black text on White bg
    // Focused: White text on Translucent bg
    // Normal: White70 text on Transparent bg
    final Color textColor = widget.isSelected ? Colors.black : Colors.white;
    final Color iconColor = widget.isSelected ? Colors.black : Colors.white;
    final FontWeight fontWeight =
        widget.isSelected ? FontWeight.w700 : FontWeight.w500;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? Colors.white
                : (_isFocused
                    ? Colors.white.withOpacity(0.2) // Explicit focus highlight
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(20), // Matches pill shape
            border: _isFocused && !widget.isSelected
                ? Border.all(
                    color: Colors.white.withOpacity(0.3),
                  ) // Subtle border for focus
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: fontWeight,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
