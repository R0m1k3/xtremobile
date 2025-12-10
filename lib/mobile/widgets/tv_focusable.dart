import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';

class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final double borderWidth;
  final Color focusColor;
  final BorderRadius? borderRadius;

  const TVFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onFocus,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.05,
    this.borderWidth = 3.0,
    this.focusColor = Colors.white,
    this.borderRadius,
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  late FocusNode _node;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _node.dispose();
    } else {
      _node.removeListener(_onFocusChanged);
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (_node.hasFocus != _isFocused) {
      setState(() => _isFocused = _node.hasFocus);
      if (_isFocused) {
        widget.onFocus?.call();
        _scrollToVisible();
      }
    }
  }

  void _scrollToVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5, // Center the item
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _handlePress() {
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter) {
            _handlePress();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _handlePress,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          tween: Tween<double>(
            begin: 1.0,
            end: _isFocused ? widget.scale : 1.0,
          ),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: Container(
                foregroundDecoration: _isFocused
                    ? BoxDecoration(
                        border: Border.all(
                          color: widget.focusColor,
                          width: widget.borderWidth,
                        ),
                        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
                      )
                    : null,
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
