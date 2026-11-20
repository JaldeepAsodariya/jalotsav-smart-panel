import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jalotsav_panel/core/models.dart';
import 'package:jalotsav_panel/core/panel_controller.dart';

import '../support/stub_gateway.dart';

void main() {
  late StubGateway gateway;
  late PanelController controller;
  late DateTime now;
  final t0 = DateTime(2026, 11, 21, 15, 30);
  const noDelay = AlarmConfig(delay: Duration.zero);

  setUp(() {
    gateway = StubGateway(config: noDelay);
    now = t0;
    controller = PanelController(gateway, clock: () => now);
  });

  tearDown(() async {
    controller.dispose();
    await gateway.dispose();
  });

  void push(int sec, double c) =>
      gateway.temp.add(TemperatureReading(c, t0.add(Duration(seconds: sec))));

  List<AlarmEventType> eventTypes() =>
      controller.events.map((e) => e.type).toList();

  test('shows the siren on when the node raises the alarm', () {
    push(0, 30);
    expect(controller.alarmState, AlarmState.normal);
    expect(controller.buzzerOn, isFalse);

    push(1, 55);
    expect(controller.alarmState, AlarmState.alarm);
    expect(controller.buzzerOn, isTrue);
    expect(controller.events.first.type, AlarmEventType.raised);
    expect(controller.events.first.celsius, 55);
  });

  test('acknowledge from the panel silences the siren', () async {
    push(0, 55);
    controller.acknowledge();
    await pumpEventQueue();

    expect(gateway.commands, ['ack']);
    expect(controller.alarmState, AlarmState.acknowledged);
    expect(controller.buzzerOn, isFalse);
    expect(controller.events.first.type, AlarmEventType.acknowledged);
  });

  test('a touch on the hardware button shows up on the panel', () {
    push(0, 55);
    gateway.touchButton(t0);

    expect(gateway.commands, isEmpty);
    expect(controller.alarmState, AlarmState.acknowledged);
    expect(controller.events.first.type, AlarmEventType.acknowledged);
  });

  test('cooling below setpoint − hysteresis clears the alarm by itself', () {
    // Default limits: setpoint 35 °C, clears at 33 °C.
    push(0, 37);
    push(1, 34); // above 33 °C: still alarm
    expect(controller.alarmState, AlarmState.alarm);

    push(2, 33);
    expect(controller.alarmState, AlarmState.normal);
    expect(controller.buzzerOn, isFalse);
    expect(eventTypes(), [AlarmEventType.cleared, AlarmEventType.raised]);
  });

  test('logs a siren test', () async {
    push(0, 30);
    await controller.testBuzzer();
    expect(gateway.commands, ['test']);
    expect(controller.buzzerOn, isTrue);
    expect(controller.events.first.type, AlarmEventType.buzzerTest);
  });

  test('mirrors the limits stored on the node', () {
    push(0, 30);
    expect(controller.config.delay, Duration.zero);
  });

  test('sends only the last of several quick setting changes', () {
    fakeAsync((async) {
      final c = PanelController(gateway, clock: () => now);
      for (final sp in [40.0, 41.0, 42.0]) {
        c.updateConfig(c.config.copyWith(setpoint: sp));
      }
      expect(c.config.setpoint, 42);
      expect(gateway.writtenConfigs, isEmpty);

      async.elapse(const Duration(milliseconds: 500));
      expect(gateway.writtenConfigs.map((c) => c.setpoint), [42]);
      c.dispose();
    });
  });

  test('reports a failed command instead of hiding it', () async {
    gateway.offline = true;
    push(0, 55);
    controller.acknowledge();
    await pumpEventQueue();

    expect(controller.lastError, contains('acknowledge'));
    expect(controller.alarmState, AlarmState.alarm);
  });

  test('keeps a bounded history of readings', () {
    final small = PanelController(gateway, historyLength: 3);
    addTearDown(small.dispose);
    for (var i = 0; i < 5; i++) {
      push(i, 20.0 + i);
    }
    expect(small.history.map((r) => r.celsius), [22, 23, 24]);
  });

  test(
    'flags sensor lost after the timeout and recovers on the next reading',
    () {
      push(0, 30);
      now = t0.add(const Duration(seconds: 9));
      controller.checkSensorTimeout();
      expect(controller.sensorLost, isFalse);

      now = t0.add(const Duration(seconds: 10));
      controller.checkSensorTimeout();
      expect(controller.sensorLost, isTrue);
      expect(controller.events.first.type, AlarmEventType.sensorLost);

      push(11, 30);
      expect(controller.sensorLost, isFalse);
      expect(controller.events.first.type, AlarmEventType.sensorRestored);
    },
  );

  test('tracks node online status', () {
    gateway.status.add(const NodeStatus(id: NodeId.buzzer, online: false));
    expect(controller.node(NodeId.buzzer)?.online, isFalse);
  });

  group('PT100 calibration', () {
    test('forwards Calibrate and Reset to Node 1', () async {
      gateway.calibrationIn.add(const CalibrationInfo(offset: 0, ohms: 110));
      await controller.calibrate(24.5);
      await controller.resetOffset();
      expect(gateway.commands, ['cal 24.5', 'ofs 0']);
      expect(controller.calibration?.offset, 0);
    });

    test('a failed calibration is reported, not thrown', () async {
      gateway.offline = true;
      await controller.calibrate(24.5);
      expect(controller.lastError, contains('calibrate'));
    });
  });
}
