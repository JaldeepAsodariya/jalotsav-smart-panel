import 'models.dart';

/// Pure, time-injected alarm state machine. No timers, no I/O — easy to test
/// and identical everywhere the app runs.
class AlarmEngine {
  AlarmEngine(this.config);

  AlarmConfig config;
  AlarmState _state = AlarmState.normal;
  DateTime? _aboveSince;

  AlarmState get state => _state;

  /// The buzzer should sound only while an un-acknowledged alarm is active.
  bool get buzzerOn => _state == AlarmState.alarm;

  /// Feeds one reading. Returns the event produced by this transition, if any.
  AlarmEvent? evaluate(TemperatureReading r) {
    final t = r.celsius;
    switch (_state) {
      case AlarmState.normal:
        if (t >= config.setpoint) {
          _aboveSince = r.at;
          _state = AlarmState.pending;
          return _maybeRaise(r);
        }
        return null;
      case AlarmState.pending:
        if (t < config.setpoint) {
          _state = AlarmState.normal;
          _aboveSince = null;
          return null;
        }
        return _maybeRaise(r);
      case AlarmState.alarm:
      case AlarmState.acknowledged:
        if (t <= config.clearBelow) {
          _state = AlarmState.normal;
          _aboveSince = null;
          return AlarmEvent(AlarmEventType.cleared, r.at, celsius: t);
        }
        return null;
    }
  }

  AlarmEvent? acknowledge(DateTime now) {
    if (_state != AlarmState.alarm) return null;
    _state = AlarmState.acknowledged;
    return AlarmEvent(AlarmEventType.acknowledged, now);
  }

  AlarmEvent? _maybeRaise(TemperatureReading r) {
    if (r.at.difference(_aboveSince!) >= config.delay) {
      _state = AlarmState.alarm;
      return AlarmEvent(AlarmEventType.raised, r.at, celsius: r.celsius);
    }
    return null;
  }
}
