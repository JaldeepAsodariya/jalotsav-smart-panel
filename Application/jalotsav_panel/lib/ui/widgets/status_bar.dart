import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/panel_controller.dart';
import '../strings.dart';
import '../theme.dart';
import '../theme_controller.dart';
import 'glass.dart';

/// Top bar: title, node online indicators and a clock.
class StatusBar extends StatelessWidget {
  const StatusBar({required this.controller, required this.theme, super.key});

  final PanelController controller;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    final sensorOnline =
        (controller.node(NodeId.sensor)?.online ?? false) &&
        !controller.sensorLost;
    final buzzerOnline = controller.node(NodeId.buzzer)?.online ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: GlassSurface(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            return Container(
              height: 56,
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                children: [
                  Icon(Icons.sensors, color: p.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.appTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Natural size on a panel; scales down rather than overflowing
                  // on a narrow screen (e.g. the one portrait frame a phone draws
                  // before landscape kicks in). Leaves ~160 px for the title.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(0, width - 160),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _NodeChip(
                            key: const Key('node-sensor'),
                            label: S.sensorNode,
                            online: sensorOnline,
                          ),
                          const SizedBox(width: 8),
                          _NodeChip(
                            key: const Key('node-buzzer'),
                            label: S.buzzerNode,
                            online: buzzerOnline,
                          ),
                          const SizedBox(width: 16),
                          const _Clock(),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('theme-toggle'),
                    tooltip: S.switchTheme,
                    color: p.textMuted,
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                    onPressed: () => theme.toggle(Theme.of(context).brightness),
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

class _NodeChip extends StatelessWidget {
  const _NodeChip({required this.label, required this.online, super.key});

  final String label;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final p = context.panel;
    final color = online ? p.normal : p.alarm;
    return Semantics(
      label: '$label ${online ? S.online : S.offline}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: context.text.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    return Text(
      '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}',
      style: context.text.titleMedium?.copyWith(
        color: context.panel.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
