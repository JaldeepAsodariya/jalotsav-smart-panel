import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 240° arc gauge drawn with a CustomPainter (no chart package needed).
class TemperatureGauge extends StatelessWidget {
  const TemperatureGauge({
    required this.celsius,
    required this.setpoint,
    required this.color,
    this.min = 0,
    this.max = 80,
    super.key,
  });

  final double? celsius;
  final double setpoint;
  final Color color;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _GaugePainter(
          value: celsius,
          setpoint: setpoint,
          min: min,
          max: max,
          color: color,
          track: p.track,
          marker: p.textPrimary,
        ),
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    celsius == null ? '--.-' : celsius!.toStringAsFixed(1),
                    style: context.text.displayLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '°C',
                    style: context.text.headlineSmall?.copyWith(
                      color: p.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.setpoint,
    required this.min,
    required this.max,
    required this.color,
    required this.track,
    required this.marker,
  });

  final double? value;
  final double setpoint;
  final double min;
  final double max;
  final Color color;
  final Color track;
  final Color marker;

  static const _start = 150 * pi / 180;
  static const _sweep = 240 * pi / 180;

  double _frac(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 4);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    canvas.drawArc(arcRect, _start, _sweep, false, base..color = track);
    if (value != null) {
      canvas.drawArc(
        arcRect,
        _start,
        _sweep * _frac(value!),
        false,
        base..color = color,
      );
    }

    // Setpoint tick.
    final a = _start + _sweep * _frac(setpoint);
    final c = arcRect.center;
    final r = arcRect.width / 2;
    final dir = Offset(cos(a), sin(a));
    canvas.drawLine(
      c + dir * (r - stroke * 0.9),
      c + dir * (r + stroke * 0.9),
      Paint()
        ..color = marker
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.setpoint != setpoint || old.color != color;
}
