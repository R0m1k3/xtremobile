import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';

/// Remote-control focus. One focus state across the app: the focused item is
/// the only lit thing on screen — a slight scale-up and a neutral shadow.
///
/// * Default: a light outline is drawn around the child (screens that were
///   not redesigned rely on it).
/// * [paintsOwnFocus]: no outline; the child reads [TVFocusable.isFocused]
///   and turns itself into the lit surface (cards, rows).
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

  /// The child draws the focused look itself (see [TVFocusable.isFocused]).
  final bool paintsOwnFocus;

  /// Whether the nearest enclosing [TVFocusable] has focus.
  static bool isFocused(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TVFocusScope>()?.focused ??
      false;

  const TVFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onFocus,
    this.focusNode,
    this.autofocus = false,
    this.scale = 1.05,
    this.borderWidth = 3.0,
    this.focusColor = AppColors.focus,
    this.borderRadius,
    this.longPressDuration = const Duration(seconds: 3),
    this.paintsOwnFocus = false,
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
        duration: AppTheme.durationLg,
        curve: AppTheme.curveFocus,
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
          duration: AppTheme.durationFocus,
          curve: AppTheme.curveFocus,
          tween: Tween<double>(
            begin: 1.0,
            end: _isFocused ? widget.scale : 1.0,
          ),
          builder: (context, double scale, child) {
            final radius = widget.borderRadius ?? BorderRadius.circular(12);
            return Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: _isFocused
                    ? BoxDecoration(
                        borderRadius: radius,
                        boxShadow: AppColors.focusShadows,
                      )
                    : const BoxDecoration(),
                position: DecorationPosition.background,
                child: _isFocused && !widget.paintsOwnFocus
                    ? DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: widget.focusColor,
                            width: widget.borderWidth,
                          ),
                        ),
                        child: child,
                      )
                    : child,
              ),
            );
          },
          child: _TVFocusScope(
            focused: _isFocused,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _TVFocusScope extends InheritedWidget {
  const _TVFocusScope({required this.focused, required super.child});

  final bool focused;

  @override
  bool updateShouldNotify(_TVFocusScope oldWidget) =>
      focused != oldWidget.focused;
}
