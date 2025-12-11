import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';

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
          // Top Navigation Bar (Apple TV Style)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
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
          ),
          
          // Main Content
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon) {
    final isSelected = currentIndex == index;
    
    return _AppleTVNavItem(
      isSelected: isSelected,
      icon: icon,
      label: label,
      onPressed: () => onIndexChanged(index),
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
    // Selected = white bg + black text, Focused = gray border + white text, Normal = white70 text
    final Color textColor = widget.isSelected ? Colors.black : (_isFocused ? Colors.white : Colors.white70);
    final Color iconColor = widget.isSelected ? Colors.black : (_isFocused ? Colors.white : Colors.white70);
    
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
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            // White pill background when selected, transparent otherwise
            color: widget.isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
            // White border when focused
            border: _isFocused
                ? Border.all(color: Colors.white70, width: 2)
                : null,
            // Gray shadow when focused (for both selected and not selected)
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
