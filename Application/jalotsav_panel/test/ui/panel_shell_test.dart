import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jalotsav_panel/core/models.dart';
import 'package:jalotsav_panel/core/panel_controller.dart';
import 'package:jalotsav_panel/main.dart';
import 'package:jalotsav_panel/ui/strings.dart';
import 'package:jalotsav_panel/ui/theme_controller.dart';

import '../support/stub_gateway.dart';

void main() {
  late StubGateway gateway;
  late PanelController controller;
  late ThemeController theme;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpPanel(
    WidgetTester tester,
    Size size, {
    ThemeMode mode = ThemeMode.dark,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    gateway = StubGateway(config: const AlarmConfig(delay: Duration.zero));
    controller = PanelController(gateway);
    theme = ThemeController(mode);
    await tester.pumpWidget(
      JalotsavPanelApp(controller: controller, theme: theme),
    );
  }

  /// Unmount and stop the controller's timer inside the test body, so no
  /// timers are left pending when the framework checks invariants.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await gateway.dispose();
  }

  testWidgets('alarm flow: reading above setpoint → ALARM → acknowledge', (
    tester,
  ) async {
    await pumpPanel(tester, const Size(1024, 600));
    expect(find.text(S.waiting), findsOneWidget);

    gateway.temp.add(TemperatureReading(28.4, DateTime.now()));
    await tester.pump();
    expect(find.text(S.stateNormal), findsOneWidget);
    expect(find.text('28.4'), findsOneWidget);

    gateway.temp.add(TemperatureReading(55, DateTime.now()));
    await tester.pump();
    expect(find.text(S.stateAlarm), findsOneWidget);
    expect(find.text(S.sirenOn), findsOneWidget);

    await tester.tap(find.byKey(const Key('ack-button')));
    await tester.pump();
    expect(find.text(S.stateAcknowledged), findsOneWidget);
    expect(find.text(S.sirenOff), findsOneWidget);
    expect(gateway.commands, ['ack']);
    await finish(tester);
  });

  testWidgets('alarm log screen lists events', (tester) async {
    await pumpPanel(tester, const Size(1024, 600));
    gateway.temp.add(TemperatureReading(60, DateTime.now()));
    await tester.pump();

    await tester.tap(find.text(S.alarms).first);
    await tester.pump();
    expect(find.text(S.eventRaised(60)), findsOneWidget);
    await finish(tester);
  });

  for (final mode in const [ThemeMode.dark, ThemeMode.light]) {
    for (final size in const [
      Size(800, 480),
      Size(1280, 720),
      Size(915, 412), // Pixel 9, landscape
      Size(780, 360), // Galaxy S22, landscape
    ]) {
      testWidgets(
        '${mode.name}: lays out without overflow at ${size.width}x${size.height}',
        (tester) async {
          await pumpPanel(tester, size, mode: mode);
          gateway.temp.add(TemperatureReading(55, DateTime.now()));
          await tester.pump();
          for (final tab in [S.trend, S.alarms, S.settings, S.live]) {
            await tester.tap(find.text(tab).first);
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
          await finish(tester);
        },
      );
    }
  }

  testWidgets('phone landscape with a camera cutout: no overflow', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(left: 50);
    tester.view.viewPadding = const FakeViewPadding(left: 50);
    await pumpPanel(tester, const Size(915, 412));
    gateway.temp.add(TemperatureReading(55, DateTime.now()));
    await tester.pump();
    for (final tab in [S.trend, S.alarms, S.settings, S.live]) {
      await tester.tap(find.text(tab).first);
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byKey(const Key('node-sensor'))).dx,
      greaterThan(50),
    );
    await finish(tester);
  });

  testWidgets('status bar button flips light and dark', (tester) async {
    await pumpPanel(tester, const Size(1024, 600));
    expect(
      Theme.of(tester.element(find.text(S.live))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const Key('theme-toggle')));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.light);
    expect(
      Theme.of(tester.element(find.text(S.live))).brightness,
      Brightness.light,
    );
    await finish(tester);
  });

  testWidgets('Settings picker sets the theme', (tester) async {
    await pumpPanel(tester, const Size(1024, 600));
    await tester.tap(find.text(S.settings).first);
    await tester.pump();

    await tester.tap(find.text(S.themeLight));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.light);

    await tester.tap(find.text(S.themeSystem));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.system);
    await finish(tester);
  });

  testWidgets('portrait first frame (before landscape lock): no overflow', (
    tester,
  ) async {
    await pumpPanel(tester, const Size(412, 915));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Galaxy S22 with system bars showing: no overflow', (
    tester,
  ) async {
    // Landscape S22: 27 px camera cutout on the left, and the status and
    // navigation bars come back while a system dialog is open.
    const bars = FakeViewPadding(left: 27, top: 24, bottom: 24);
    tester.view.padding = bars;
    tester.view.viewPadding = bars;
    await pumpPanel(tester, const Size(780, 360));
    gateway.temp.add(TemperatureReading(55, DateTime.now()));
    await tester.pump();
    for (final tab in [S.trend, S.alarms, S.settings, S.live]) {
      await tester.tap(find.text(tab).first);
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Node 2 offline: the phone shows and silences the alarm', (
    tester,
  ) async {
    await pumpPanel(tester, const Size(1024, 600));
    gateway.unlinkSiren();
    await tester.pump();
    expect(find.text(S.phoneAlarm), findsOneWidget);

    // Default limits: 35 °C with a 3 s delay.
    final t = DateTime.now();
    gateway.temp.add(TemperatureReading(68, t));
    await tester.pump();
    expect(find.text(S.statePending), findsOneWidget);
    gateway.temp.add(TemperatureReading(68, t.add(const Duration(seconds: 4))));
    await tester.pump();
    expect(find.text(S.stateAlarm), findsOneWidget);
    expect(find.text(S.sirenOn), findsOneWidget);

    await tester.tap(find.byKey(const Key('ack-button')));
    await tester.pump();
    expect(find.text(S.stateAcknowledged), findsOneWidget);
    expect(find.text(S.sirenOff), findsOneWidget);
    expect(gateway.commands, isEmpty);
    await finish(tester);
  });

  testWidgets('S22 behind a system dialog (tall nav bar): no overflow', (
    tester,
  ) async {
    const bars = FakeViewPadding(left: 27, top: 24, bottom: 48);
    tester.view.padding = bars;
    tester.view.viewPadding = bars;
    await pumpPanel(tester, const Size(780, 360));
    gateway.unlinkSiren();
    gateway.temp.add(TemperatureReading(27.3, DateTime.now()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
