import 'package:flutter/material.dart';

import '../../core/fake_device_gateway.dart';
import '../../core/panel_controller.dart';
import '../strings.dart';
import '../theme.dart';
import '../theme_controller.dart';
import '../widgets/calibration_card.dart';
import '../widgets/panel_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.controller,
    required this.theme,
    this.simulator,
    super.key,
  });

  final PanelController controller;
  final ThemeController theme;

  /// Present only when running against the simulator.
  final FakeDeviceGateway? simulator;

  @override
  Widget build(BuildContext context) {
    final cfg = controller.config;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: PanelCard(
              title: S.settings,
              child: ListView(
                children: [
                  _ThemePicker(theme: theme),
                  _SliderRow(
                    key: const Key('setpoint-slider'),
                    label: S.setpoint,
                    value: cfg.setpoint,
                    min: 25,
                    max: 75,
                    divisions: 50,
                    format: (v) => '${v.toStringAsFixed(0)} °C',
                    onChanged: (v) =>
                        controller.updateConfig(cfg.copyWith(setpoint: v)),
                  ),
                  _SliderRow(
                    label: S.hysteresis,
                    value: cfg.hysteresis,
                    min: 0.5,
                    max: 5,
                    divisions: 9,
                    format: (v) => '${v.toStringAsFixed(1)} °C',
                    onChanged: (v) =>
                        controller.updateConfig(cfg.copyWith(hysteresis: v)),
                  ),
                  _SliderRow(
                    label: S.alarmDelay,
                    value: cfg.delay.inSeconds.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    format: (v) => '${v.toStringAsFixed(0)} s',
                    onChanged: (v) => controller.updateConfig(
                      cfg.copyWith(delay: Duration(seconds: v.round())),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: CalibrationCard(controller: controller)),
                if (simulator != null) ...[
                  const SizedBox(height: 12),
                  Expanded(child: _DemoControls(simulator: simulator!)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// System / Light / Dark. Saved on the device, not on the nodes.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.appearance, style: context.text.titleMedium),
          const SizedBox(height: 8),
          // Shrinks to fit the half-width Settings card on small screens.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ListenableBuilder(
              listenable: theme,
              builder: (context, _) => SegmentedButton<ThemeMode>(
                key: const Key('theme-picker'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text(S.themeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text(S.themeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text(S.themeDark),
                  ),
                ],
                selected: {theme.mode},
                onSelectionChanged: (s) => theme.setMode(s.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: context.text.titleMedium),
              const Spacer(),
              Text(
                format(value),
                style: context.text.titleMedium?.copyWith(
                  color: context.panel.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Lets you rehearse the whole alarm flow without hardware.
class _DemoControls extends StatefulWidget {
  const _DemoControls({required this.simulator});

  final FakeDeviceGateway simulator;

  @override
  State<_DemoControls> createState() => _DemoControlsState();
}

class _DemoControlsState extends State<_DemoControls> {
  @override
  Widget build(BuildContext context) {
    final sim = widget.simulator;
    return PanelCard(
      title: S.demoControls,
      borderColor: context.panel.info,
      child: ListView(
        children: [
          SwitchListTile(
            key: const Key('heat-switch'),
            title: const Text(S.heatProbe),
            secondary: const Icon(Icons.local_fire_department),
            value: sim.heating,
            onChanged: (v) => setState(() => sim.heating = v),
          ),
          SwitchListTile(
            title: const Text(S.sensorOnline),
            secondary: const Icon(Icons.sensors),
            value: sim.sensorOnline,
            onChanged: (v) => setState(() => sim.sensorOnline = v),
          ),
        ],
      ),
    );
  }
}
