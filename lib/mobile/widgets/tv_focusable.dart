import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final double borderWidth;
  final Color focusColor;
  final BorderRadius? borderRadius;
  final Duration longPressDuration;

  const TVFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onFocus,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.08, // More visible scale
    this.borderWidth = 3.0,
    this.focusColor = Colors.white,
    this.borderRadius,
    this.longPressDuration = const Duration(seconds: 3),
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  late FocusNode _node;
  bool _isFocused = false;
  Timer? _longPressTimer;
  bool _isKeyDown = false;
  bool _longPressTriggered = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
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
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  void _handlePress() {
    widget.onPressed?.call();
  }

  void _handleLongPress() {
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        final key = event.logicalKey;
        final isSelectKey = key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.numpadEnter;

        if (event is KeyDownEvent && isSelectKey) {
          if (!_isKeyDown) {
            _isKeyDown = true;
            _longPressTriggered = false;

            // Start long press timer only if onLongPress is defined
            if (widget.onLongPress != null) {
              _longPressTimer?.cancel();
              _longPressTimer = Timer(widget.longPressDuration, () {
                if (_isKeyDown && mounted) {
                  _longPressTriggered = true;
                  _handleLongPress();
                }
              });
            }
          }
          return KeyEventResult.handled;
        }

        if (event is KeyUpEvent && isSelectKey) {
          _longPressTimer?.cancel();

          // If long press wasn't triggered, it's a normal press
          if (_isKeyDown && !_longPressTriggered) {
            _handlePress();
          }

          _isKeyDown = false;
          _longPressTriggered = false;
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _handlePress,
        onLongPress: widget.onLongPress,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic, // Apple-like snappy curve
          tween: Tween<double>(
            begin: 1.0,
            end: _isFocused ? widget.scale : 1.0,
          ),
          builder: (context, double scale, child) {
            return Transform.scale(
              scale: scale,
              child: Container(
                decoration: _isFocused
                    ? BoxDecoration(
                        borderRadius:
                            widget.borderRadius ?? BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(0.5), // Shadow for depth
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: widget.focusColor
                                .withOpacity(0.3), // Glow effect
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      )
                    : null,
                foregroundDecoration: _isFocused
                    ? BoxDecoration(
                        borderRadius:
                            widget.borderRadius ?? BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.focusColor,
                          width: widget.borderWidth,
                        ),
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
