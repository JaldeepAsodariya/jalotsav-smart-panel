import 'package:flutter/material.dart';

import '../../core/panel_controller.dart';
import '../strings.dart';
import '../theme.dart';
import 'panel_card.dart';

/// One-point PT100 calibration against a reference thermometer. Node 1 works
/// out offset = real − raw and keeps it in flash.
///
/// The real temperature is set with ± buttons (no keyboard on a panel). It
/// follows the live reading until you touch a button.
class CalibrationCard extends StatefulWidget {
  const CalibrationCard({required this.controller, super.key});

  final PanelController controller;

  @override
  State<CalibrationCard> createState() => _CalibrationCardState();
}

class _CalibrationCardState extends State<CalibrationCard> {
  /// Null = follow the live reading.
  double? _target;

  PanelController get _c => widget.controller;

  void _nudge(double by) {
    final from = _target ?? _c.latest?.celsius ?? 25;
    setState(() => _target = ((from + by) * 10).round() / 10);
  }

  Future<void> _calibrate(double real) async {
    await _c.calibrate(real);
    if (mounted) setState(() => _target = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    final cal = _c.calibration;
    final ready = cal != null && cal.available;
    final reading = _c.latest?.celsius;
    final shown = _target ?? reading;
    final canCalibrate = ready && shown != null;
    final error = _c.lastError;

    return PanelCard(
      title: S.calibration,
      child: ListView(
        children: [
          Text(
            ready
                ? S.calibrationStatus(reading, cal.offset, cal.ohms)
                : S.calibrationUnavailable,
            style: context.text.bodyMedium?.copyWith(
              color: ready ? p.textMuted : p.warning,
            ),
          ),
          const SizedBox(height: 12),
          Text(S.realTemperature, style: context.text.titleMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              _Step(label: '−1', id: 'cal-minus-1', onTap: () => _nudge(-1)),
              _Step(
                label: '−0.1',
                id: 'cal-minus-0.1',
                onTap: () => _nudge(-0.1),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shown == null ? '-- °C' : '${shown.toStringAsFixed(1)} °C',
                    style: context.text.headlineSmall?.copyWith(
                      color: p.info,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              _Step(
                label: '+0.1',
                id: 'cal-plus-0.1',
                onTap: () => _nudge(0.1),
              ),
              _Step(label: '+1', id: 'cal-plus-1', onTap: () => _nudge(1)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('calibrate-button'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: canCalibrate ? () => _calibrate(shown) : null,
                  icon: const Icon(Icons.tune),
                  label: const Text(S.calibrate),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('reset-offset'),
                onPressed: ready ? _c.resetOffset : null,
                child: const Text(S.resetOffset),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: context.text.bodySmall?.copyWith(color: p.alarm),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            S.calibrationHint,
            style: context.text.bodySmall?.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.id, required this.onTap});

  final String label;
  final String id;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        key: Key(id),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
