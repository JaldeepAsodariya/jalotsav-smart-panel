import 'package:flutter_test/flutter_test.dart';
import 'package:jalotsav_panel/core/alarm_engine.dart';
import 'package:jalotsav_panel/core/models.dart';

void main() {
  final t0 = DateTime(2026, 11, 21, 15, 30);
  TemperatureReading at(int sec, double c) =>
      TemperatureReading(c, t0.add(Duration(seconds: sec)));

  AlarmEngine engine({int delaySec = 3}) => AlarmEngine(
    AlarmConfig(
      setpoint: 50,
      hysteresis: 2,
      delay: Duration(seconds: delaySec),
    ),
  );

  test('stays normal below setpoint', () {
    final e = engine();
    expect(e.evaluate(at(0, 49.9)), isNull);
    expect(e.state, AlarmState.normal);
    expect(e.buzzerOn, isFalse);
  });

  test('raises alarm only after staying above setpoint for the delay', () {
    final e = engine();
    expect(e.evaluate(at(0, 51)), isNull);
    expect(e.state, AlarmState.pending);
    expect(e.evaluate(at(2, 52)), isNull);

    final event = e.evaluate(at(3, 52.5));
    expect(event?.type, AlarmEventType.raised);
    expect(event?.celsius, 52.5);
    expect(e.state, AlarmState.alarm);
    expect(e.buzzerOn, isTrue);
  });

  test('a short spike above setpoint does not raise an alarm', () {
    final e = engine();
    e.evaluate(at(0, 51));
    e.evaluate(at(1, 49));
    expect(e.state, AlarmState.normal);
    e.evaluate(at(5, 51));
    expect(e.state, AlarmState.pending);
  });

  test('zero delay raises immediately', () {
    final e = engine(delaySec: 0);
    expect(e.evaluate(at(0, 50))?.type, AlarmEventType.raised);
  });

  test(
    'hysteresis: stays in alarm until temp drops below setpoint - hysteresis',
    () {
      final e = engine(delaySec: 0)..evaluate(at(0, 55));
      expect(e.evaluate(at(1, 49)), isNull, reason: '49 > 48 clear line');
      expect(e.state, AlarmState.alarm);

      final cleared = e.evaluate(at(2, 48));
      expect(cleared?.type, AlarmEventType.cleared);
      expect(e.state, AlarmState.normal);
    },
  );

  test('acknowledge silences the buzzer but keeps the alarm until cleared', () {
    final e = engine(delaySec: 0)..evaluate(at(0, 55));
    expect(e.acknowledge(at(1, 0).at)?.type, AlarmEventType.acknowledged);
    expect(e.state, AlarmState.acknowledged);
    expect(e.buzzerOn, isFalse);

    e.evaluate(at(2, 56));
    expect(e.state, AlarmState.acknowledged, reason: 'no re-trigger while hot');

    expect(e.evaluate(at(3, 47))?.type, AlarmEventType.cleared);
    expect(e.state, AlarmState.normal);
  });

  test('acknowledge does nothing when there is no active alarm', () {
    final e = engine();
    expect(e.acknowledge(t0), isNull);
    expect(e.state, AlarmState.normal);
  });
}
