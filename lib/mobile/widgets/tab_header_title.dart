import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/utils/form_factor.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';

/// Title of a tab, with an optional count in quiet tabular figures.
/// 28 dp on TV, 34 dp on a phone, 32 dp on a tablet.
class TabHeaderTitle extends StatelessWidget {
  final String title;
  final int? count;

  const TabHeaderTitle({super.key, required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    final size = switch (FormFactors.of(context)) {
      FormFactor.tv => 28.0,
      FormFactor.tablet => 32.0,
      FormFactor.phone => 34.0,
    };
    final weight = FormFactors.of(context) == FormFactor.phone
        ? FontWeight.w600
        : FontWeight.w500;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: title),
          if (count != null && count! > 0)
            TextSpan(
              text: '  $count',
              style: AppTheme.body(
                fontSize: size * 0.5,
                color: AppColors.textMuted,
                fontFeatures: AppTheme.tabular,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.display(fontSize: size, fontWeight: weight),
    );
  }
}

/// Header of the catalogue tabs (Films, Séries): back link, title and count,
/// then the search field. On TV the search field only shows once asked for
/// (rail « Rechercher ») or while a query is active.
class CatalogHeader extends StatelessWidget {
  const CatalogHeader({
    super.key,
    required this.title,
    required this.count,
    required this.backLabel,
    required this.onBack,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchHint,
    required this.isSearchEditing,
    required this.isSearching,
    required this.showSearchOnTv,
    required this.onSearchChanged,
    required this.onStartEditing,
    required this.onStopEditing,
    required this.onClear,
  });

  final String title;
  final int? count;

  /// `Films`: shown as `‹ Films` above the title inside a group.
  final String? backLabel;
  final VoidCallback? onBack;

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String searchHint;
  final bool isSearchEditing;
  final bool isSearching;
  final bool showSearchOnTv;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onStartEditing;
  final VoidCallback onStopEditing;
  final VoidCallback onClear;

  /// Same insets as the Live TV tab on TV: clear of the overscan.
  static const tvPadding = EdgeInsets.fromLTRB(24, 28, 48, 0);

  @override
  Widget build(BuildContext context) {
    final tv = FormFactors.of(context) == FormFactor.tv;
    final showSearch =
        !tv || showSearchOnTv || searchController.text.isNotEmpty;

    final field = Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 22, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: ExcludeFocus(
              excluding: tv && !isSearchEditing,
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                readOnly: tv && !isSearchEditing,
                cursorColor: AppColors.textPrimary,
                style: AppTheme.body(fontSize: 16),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: searchHint,
                  hintStyle:
                      AppTheme.body(fontSize: 16, color: AppColors.textMuted),
                  filled: false,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onSearchChanged,
                onSubmitted: (_) => onStopEditing(),
              ),
            ),
          ),
          if (isSearching)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (searchController.text.isNotEmpty || (tv && showSearchOnTv))
            IconButton(
              tooltip: 'Effacer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.textMuted,
              onPressed: onClear,
            ),
        ],
      ),
    );

    return Padding(
      padding: tv ? tvPadding : const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (backLabel != null)
            tv
                ? Text(
                    '‹ $backLabel',
                    style: AppTheme.body(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Retour',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                      color: AppColors.textPrimary,
                    ),
                  ),
          if (backLabel != null && tv) const SizedBox(height: 4),
          TabHeaderTitle(title: title, count: count),
          if (showSearch) ...[
            const SizedBox(height: 16),
            if (tv)
              TVFocusable(
                scale: 1.0,
                borderRadius: BorderRadius.circular(12),
                onPressed: () {
                  onStartEditing();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    searchFocusNode.requestFocus();
                    SystemChannels.textInput.invokeMethod('TextInput.show');
                  });
                },
                child: field,
              )
            else
              field,
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
