import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/utils/group_label.dart';
import 'package:xtremobile/core/utils/image_cache_config.dart';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';

// ─── Guide helpers ─────────────────────────────────────────────────────────────

extension ShortEpgTimes on model.ShortEPG {
  DateTime? get startTime => DateTime.tryParse(start);
  DateTime? get endTime => DateTime.tryParse(end);

  /// `21:10 – 23:15`, or `null` without valid times.
  String? get timeRange {
    final s = startTime, e = endTime;
    if (s == null || e == null) return null;
    return '${_hm(s)} – ${_hm(e)}';
  }

  /// `encore 1 h 03` / `encore 12 min`, or `null` when over or unknown.
  String? remaining([DateTime? now]) {
    final e = endTime;
    if (e == null) return null;
    final left = e.difference(now ?? DateTime.now());
    if (left.inMinutes < 1) return null;
    final h = left.inHours, m = left.inMinutes % 60;
    if (h == 0) return 'encore $m min';
    return 'encore $h h ${m.toString().padLeft(2, '0')}';
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ─── Small pieces ──────────────────────────────────────────────────────────────

/// A channel logo on its dark tile. The tile stays dark even when the row
/// is lit, so the logo keeps its own colours.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.url,
    required this.name,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final String url;
  final String name;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.startsWith('http');
    // No logo: the channel name, shrunk to fit the tile rather than cut.
    final fallback = Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          maxLines: 1,
          style: AppTheme.body(
            fontSize: height * 0.3,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
    return Container(
      width: width,
      height: height,
      decoration: AppDecorations.logoTile(radius: radius),
      padding: EdgeInsets.all(height * 0.12),
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              memCacheHeight: (height * 3).round(),
              cacheManager: AppCacheManager.instance,
              fadeInDuration: AppTheme.durationFast,
              errorWidget: (_, __, ___) => fallback,
              placeholder: (_, __) => const SizedBox.shrink(),
            )
          : fallback,
    );
  }
}

/// The signature: a red line showing how far the programme on now has run.
class LiveLine extends StatelessWidget {
  const LiveLine({
    super.key,
    required this.progress,
    this.height = 3,
    this.lit = false,
  });

  final double progress;
  final double height;

  /// On a lit (focused) surface the track lightens.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          color: AppColors.live,
          backgroundColor: lit ? AppColors.focusTrack : AppColors.track,
          minHeight: height,
        ),
      ),
    );
  }
}

/// `Tous les groupes  125`: label in primary, count quieter.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.count, this.fontSize = 18});

  final String title;
  final int? count;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: title),
          if (count != null)
            TextSpan(
              text: '  $count',
              style: AppTheme.body(
                fontSize: fontSize - 2,
                color: AppColors.textMuted,
                fontFeatures: AppTheme.tabular,
              ),
            ),
        ],
      ),
      style: AppTheme.body(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// A remote key drawn as a small keycap: `OK`.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.textMuted),
      ),
      child: Text(
        label,
        style: AppTheme.body(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ─── Groups ────────────────────────────────────────────────────────────────────

/// TV group card of the « Tous les groupes » grid: 72 dp, lit when focused.
class TvGroupCard extends StatelessWidget {
  const TvGroupCard({
    super.key,
    required this.label,
    required this.onPressed,
    required this.onLongPress,
    this.autofocus = false,
  });

  final GroupLabel label;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(12),
      onPressed: onPressed,
      onLongPress: onLongPress,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: lit ? AppColors.focus : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    fontSize: 17,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: lit ? AppColors.onFocus : AppColors.textPrimary,
                  ),
                ),
                if (label.country != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    label.country!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      fontSize: 14,
                      color: lit ? AppColors.onFocusMuted : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Touch list row for a group (phone, tablet).
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.label,
    required this.onTap,
    required this.onLongPress,
    this.isFavorite = false,
    this.selected = false,
    this.height = 64,
    this.showChevron = true,
  });

  final GroupLabel label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isFavorite;
  final bool selected;
  final double height;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.surfaceHigh : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (label.country != null)
                        Text(
                          label.country!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isFavorite)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (showChevron)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Favourite group card (TV shelf, phone carousel): name, star, channel
