import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/panel_controller.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/panel_card.dart';

class AlarmsScreen extends StatelessWidget {
  const AlarmsScreen({required this.controller, super.key});

  final PanelController controller;

  @override
  Widget build(BuildContext context) {
    final events = controller.events;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: PanelCard(
        title: S.alarms,
        child: events.isEmpty
            ? Center(
                child: Text(
                  S.noEvents,
                  style: context.text.titleMedium?.copyWith(
                    color: context.panel.textMuted,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, _) =>
                    Divider(color: context.panel.track, height: 1),
                itemBuilder: (context, i) => _EventRow(event: events[i]),
              ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final AlarmEvent event;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    final (IconData icon, Color color, String text) = switch (event.type) {
      AlarmEventType.raised => (
        Icons.warning_rounded,
        p.alarm,
        S.eventRaised(event.celsius ?? 0),
      ),
      AlarmEventType.acknowledged => (
        Icons.check_circle,
        p.warning,
        S.eventAcknowledged,
      ),
      AlarmEventType.cleared => (
        Icons.verified,
        p.normal,
        S.eventCleared(event.celsius ?? 0),
      ),
      AlarmEventType.sensorLost => (
        Icons.sensors_off,
        p.warning,
        S.eventSensorLost,
      ),
      AlarmEventType.sensorRestored => (
        Icons.sensors,
        p.normal,
        S.eventSensorRestored,
      ),
      AlarmEventType.buzzerTest => (Icons.campaign, p.info, S.eventBuzzerTest),
    };
    String two(int v) => v.toString().padLeft(2, '0');
    final t = event.at;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.text.titleMedium)),
          Text(
            '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
            style: context.text.bodyMedium?.copyWith(
              color: p.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
