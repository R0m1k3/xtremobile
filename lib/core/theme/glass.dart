import 'dart:ui' as ui show Image;
import 'dart:ui' show PictureRecorder, lerpDouble;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Glass without blur.
///
/// A real frosted glass (`BackdropFilter`) re-blurs what is behind it on
/// every frame and is the first thing to drop frames on a Fire TV. Here the
/// page behind the cards is a few soft blue glows ([AmbientBackground]) that
/// look the same blurred or not, so a translucent fill is enough to read as
/// frosted glass. The rest is light: brighter at the top left, a faint
/// diagonal glint, a breath of blue at the bottom right, and a rim lit from
/// the top left that cools to blue.
///
/// Cost matters more than anything here: with a live preview playing, the
/// TV redraws the whole screen for every video frame. So a card is exactly
/// two draws (one gradient body, one gradient rim), no clip, no layer, and
/// no blurred shadow: the lit card's blue halo is a few plain strokes.
///
/// [lit] goes from 0 (resting glass) to 1 (the lit card: frosted white, dark
/// ink on it). `AnimatedContainer` blends between the two.
class GlassDecoration extends Decoration {
  const GlassDecoration({this.lit = 0, this.radius = 14});

  final double lit;
  final double radius;

  static GlassDecoration lerp(GlassDecoration a, GlassDecoration b, double t) =>
      GlassDecoration(
        lit: lerpDouble(a.lit, b.lit, t)!,
        radius: lerpDouble(a.radius, b.radius, t)!,
      );

  @override
  Decoration? lerpFrom(Decoration? a, double t) =>
      a is GlassDecoration ? lerp(a, this, t) : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is GlassDecoration ? lerp(this, b, t) : super.lerpTo(b, t);

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius))
          .contains(position);

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _GlassPainter(this);

  @override
  bool operator ==(Object other) =>
      other is GlassDecoration && other.lit == lit && other.radius == radius;

  @override
  int get hashCode => Object.hash(lit, radius);
}

class _GlassPainter extends BoxPainter {
  _GlassPainter(this.d);
  final GlassDecoration d;

  // Body, top left to bottom right: light, glint band, blue pool.
  static const _stops = [0.0, .32, .39, .46, 1.0];
  static const _rest = [
    Color(0x29FFFFFF),
    Color(0x14FFFFFF),
    Color(0x21FFFFFF),
    Color(0x12FFFFFF),
    Color(0x2E3D8FFF),
  ];
  static const _lit = [
    AppColors.focusTop,
    Color(0xFFF8F8F6),
    Color(0xFFFAFAF8),
    Color(0xFFF6F5F2),
    AppColors.focus,
  ];

  // Rim: lit top left, dim middle, blue bottom right.
  static const _rimStops = [0.0, .45, 1.0];
  static const _rimRest = [
    Color(0x66FFFFFF),
    Color(0x14FFFFFF),
    Color(0x598AB9FF)
  ];
  static const _rimLit = [
    Color(0xFFFFFFFF),
    Color(0x99FFFFFF),
    Color(0xCC8AB9FF)
  ];

  // Lit halo: plain strokes, fading outwards (a blur would cost a pass).
  static const _halo = [(2.0, .50), (5.0, .26), (8.0, .12), (11.0, .05)];

  static List<Color> _mix(List<Color> a, List<Color> b, double t) => [
        for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
      ];

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final r = d.radius.clamp(0.0, size.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));
    final l = d.lit.clamp(0.0, 1.0);

    if (l > 0) {
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      for (final (out, alpha) in _halo) {
        halo.color = AppColors.accentStrong.withValues(alpha: alpha * l);
        canvas.drawRRect(rrect.inflate(out - 1.5), halo);
      }
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: _stops,
          colors: l == 0 ? _rest : _mix(_rest, _lit, l),
        ).createShader(rect),
    );

    const w = 1.2;
    canvas.drawRRect(
      rrect.deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: _rimStops,
          colors: l == 0 ? _rimRest : _mix(_rimRest, _rimLit, l),
        ).createShader(rect),
    );
  }
}

/// Page background: near-black with soft blue light, the colour of the logo,
/// coming from the top left and the bottom right. The glass cards show it
/// through.
///
/// Rendered once into a small image (320×180) and stretched: smooth glows
/// lose nothing, and the screen then costs a single textured draw per frame
/// instead of several full-screen gradients.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  static ui.Image? _image;

  static ui.Image _bake() {
    const w = 320.0, h = 180.0;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = const Offset(0, 0) & const Size(w, h);
    canvas.drawRect(rect, Paint()..color = AppColors.background);
    void glow(Offset c, double radius, Color color) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }

    // Behind the logo, top left.
    glow(const Offset(w * .10, -h * .10), w * .55, const Color(0x4D0A84FF));
    // Deep indigo, bottom right.
    glow(const Offset(w * 1.0, h * 1.10), w * .60, const Color(0x403656D6));
    // A faint cyan in the middle, so the glass has something to catch.
    glow(const Offset(w * .62, h * .42), w * .38, const Color(0x1458B8FF));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w.toInt(), h.toInt());
    picture.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _AmbientPainter(_image ??= _bake())),
          ),
          child,
        ],
      );
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.image);
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) => oldDelegate.image != image;
}
