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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    gateway = StubGateway();
    controller = PanelController(gateway);
    await tester.pumpWidget(
      JalotsavPanelApp(
        controller: controller,
        theme: ThemeController(ThemeMode.dark),
      ),
    );
    await tester.tap(find.text(S.settings).first);
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await gateway.dispose();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
  }

  testWidgets('calibrates to the real temperature set with the steppers', (
    tester,
  ) async {
    await openSettings(tester);
    gateway.calibrationIn.add(const CalibrationInfo(offset: 0, ohms: 111.6));
    gateway.temp.add(TemperatureReading(30.2, DateTime.now()));
    await tester.pump();

    // Starts at the current reading.
    expect(find.text('30.2 °C'), findsOneWidget);
    await tapKey(tester, 'cal-plus-1');
    await tapKey(tester, 'cal-plus-0.1');
    await tapKey(tester, 'cal-plus-0.1');
    expect(find.text('31.4 °C'), findsOneWidget);

    await tapKey(tester, 'calibrate-button');
    expect(gateway.commands, ['cal 31.4']);
    await finish(tester);
  });

  testWidgets('Reset offset sends offset 0', (tester) async {
    await openSettings(tester);
    gateway.calibrationIn.add(const CalibrationInfo(offset: 1.2, ohms: 111.6));
    gateway.temp.add(TemperatureReading(30.2, DateTime.now()));
    await tester.pump();
    expect(find.textContaining('offset +1.20 °C'), findsOneWidget);

    await tapKey(tester, 'reset-offset');
    expect(gateway.commands, ['ofs 0']);
    await finish(tester);
  });

  testWidgets('without the PT100 node, calibration is disabled', (
    tester,
  ) async {
    await openSettings(tester);
    expect(find.text(S.calibrationUnavailable), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('calibrate-button')),
    );
    expect(button.onPressed, isNull);
    await finish(tester);
  });

  testWidgets('a failed calibration is shown on the card', (tester) async {
    await openSettings(tester);
    gateway.calibrationIn.add(const CalibrationInfo(offset: 0, ohms: 111.6));
    gateway.temp.add(TemperatureReading(30.2, DateTime.now()));
    await tester.pump();
    gateway.offline = true;

    await tapKey(tester, 'calibrate-button');
    await tester.pump();
    expect(find.textContaining('Could not calibrate'), findsOneWidget);
    await finish(tester);
  });
}
