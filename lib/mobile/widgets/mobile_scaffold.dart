import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/utils/form_factor.dart';

/// Bumped when the TV rail's "Rechercher" destination is chosen: the visible
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
/// * TV — a rail on the left, icons only, that unfolds while it has focus
///   (press left from the first column);
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
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              Positioned.fill(
                left: _TvRail.collapsedWidth,
                child: child,
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _TvRail(
                  currentIndex: currentIndex,
                  onIndexChanged: onIndexChanged,
                  onSearch: () {
                    if (currentIndex == 3) onIndexChanged(0);
                    ref.read(tabSearchRequestProvider.notifier).state++;
                  },
                ),
              ),
            ],
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
              Expanded(child: child),
            ],
          ),
        );
      case FormFactor.phone:
        return Scaffold(
          backgroundColor: AppColors.background,
          body: child,
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

/// TV rail: 104 dp of icons, unfolding to 240 dp with labels while one of its
/// items has focus. It overlays the content instead of pushing it, so the
/// grid does not reflow each time the remote goes left.
class _TvRail extends StatefulWidget {
  static const double collapsedWidth = 104;
  static const double expandedWidth = 240;

  const _TvRail({
    required this.currentIndex,
    required this.onIndexChanged,
    required this.onSearch,
  });

  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onSearch;

  @override
  State<_TvRail> createState() => _TvRailState();
}

class _TvRailState extends State<_TvRail> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) => setState(() => _expanded = hasFocus),
      child: AnimatedContainer(
        duration: AppTheme.durationNormal,
        curve: AppTheme.curveFocus,
        width: _expanded ? _TvRail.expandedWidth : _TvRail.collapsedWidth,
        color: AppColors.rail,
        padding: const EdgeInsets.fromLTRB(32, 28, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 28,
              child: AnimatedOpacity(
                opacity: _expanded ? 1 : 0,
                duration: AppTheme.durationFast,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'XtremFlow',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: AppTheme.body(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _RailItem(
              icon: Icons.search,
              label: 'Rechercher',
              selected: false,
              expanded: _expanded,
              onPressed: widget.onSearch,
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < 3; i++) ...[
              _RailItem(
                icon: _destinations[i].icon,
                selectedIcon: _destinations[i].selectedIcon,
                label: _destinations[i].label,
                selected: widget.currentIndex == i,
                expanded: _expanded,
                onPressed: () => widget.onIndexChanged(i),
              ),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            _RailItem(
              icon: _destinations[3].icon,
              selectedIcon: _destinations[3].selectedIcon,
              label: _destinations[3].label,
              selected: widget.currentIndex == 3,
              expanded: _expanded,
              onPressed: () => widget.onIndexChanged(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onPressed,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (_focused) {
      background = AppColors.focus;
      foreground = AppColors.onFocus;
    } else if (widget.selected) {
      background = AppColors.surfaceHigh;
      foreground = AppColors.textPrimary;
    } else {
      background = Colors.transparent;
      foreground = AppColors.textMuted;
    }

    return Focus(
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
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          // The label joins once the rail is wide enough, not as soon as it
          // starts to unfold.
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Icon(
                  widget.selected
                      ? (widget.selectedIcon ?? widget.icon)
                      : widget.icon,
                  size: 24,
                  color: foreground,
                ),
                if (widget.expanded && box.maxWidth >= 24 + 16 + 48) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: AppTheme.body(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
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
