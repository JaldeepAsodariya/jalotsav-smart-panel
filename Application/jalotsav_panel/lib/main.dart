import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/device_gateway.dart';
import 'core/fake_device_gateway.dart';
import 'core/panel_controller.dart';
import 'hardware/ble_device_gateway.dart';
import 'hardware/phone_siren.dart';
import 'ui/panel_shell.dart';
import 'ui/strings.dart';
import 'ui/theme.dart';
import 'ui/theme_controller.dart';

/// `flutter run --dart-define=SIMULATOR=true` runs without hardware.
const _useSimulator = bool.fromEnvironment('SIMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The UI is a landscape wall panel. On phones and tablets: landscape only,
  // full screen (swipe from an edge to show the system bars). No-op on desktop.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final simulator = _useSimulator ? FakeDeviceGateway() : null;
  final DeviceGateway gateway = simulator ?? BleDeviceGateway();
  // The phone sounds the alarm itself whenever Node 2 isn't linked.
  final controller = PanelController(gateway, sound: PhoneSiren());
  final theme = await ThemeController.load();
  runApp(
    JalotsavPanelApp(
      controller: controller,
      theme: theme,
      simulator: simulator,
    ),
  );
}

class JalotsavPanelApp extends StatelessWidget {
  const JalotsavPanelApp({
    required this.controller,
    required this.theme,
    this.simulator,
    super.key,
  });

  final PanelController controller;
  final ThemeController theme;
  final FakeDeviceGateway? simulator;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: S.appTitle,
        debugShowCheckedModeBanner: false,
        theme: buildPanelTheme(Brightness.light),
        darkTheme: buildPanelTheme(Brightness.dark),
        themeMode: theme.mode,
        home: PanelShell(
          controller: controller,
          theme: theme,
          simulator: simulator,
        ),
      ),
    );
  }
}
