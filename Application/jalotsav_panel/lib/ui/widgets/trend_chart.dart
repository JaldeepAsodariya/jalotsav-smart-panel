import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';

/// Line chart of readings over a time window, with setpoint and clear lines.
/// Custom-painted, so no chart package is needed.
class TrendChart extends StatelessWidget {
  const TrendChart({
    required this.readings,
    required this.window,
    required this.setpoint,
    required this.clearBelow,
    required this.lineColor,
    this.showAxis = true,
    super.key,
  });

  final List<TemperatureReading> readings;
  final Duration window;
  final double setpoint;
  final double clearBelow;
  final Color lineColor;
  final bool showAxis;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    return CustomPaint(
      size: Size.infinite,
      painter: _TrendPainter(
        readings: readings,
        window: window,
        setpoint: setpoint,
        clearBelow: clearBelow,
        line: lineColor,
        grid: p.track,
        setpointColor: p.alarm,
        clearColor: p.textMuted,
        label: showAxis
            ? context.text.labelSmall!.copyWith(color: p.textMuted)
            : null,
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.readings,
    required this.window,
    required this.setpoint,
    required this.clearBelow,
    required this.line,
    required this.grid,
    required this.setpointColor,
    required this.clearColor,
    required this.label,
  });

  final List<TemperatureReading> readings;
  final Duration window;
  final double setpoint;
  final double clearBelow;
  final Color line;
  final Color grid;
  final Color setpointColor;
  final Color clearColor;
  final TextStyle? label;

  @override
  void paint(Canvas canvas, Size size) {
    final left = label == null ? 0.0 : 36.0;
    final plot = Rect.fromLTRB(left, 8, size.width, size.height - 4);

    final end = readings.isEmpty ? DateTime.now() : readings.last.at;
    final start = end.subtract(window);
    final visible = readings.where((r) => !r.at.isBefore(start)).toList();

    var lo = clearBelow - 5;
    var hi = setpoint + 5;
    for (final r in visible) {
      if (r.celsius < lo) lo = r.celsius - 2;
      if (r.celsius > hi) hi = r.celsius + 2;
    }

    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    double x(DateTime t) =>
        plot.left +
        t.difference(start).inMilliseconds / window.inMilliseconds * plot.width;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final step = (hi - lo) > 30 ? 10.0 : 5.0;
    for (var v = (lo / step).ceil() * step; v <= hi; v += step) {
      canvas.drawLine(
        Offset(plot.left, y(v)),
        Offset(plot.right, y(v)),
        gridPaint,
      );
      if (label != null) {
        final tp = TextPainter(
          text: TextSpan(text: v.toStringAsFixed(0), style: label),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
      }
    }

    _dashed(canvas, plot, y(clearBelow), clearColor);
    canvas.drawLine(
      Offset(plot.left, y(setpoint)),
      Offset(plot.right, y(setpoint)),
      Paint()
        ..color = setpointColor
        ..strokeWidth = 2,
    );

    if (visible.length < 2) return;
    final path = Path()..moveTo(x(visible.first.at), y(visible.first.celsius));
    for (final r in visible.skip(1)) {
      path.lineTo(x(r.at), y(r.celsius));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _dashed(Canvas canvas, Rect plot, double dy, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var dx = plot.left; dx < plot.right; dx += 12) {
      canvas.drawLine(Offset(dx, dy), Offset(dx + 6, dy), paint);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.readings != readings ||
      old.setpoint != setpoint ||
      old.clearBelow != clearBelow ||
      old.line != line;
}
