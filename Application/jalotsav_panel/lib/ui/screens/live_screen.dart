import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/panel_controller.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/panel_card.dart';
import '../widgets/temperature_gauge.dart';
import '../widgets/trend_chart.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({required this.controller, super.key});

  final PanelController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    final state = controller.alarmState;
    final color = p.forState(state, sensorLost: controller.sensorLost);
    final cfg = controller.config;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: PanelCard(
              borderColor: state == AlarmState.alarm ? p.alarm : null,
              child: Center(
                child: TemperatureGauge(
                  celsius: controller.latest?.celsius,
                  setpoint: cfg.setpoint,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _StateTile(controller: controller)),
                const SizedBox(height: 12),
                Expanded(flex: 3, child: _SirenTile(controller: controller)),
                const SizedBox(height: 12),
                Expanded(
                  flex: 3,
                  child: PanelCard(
                    title: S.lastMinute,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: TrendChart(
                      readings: controller.history,
                      window: const Duration(seconds: 60),
                      setpoint: cfg.setpoint,
                      clearBelow: cfg.clearBelow,
                      lineColor: color,
                      showAxis: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StateTile extends StatelessWidget {
  const _StateTile({required this.controller});

  final PanelController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    final lost = controller.sensorLost;
    final state = controller.alarmState;
    final color = p.forState(state, sensorLost: lost);
    final label = lost
        ? S.stateSensorLost
        : switch (state) {
            AlarmState.normal => S.stateNormal,
            AlarmState.pending => S.statePending,
            AlarmState.alarm => S.stateAlarm,
            AlarmState.acknowledged => S.stateAcknowledged,
          };
    final cfg = controller.config;

    return PanelCard(
      borderColor: color,
      // Scales the whole block down (both ways) on a short screen.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.latest == null ? S.waiting : label,
              key: const Key('alarm-state'),
              style: context.text.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${S.setpoint} ${cfg.setpoint.toStringAsFixed(0)} °C  ·  '
              '${S.clearsBelow} ${cfg.clearBelow.toStringAsFixed(0)} °C',
              style: context.text.bodyMedium?.copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SirenTile extends StatelessWidget {
  const _SirenTile({required this.controller});

  final PanelController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    // Node 2 offline or not hearing Node 1: the phone is the siren.
    final phone = !controller.sirenNodeInCharge;
    final on = phone ? controller.phoneAlarmOn : controller.buzzerOn;
    final canAck = controller.alarmState == AlarmState.alarm;

    return PanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            on
                ? Icons.campaign
                : phone
                ? Icons.phone_android
                : Icons.volume_off,
            color: on ? p.alarm : p.textMuted,
            size: 36,
          ),
          const SizedBox(width: 12),
          // Scales the label + status down together on a short screen.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phone ? S.phoneAlarm : S.siren,
                    style: context.text.labelLarge?.copyWith(
                      color: phone ? p.warning : p.textMuted,
                    ),
                  ),
                  Text(
                    on ? S.sirenOn : S.sirenOff,
                    style: context.text.titleLarge?.copyWith(
                      color: on ? p.alarm : p.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Shrinks to fit on small (800×480) panels instead of overflowing.
          Flexible(
            child: FittedBox(child: canAck ? _ackButton(p) : _testButton()),
          ),
        ],
      ),
    );
  }

  Widget _ackButton(PanelColors p) => FilledButton.icon(
    key: const Key('ack-button'),
    style: FilledButton.styleFrom(
      backgroundColor: p.alarm,
      foregroundColor: p.textPrimary,
      minimumSize: const Size(0, 56),
    ),
    onPressed: controller.acknowledge,
    icon: const Icon(Icons.check),
    label: const Text(S.acknowledge),
  );

  Widget _testButton() => OutlinedButton(
    key: const Key('test-siren'),
    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
    onPressed: controller.testBuzzer,
    child: const Text(S.testSiren),
  );
}
