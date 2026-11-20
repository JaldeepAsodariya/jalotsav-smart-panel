import 'package:flutter_test/flutter_test.dart';
import 'package:jalotsav_panel/core/alarm_sound.dart';
import 'package:jalotsav_panel/core/models.dart';
import 'package:jalotsav_panel/core/panel_controller.dart';

import '../support/stub_gateway.dart';

class FakeSound implements AlarmSound {
  bool playing = false;
  int starts = 0;

  @override
  Future<void> start() async {
    playing = true;
    starts++;
  }

  @override
  Future<void> stop() async => playing = false;

  @override
  Future<void> dispose() async {}
}

/// Node 2 off: the phone runs the same alarm rules and is the siren.
void main() {
  late StubGateway gateway;
  late PanelController controller;
  late FakeSound sound;
  late DateTime now;
  final t0 = DateTime(2026, 11, 21, 15, 30);
  const noDelay = AlarmConfig(delay: Duration.zero);

  setUp(() {
    gateway = StubGateway(config: noDelay)..unlinkSiren();
    sound = FakeSound();
    now = t0;
    controller = PanelController(
      gateway,
      config: noDelay,
      sound: sound,
      clock: () => now,
    );
  });

  tearDown(() async {
    controller.dispose();
    await gateway.dispose();
  });

  void push(int sec, double c) {
    now = t0.add(Duration(seconds: sec));
    gateway.temp.add(TemperatureReading(c, now));
  }

  test('above the limit, the phone raises the alarm and sounds', () {
    push(0, 30);
    expect(controller.sirenNodeOnline, isFalse);
    expect(controller.alarmState, AlarmState.normal);
    expect(sound.playing, isFalse);

    push(1, 68);
    expect(controller.alarmState, AlarmState.alarm);
    expect(controller.phoneAlarmOn, isTrue);
    expect(controller.buzzerOn, isFalse, reason: 'the hooter is unknown');
    expect(sound.playing, isTrue);
    expect(controller.events.first.type, AlarmEventType.raised);
  });

  test('Silence stops the phone without needing Node 2', () async {
    push(0, 68);
    controller.acknowledge();
    await pumpEventQueue();

    expect(controller.alarmState, AlarmState.acknowledged);
    expect(sound.playing, isFalse);
    expect(gateway.commands, isEmpty);
    expect(controller.lastError, isNull);
  });

  test('cooling below setpoint − hysteresis clears it by itself', () {
    push(0, 68);
    push(1, 34); // still above 33 °C
    expect(sound.playing, isTrue);
    push(2, 33);
    expect(controller.alarmState, AlarmState.normal);
    expect(sound.playing, isFalse);
    expect(controller.events.first.type, AlarmEventType.cleared);
  });

  test('when Node 2 comes back, it takes over and the phone goes quiet', () {
    push(0, 68);
    expect(sound.playing, isTrue);

    gateway.relinkSiren();
    expect(controller.sirenNodeOnline, isTrue);
    expect(sound.playing, isFalse);
    expect(controller.buzzerOn, isTrue, reason: "Node 2's hooter is on");
  });

  test('Test siren sounds the phone for two seconds', () async {
    push(0, 30);
    await controller.testBuzzer();
    expect(sound.playing, isTrue);
    expect(gateway.commands, isEmpty);

    now = t0.add(const Duration(seconds: 3));
    controller.checkSensorTimeout(); // the 1 s tick
    expect(sound.playing, isFalse);
  });

  test('no phone alarm while the sensor is lost', () {
    push(0, 68);
    now = t0.add(const Duration(seconds: 11));
    controller.checkSensorTimeout();
    expect(controller.sensorLost, isTrue);
    expect(sound.playing, isFalse);
  });

  group('Node 2 linked but not hearing Node 1 (Wi-Fi link down)', () {
    setUp(() {
      gateway
        ..hearsSensor = false
        ..relinkSiren();
    });

    test('the phone raises the alarm and sounds', () {
      push(0, 30);
      expect(controller.sirenNodeOnline, isTrue);
      expect(controller.sirenNodeInCharge, isFalse);

      push(1, 68);
      expect(controller.alarmState, AlarmState.alarm);
      expect(controller.phoneAlarmOn, isTrue);
      expect(sound.playing, isTrue);
      expect(controller.events.first.type, AlarmEventType.raised);
    });

    test('Silence and Test siren act on the phone', () async {
      push(0, 68);
      controller.acknowledge();
      await pumpEventQueue();
      expect(controller.alarmState, AlarmState.acknowledged);
      expect(sound.playing, isFalse);

      push(1, 30);
      await controller.testBuzzer();
      expect(sound.playing, isTrue);
      expect(gateway.commands, isEmpty);
    });

    test('once Node 2 hears Node 1 again, it takes over', () {
      push(0, 68);
      expect(sound.playing, isTrue);

      gateway.hearsSensor = true;
      push(1, 68);
      expect(controller.sirenNodeInCharge, isTrue);
      expect(sound.playing, isFalse);
      expect(controller.buzzerOn, isTrue, reason: "Node 2's hooter is on");
    });
  });
}
