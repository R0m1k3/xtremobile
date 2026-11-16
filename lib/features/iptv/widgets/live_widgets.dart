import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/theme/glass.dart';
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

/// "FR| BEIN SPORTS MAX 10 FHD HEVC (EVENTS)" -> "BEIN SPORTS MAX 10": the
/// words worth reading on a logo tile.
String shortChannelName(String name) {
  var n = name.replaceFirst(RegExp(r'^\s*[A-Z]{2,3}\s*[|:\-]\s*'), '');
  n = n.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
  const tags = {
    'FHD',
    'HD',
    'UHD',
    'SD',
    '4K',
    '8K',
    'HEVC',
    'H265',
    'H.265',
    'H264',
    'HDR',
    'FULLHD',
    '50FPS',
    '60FPS',
    'MULTI-AUDIO',
    'MULTI',
    'VIP',
    'RAW',
  };
  final words = n
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !tags.contains(w.toUpperCase()))
      .toList();
  if (words.isEmpty) return name.trim();
  return words.take(4).join(' ');
}

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
    this.inset = false,
  });

  final String url;
  final String name;
  final double width;
  final double height;

  /// Sunk into a TV card rather than raised on the page.
  final bool inset;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.startsWith('http');
    // No logo: the short name (no country prefix, no quality tags). Two
    // lines on big tiles; on small ones the first word, shrunk to fit but
    // never below 11 dp (shrinking the whole name made scribbles).
    final inner = height * (1 - 2 * 0.12);
    final fallback = LayoutBuilder(
      builder: (context, box) {
        final short = shortChannelName(name);
        final twoLines = inner >= 34;
        final text = twoLines ? short : short.split(' ').first;
        var size = (inner / (twoLines ? 2 : 1) / 1.15).clamp(11.0, 14.0);
        if (!twoLines) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: AppTheme.body(fontSize: size, fontWeight: FontWeight.w600),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          if (painter.width > box.maxWidth) {
            size = (size * box.maxWidth / painter.width).clamp(11.0, size);
          }
          painter.dispose();
        }
        return Center(
          child: Text(
            text,
            maxLines: twoLines ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.body(
              fontSize: size,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        );
      },
    );
    return Container(
      width: width,
      height: height,
      decoration: AppDecorations.logoTile(radius: radius, inset: inset),
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
    this.subdued = false,
  });

  final double progress;
  final double height;

  /// In a list: one bar per row, so each one quieter.
  final bool subdued;

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
          color: lit
              ? AppColors.liveOnLight
              : subdued
                  ? AppColors.live.withValues(alpha: .7)
                  : AppColors.live,
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
            // Title at the top, with or without a subtitle under it.
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: AppDecorations.tvCard(lit: lit, radius: 12),
            child: Column(
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
                // "BE | Belgique": the country would repeat the name.
                if (label.country != null &&
                    label.country!.toLowerCase() !=
                        label.name.toLowerCase()) ...[
                  const SizedBox(height: 2),
                  Text(
                    label.country!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      fontSize: 14,
                      color: lit
                          ? AppColors.onFocusMuted
                          : AppColors.textSecondary,
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
                      color: AppColors.accent,
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

/// Favourite group card (TV grid, phone carousel): name, star and channel
/// count — no channel logos, judged too busy by Michael. The group's channels are
/// loaded through the cached category provider — a handful of favourites, so
/// cheap, and it pre-warms the group for when it is opened.
class FavoriteGroupCard extends ConsumerWidget {
  const FavoriteGroupCard({
    super.key,
    required this.playlist,
    required this.category,
    required this.onPressed,
    required this.onLongPress,
    this.width = 236,
    this.height = 88,
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
            return AnimatedContainer(
              duration: AppTheme.durationFocus,
              curve: AppTheme.curveFocus,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: AppDecorations.tvCard(lit: lit),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                        color: lit ? AppColors.accentOnLight : AppColors.accent,
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
                      color: lit
                          ? AppColors.onFocusMuted
                          : AppColors.textSecondary,
                      fontFeatures: AppTheme.tabular,
                    ),
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
            // Same lit glass as the cards; nothing at rest; no halo (rows
            // are 4 dp apart).
            decoration: GlassDecoration(
              lit: lit ? 1 : 0,
              radius: 10,
              bare: true,
              halo: false,
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
                                color: lit
                                    ? AppColors.accentOnLight
                                    : AppColors.accent,
                              ),
                            ),
                          if (now?.timeRange != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                now!.timeRange!,
                                style: AppTheme.body(
                                  fontSize: 15,
                                  color: secondary,
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
                        LiveLine(
                          progress: now.progress,
                          lit: lit,
                          height: lit ? 3 : 2,
                          subdued: !lit,
                        ),
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
                            color: AppColors.accent,
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
    final hasPreview = preview != null;

    // Full channel name, however long: the number leads, dimmed.
    final name = Text.rich(
      TextSpan(
        children: [
          if (c.num.isNotEmpty)
            TextSpan(
              text: '${c.num}  ',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontFeatures: AppTheme.tabular,
              ),
            ),
          TextSpan(text: c.name),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.body(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: AppColors.textPrimary,
      ),
    );

    final info = Padding(
      padding: EdgeInsets.fromLTRB(20, hasPreview ? 14 : 24, 20, 16),
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
          name,
          const SizedBox(height: 8),
          // The programme gets the height left under the name: as many whole
          // lines of title, then of description, as fit.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => _NowProgramme(
                now: now,
                height: box.maxHeight,
                titleSize: hasPreview ? 18 : 22,
              ),
            ),
          ),
          if (!hasPreview) ...[
            const SizedBox(height: 8),
            const _FullScreenHint(),
          ],
        ],
      ),
    );

    return Container(
      // No clip on the whole panel: only the picture is rounded, with a
      // plain rounded-rect clip (cheap), not a path around everything.
      decoration: AppDecorations.tvCard(lit: false, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPreview)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    preview!,
                    const Positioned(
                      right: 10,
                      bottom: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xB3000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(6, 4, 8, 4),
                          child: _FullScreenHint(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: info),
        ],
      ),
    );
  }
}

