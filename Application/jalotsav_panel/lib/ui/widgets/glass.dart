import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Soft coloured backdrop the glass sits on: a gradient plus three glows.
/// Radial gradients are already soft, so this needs no blur of its own.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.background,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.backdrop,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Glow(color: p.blobs[0], center: const Alignment(-0.85, -0.9)),
          _Glow(color: p.blobs[1], center: const Alignment(0.95, -0.2)),
          _Glow(color: p.blobs[2], center: const Alignment(-0.1, 1.1)),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.center});

  final Color color;
  final Alignment center;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: 0.9,
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// A frosted pane: blurs what is behind it, then adds a translucent fill, a
/// hairline border and a light top edge. [tint] colours the fill and border
/// (used for alarm states).
///
/// Uses [BackdropFilter.grouped], so all panes under one [BackdropGroup] share
/// a single backdrop read instead of one per pane.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.radius = 20,
    this.tint,
    this.borderWidth = 1,
    super.key,
  });

  final Widget child;
  final double radius;
  final Color? tint;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    final shape = BorderRadius.circular(radius);
    final t = tint;
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              p.glassHighlight.withValues(alpha: 0.12),
              p.glassFill,
            ),
            t == null
                ? p.glassFill
                : Color.alphaBlend(t.withValues(alpha: 0.10), p.glassFill),
          ],
        ),
        border: Border.all(
          color: t ?? p.glassBorder,
          width: t == null ? borderWidth : 2,
        ),
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: pane,
      ),
    );
  }
}
