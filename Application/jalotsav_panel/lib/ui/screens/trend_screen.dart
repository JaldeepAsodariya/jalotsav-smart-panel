import 'package:flutter/material.dart';

import '../../core/panel_controller.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/panel_card.dart';
import '../widgets/trend_chart.dart';

class TrendScreen extends StatelessWidget {
  const TrendScreen({required this.controller, super.key});

  final PanelController controller;

  @override
  Widget build(BuildContext context) {
    final cfg = controller.config;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: PanelCard(
        title: '${S.trendTitle} · 5 min',
        child: TrendChart(
          readings: controller.history,
          window: const Duration(minutes: 5),
          setpoint: cfg.setpoint,
          clearBelow: cfg.clearBelow,
          lineColor: context.panel.forState(
            controller.alarmState,
            sensorLost: controller.sensorLost,
          ),
        ),
      ),
    );
  }
}