/// Title, times, progress and description of the current programme, fitted
/// to [height] in whole lines (nothing cut half-way).
class _NowProgramme extends StatelessWidget {
  const _NowProgramme({
    required this.now,
    required this.height,
    required this.titleSize,
  });

  final model.ShortEPG? now;
  final double height;
  final double titleSize;

  static const _lineHeight = 1.25;
  static const _timesSize = 15.0;
  static const _descSize = 15.0, _descHeight = 1.45;

  @override
  Widget build(BuildContext context) {
    final now = this.now;
    final titleLine = titleSize * _lineHeight;
    final titleStyle = AppTheme.body(
      fontSize: titleSize,
      fontWeight: FontWeight.w500,
      height: _lineHeight,
      color: now == null ? AppColors.textSecondary : AppColors.textPrimary,
    );
    if (now == null) {
      if (height < titleLine) return const SizedBox.shrink();
      return Text(
        'Pas de guide pour cette chaîne',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
    }

    // What fits, by priority: the title (it says what is on), the progress
    // line, the times, a second title line, then the description.
    const barBlock = 8.0 + 4;
    const timesBlock = 4 + _timesSize * _lineHeight;
    if (height < titleLine) return const SizedBox.shrink();
    var titleLines = 1;
    var left = height - titleLine;
    final showBar = left >= barBlock;
    if (showBar) left -= barBlock;
    final showTimes = left >= timesBlock;
    if (showTimes) left -= timesBlock;
    if (left >= titleLine) {
      titleLines = 2;
      left -= titleLine;
    }
    final descLines = now.description.isEmpty
        ? 0
        : ((left - 14) / (_descSize * _descHeight)).floor().clamp(0, 5).toInt();

    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              now.title,
              maxLines: titleLines,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            if (showTimes) ...[
              const SizedBox(height: 4),
              Text(
                [now.timeRange, now.remaining()]
                    .whereType<String>()
                    .join(' · '),
                maxLines: 1,
                style: AppTheme.body(
                  fontSize: _timesSize,
                  height: _lineHeight,
                  color: AppColors.textSecondary,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
            ],
            if (showBar) ...[
              const SizedBox(height: 8),
              LiveLine(progress: now.progress, height: 4),
            ],
            if (descLines > 0) ...[
              const SizedBox(height: 14),
              Text(
                now.description,
                maxLines: descLines,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  fontSize: _descSize,
                  height: _descHeight,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FullScreenHint extends StatelessWidget {
  const _FullScreenHint();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyCap('OK'),
          SizedBox(width: 8),
          _Hint('Plein écran'),
        ],
      );
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