/// count and the logos of its first three channels. The group's channels are
/// loaded through the cached category provider — a handful of favourites, so
/// cheap, and it pre-warms the group for when it is opened.
class FavoriteGroupCard extends ConsumerWidget {
  const FavoriteGroupCard({
    super.key,
    required this.playlist,
    required this.category,
    required this.onPressed,
    required this.onLongPress,
    this.width = 245,
    this.height = 126,
    this.nameLines = 1,
    this.autofocus = false,
  });

  final PlaylistConfig playlist;
  final model.Category category;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final double width;
  final double height;

  /// 2 on TV, where names must never be cut short.
  final int nameLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = GroupLabel.parse(category.categoryName);
    final channels = ref
        .watch(
          mobileLiveChannelsByCategoryProvider(
            (playlist, category.categoryId),
          ),
        )
        .valueOrNull;

    return SizedBox(
      width: width,
      height: height,
      child: TVFocusable(
        paintsOwnFocus: true,
        autofocus: autofocus,
        scale: 1.05,
        borderRadius: BorderRadius.circular(14),
        onPressed: onPressed,
        onLongPress: onLongPress,
        child: Builder(
          builder: (context) {
            final lit = TVFocusable.isFocused(context);
            final logos = channels?.take(3).toList() ?? const [];
            final channelCount = channels?.length ?? 0;
            return AnimatedContainer(
              duration: AppTheme.durationFocus,
              curve: AppTheme.curveFocus,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: lit ? AppColors.focus : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.name,
                          maxLines: nameLines,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: 18,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color:
                                lit ? AppColors.onFocus : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color:
                            lit ? AppColors.onFocus : AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label.meta(channelCount: channels?.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      fontSize: 14,
                      color: lit ? AppColors.onFocusMuted : AppColors.textMuted,
                      fontFeatures: AppTheme.tabular,
                    ),
                  ),
                  const Spacer(),
                  if (logos.isNotEmpty)
                    // As many logos as the card's width allows (the TV grid
                    // narrows when the rail opens), the rest as "+N".
                    LayoutBuilder(
                      builder: (context, box) {
                        const slot = 52.0 + 8;
                        const moreWidth = 36.0;
                        final fit = ((box.maxWidth - moreWidth) / slot)
                            .floor()
                            .clamp(1, logos.length);
                        final more = channelCount - fit;
                        return Row(
                          children: [
                            for (final c in logos.take(fit)) ...[
                              ChannelLogo(
                                url: c.streamIcon,
                                name: c.name,
                                width: 52,
                                height: 32,
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (more > 0)
                              Text(
                                '+$more',
                                maxLines: 1,
                                style: AppTheme.body(
                                  fontSize: 14,
                                  color: lit
                                      ? AppColors.onFocusMuted
                                      : AppColors.textMuted,
                                  fontFeatures: AppTheme.tabular,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Channels ──────────────────────────────────────────────────────────────────

/// One channel: number, logo, name, programme on now with its times and the
/// live line. Lit when focused on TV.
class ChannelRow extends ConsumerWidget {
  const ChannelRow({
    super.key,
    required this.playlist,
    required this.channel,
    required this.onPressed,
    required this.onLongPress,
    required this.isFavorite,
    this.onFocus,
    this.dense = false,
    this.autofocus = false,
  });

  final PlaylistConfig playlist;
  final model.Channel channel;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final VoidCallback? onFocus;
  final bool isFavorite;

  /// TV rows are 60 dp; touch rows are 76 dp.
  final bool dense;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now =
        ref.watch(channelNowProvider((playlist, channel.streamId))).valueOrNull;
    final height = dense ? 60.0 : 76.0;

    return TVFocusable(
      paintsOwnFocus: true,
      autofocus: autofocus,
      scale: 1.03,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      onLongPress: onLongPress,
      onFocus: onFocus,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          final primary = lit ? AppColors.onFocus : AppColors.textPrimary;
          final secondary =
              lit ? AppColors.onFocusMuted : AppColors.textSecondary;
          final muted = lit ? AppColors.onFocusMuted : AppColors.textMuted;
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            curve: AppTheme.curveFocus,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: lit ? AppColors.focus : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    channel.num,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: AppTheme.body(
                      fontSize: 14,
                      color: muted,
                      fontFeatures: AppTheme.tabular,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ChannelLogo(
                  url: channel.streamIcon,
                  name: channel.name,
                  width: dense ? 64 : 56,
                  height: dense ? 40 : 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(
                                fontSize: dense ? 17 : 16,
                                fontWeight: FontWeight.w500,
                                color: primary,
                              ),
                            ),
                          ),
                          if (isFavorite)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: secondary,
                              ),
                            ),
                          if (now?.timeRange != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                now!.timeRange!,
                                style: AppTheme.body(
                                  fontSize: 13,
                                  color: muted,
                                  fontFeatures: AppTheme.tabular,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (now != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          now.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(
                            fontSize: dense ? 15 : 14,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        LiveLine(progress: now.progress, lit: lit),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Tablet channel card: logo tile on top, then number, name, programme and
/// the live line.
class ChannelTile extends ConsumerWidget {
  const ChannelTile({
    super.key,
    required this.playlist,
    required this.channel,
    required this.onPressed,
    required this.onLongPress,
    required this.isFavorite,
  });

  final PlaylistConfig playlist;
  final model.Channel channel;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  final bool isFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now =
        ref.watch(channelNowProvider((playlist, channel.streamId))).valueOrNull;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => ChannelLogo(
                    url: channel.streamIcon,
                    name: channel.name,
                    width: box.maxWidth,
                    height: box.maxHeight,
                    radius: 8,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          channel.num,
                          style: AppTheme.body(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            fontFeatures: AppTheme.tabular,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isFavorite)
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      now?.title ?? ' ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: now == null
                              ? const SizedBox(height: 3)
                              : LiveLine(progress: now.progress),
                        ),
                        if (now?.timeRange != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            now!.timeRange!,
                            style: AppTheme.body(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              fontFeatures: AppTheme.tabular,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TV panel on the right of the channel list: the programme of the focused
/// channel — the one rich moment of the screen.
class NowPanel extends ConsumerWidget {
  const NowPanel({
    super.key,
    required this.playlist,
    required this.channel,
    this.preview,
  });

  final PlaylistConfig playlist;
  final model.Channel? channel;

  /// Live picture shown on top (TV); without it, the big logo is shown.
  final Widget? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = channel;
    if (c == null) return const SizedBox.shrink();
    final now =
        ref.watch(channelNowProvider((playlist, c.streamId))).valueOrNull;
    final group = GroupLabel.parse(c.categoryName);
    final hasPreview = preview != null;

    final info = Padding(
      padding: EdgeInsets.fromLTRB(20, hasPreview ? 16 : 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasPreview) ...[
            ChannelLogo(
              url: c.streamIcon,
              name: c.name,
              width: 128,
              height: 80,
              radius: 10,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            [
              if (c.num.isNotEmpty) c.num,
              c.name,
              if (group.country != null) group.country!,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              fontSize: 14,
              color: AppColors.textMuted,
              fontFeatures: AppTheme.tabular,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            now?.title ?? 'Pas de guide pour cette chaîne',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              fontSize: hasPreview ? 20 : 24,
              fontWeight: FontWeight.w500,
              height: 1.2,
              color:
                  now == null ? AppColors.textSecondary : AppColors.textPrimary,
            ),
          ),
          if (now != null) ...[
            const SizedBox(height: 8),
            Text(
              [now.timeRange, now.remaining()].whereType<String>().join(' · '),
              style: AppTheme.body(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontFeatures: AppTheme.tabular,
              ),
            ),
            const SizedBox(height: 10),
            LiveLine(progress: now.progress, height: 4),
            const SizedBox(height: 14),
          ],
          // The description gets whatever height is left, in whole lines only.
          Expanded(
            child: now == null || now.description.isEmpty
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, box) {
                      const size = 15.0, height = 1.45;
                      final lines = (box.maxHeight / (size * height)).floor();
                      if (lines < 1) return const SizedBox.shrink();
                      return Text(
                        now.description,
                        maxLines: lines.clamp(1, 5),
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          fontSize: size,
                          height: height,
                          color: AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              KeyCap('OK'),
              SizedBox(width: 8),
              _Hint('Plein écran'),
            ],
          ),
        ],
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPreview) AspectRatio(aspectRatio: 16 / 9, child: preview),
          Expanded(child: info),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTheme.body(fontSize: 14, color: AppColors.textMuted),
      );
}

/// `Maintenir [OK] pour ajouter aux favoris` — remote hint, TV only.
class RemoteHint extends StatelessWidget {
  const RemoteHint({super.key, required this.before, required this.after});
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Hint(before),
        const SizedBox(width: 8),
        const KeyCap('OK'),
        const SizedBox(width: 8),
        _Hint(after),
      ],
    );
  }
}
