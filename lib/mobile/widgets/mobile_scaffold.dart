import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/theme/glass.dart';
import 'package:xtremobile/core/utils/form_factor.dart';

/// Bumped when the TV menu's "Rechercher" destination is chosen: the visible
/// tab listens and opens its own search field. Search is a destination on
/// TV, not a permanent text field.
final tabSearchRequestProvider = StateProvider<int>((ref) => 0);

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Direct', Icons.live_tv_outlined, Icons.live_tv),
  _Destination('Films', Icons.movie_outlined, Icons.movie),
  _Destination('Séries', Icons.layers_outlined, Icons.layers),
  _Destination('Réglages', Icons.settings_outlined, Icons.settings),
];

/// App shell. One structure per form factor:
/// * TV — a menu bar on top (up from the first row, or Back);
/// * tablet — a Material navigation rail;
/// * phone — a navigation bar at the bottom.
class MobileScaffold extends ConsumerWidget {
  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  const MobileScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (FormFactors.of(context)) {
      case FormFactor.tv:
        return Scaffold(
          // The ambient image is opaque: no second full-screen fill.
          backgroundColor: Colors.transparent,
          body: AmbientBackground(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TvTopMenu(
                  currentIndex: currentIndex,
                  onIndexChanged: onIndexChanged,
                  onSearch: () {
                    if (currentIndex == 3) onIndexChanged(0);
                    ref.read(tabSearchRequestProvider.notifier).state++;
                  },
                ),
                Expanded(child: child),
              ],
            ),
          ),
        );
      case FormFactor.tablet:
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: currentIndex,
                onDestinationSelected: onIndexChanged,
                groupAlignment: -1,
                leading: const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 16),
                  child: _Logo(size: 40),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                ],
              ),
              Expanded(child: AmbientBackground(child: child)),
            ],
          ),
        );
      case FormFactor.phone:
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AmbientBackground(child: child),
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: onIndexChanged,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
    }
  }
}

/// TV only. Back at the root of a tab first brings the focus up to the top
/// menu; once the menu has it, Back does what it did before.
abstract final class TvMenu {
  static _TvTopMenuState? _current;

  /// Moves the focus to the selected tab of the menu. False when there is no
  /// menu (phone, tablet) or the focus is already in it.
  static bool focusIfAway() => _current?._focusIfAway() ?? false;
}

/// TV menu bar: the tabs on the left, search and settings on the right.
/// Entering it from the content always lands on the current tab.
class _TvTopMenu extends StatefulWidget {
  const _TvTopMenu({
    required this.currentIndex,
    required this.onIndexChanged,
    required this.onSearch,
  });

  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onSearch;

  @override
  State<_TvTopMenu> createState() => _TvTopMenuState();
}

class _TvTopMenuState extends State<_TvTopMenu> {
  final _nodes = List.generate(
    _destinations.length,
    (i) => FocusNode(debugLabel: 'menu-${_destinations[i].label}'),
  );
  final _group = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
    debugLabel: 'tv-menu',
  );

  @override
  void initState() {
    super.initState();
    TvMenu._current = this;
  }

  @override
  void dispose() {
    if (TvMenu._current == this) TvMenu._current = null;
    for (final n in _nodes) {
      n.dispose();
    }
    _group.dispose();
    super.dispose();
  }

  bool _focusIfAway() {
    if (_group.hasFocus) return false;
    _nodes[widget.currentIndex].requestFocus();
    return true;
  }

  bool _inside = false;

  void _onFocusChange(bool hasFocus) {
    // Up from the content lands on the nearest item: go to the current tab.
    if (hasFocus && !_inside) {
      final target = _nodes[widget.currentIndex];
      if (!target.hasPrimaryFocus) target.requestFocus();
    }
    _inside = hasFocus;
  }

  @override
  Widget build(BuildContext context) {
    Widget item(int i, {bool iconOnly = false}) => _MenuItem(
          focusNode: _nodes[i],
          icon: _destinations[i].icon,
          selectedIcon: _destinations[i].selectedIcon,
          label: iconOnly ? null : _destinations[i].label,
          selected: widget.currentIndex == i,
          onPressed: () => widget.onIndexChanged(i),
        );

    return Focus(
      focusNode: _group,
      onFocusChange: _onFocusChange,
      child: Padding(
        // Clear of the TV overscan: 48 dp on the sides, 16 on top.
        padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const _Logo(size: 34),
              const SizedBox(width: 10),
              Text(
                'XtremFlow',
                style: AppTheme.body(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 28),
              // The tabs sit in a glass capsule, tvOS style.
              _GlassCapsule(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    item(i),
                  ],
                ],
              ),
              const Spacer(),
              _GlassCapsule(
                children: [
                  _MenuItem(
                    icon: Icons.search,
                    tooltip: 'Rechercher',
                    selected: false,
                    onPressed: widget.onSearch,
                  ),
                  const SizedBox(width: 4),
                  item(3, iconOnly: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.selectedIcon,
    this.label,
    this.tooltip,
    this.focusNode,
  });

  final IconData icon;
  final IconData? selectedIcon;

  /// Null: a round icon button.
  final String? label;
  final String? tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (_focused) {
      background = AppColors.focus;
      foreground = AppColors.onFocus;
    } else if (widget.selected) {
      background = AppColors.accentFill;
      foreground = AppColors.accent;
    } else {
      background = Colors.transparent;
      foreground = AppColors.textMuted;
    }
    final label = widget.label;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: label ?? widget.tooltip,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            height: 40,
            width: label == null ? 40 : null,
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 16),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.selected
                      ? (widget.selectedIcon ?? widget.icon)
                      : widget.icon,
                  size: 22,
                  color: foreground,
                ),
                if (label != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: AppTheme.body(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The blue XtremFlow play button.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/logo_xtremflow.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Icon(
          Icons.play_circle_filled,
          size: size,
          color: AppColors.accent,
        ),
      );
}

/// A row of menu items on a strip of glass.
class _GlassCapsule extends StatelessWidget {
  const _GlassCapsule({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const GlassDecoration(radius: 24),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}
