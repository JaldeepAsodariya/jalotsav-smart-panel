import 'alarm_engine.dart';
import 'models.dart';

/// Dart twin of the siren node's firmware rules (esp32/node2_siren). Lets the
/// simulator and the tests behave like the real hardware.
class SirenNodeModel {
  SirenNodeModel([AlarmConfig config = const AlarmConfig()])
    : _engine = AlarmEngine(config);

  static const testLength = Duration(seconds: 2);

  final AlarmEngine _engine;
  DateTime? _testUntil;

  AlarmConfig get config => _engine.config;
  set config(AlarmConfig value) => _engine.config = value;

  void feed(TemperatureReading reading) {
    _engine.evaluate(reading);
    tick(reading.at);
  }

  void acknowledge(DateTime now) {
    _engine.acknowledge(now);
    _testUntil = null;
  }

  void startTest(DateTime now) {
    if (_engine.state == AlarmState.alarm) return; // already sounding
    _testUntil = now.add(testLength);
  }

  /// Ends a siren test once its time is up.
  void tick(DateTime now) {
    final until = _testUntil;
    if (until != null && !now.isBefore(until)) _testUntil = null;
  }

  SirenSnapshot snapshot() => SirenSnapshot(
    state: _engine.state,
    sirenOn: _engine.buzzerOn || _testUntil != null,
    testActive: _testUntil != null,
    config: config,
  );
}
