import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Glass without blur.
///
/// A real frosted glass (`BackdropFilter`) re-blurs what is behind it on
/// every frame and is the first thing to drop frames on a Fire TV. Here the
/// page behind the cards is a few soft blue glows ([AmbientBackground]) that
/// look the same blurred or not, so a translucent fill is enough to read as
/// frosted glass. The rest is light: a sheen on the top half, a faint
/// diagonal glint, and a rim lit from the top left that cools to blue at the
/// bottom right. All of it is a handful of gradients, painted once.
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

  static Color _a(Color c, double opacity) =>
      c.withValues(alpha: (c.a * opacity).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final r = d.radius.clamp(0.0, size.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));
    final l = d.lit.clamp(0.0, 1.0);
    final rest = 1 - l;

    // 1. Body: translucent white at rest, frosted white when lit.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(AppColors.glassTop, AppColors.focusTop, l)!,
            Color.lerp(AppColors.glassBottom, AppColors.focus, l)!,
          ],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    // 2. A breath of the logo's blue pooling at the bottom right.
    if (rest > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0x000A84FF),
              _a(AppColors.glassTint, rest),
            ],
          ).createShader(rect),
      );
    }

    // 3. Sheen: light falling on the top half.
    final top =
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * .5);
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _a(const Color(0x1FFFFFFF), rest + l * 2.5),
            const Color(0x00FFFFFF),
          ],
        ).createShader(top),
    );

    // 4. Glint: a soft diagonal band across the glass.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .30, .38, .46, 1],
          colors: [
            const Color(0x00FFFFFF),
            const Color(0x00FFFFFF),
            _a(const Color(0x0FFFFFFF), rest),
            const Color(0x00FFFFFF),
            const Color(0x00FFFFFF),
          ],
        ).createShader(rect),
    );
    canvas.restore();

    // 5. Rim: lit from the top left, cooling to blue at the bottom right.
    const w = 1.2;
    canvas.drawRRect(
      rrect.deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .45, 1],
          colors: [
            Color.lerp(const Color(0x66FFFFFF), const Color(0xFFFFFFFF), l)!,
            Color.lerp(const Color(0x14FFFFFF), const Color(0x99FFFFFF), l)!,
            Color.lerp(const Color(0x598AB9FF), const Color(0xCC8AB9FF), l)!,
          ],
        ).createShader(rect),
    );
  }
}

/// Page background: near-black with soft blue light, the colour of the logo,
/// coming from the top left and the bottom right. The glass cards show it
/// through. Painted once (own layer), never repainted by the content.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _AmbientPainter())),
          child,
        ],
      );
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.background);
    void glow(Offset c, double radius, Color color) {
      final r = Rect.fromCircle(center: c, radius: radius);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(r),
      );
    }

    final w = size.width, h = size.height;
    // Behind the logo, top left.
    glow(Offset(w * .10, -h * .10), w * .55, const Color(0x4D0A84FF));
    // Deep indigo, bottom right.
    glow(Offset(w * 1.0, h * 1.10), w * .60, const Color(0x403656D6));
    // A faint cyan in the middle, so the glass has something to catch.
    glow(Offset(w * .62, h * .42), w * .38, const Color(0x1458B8FF));
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) => false;
}
