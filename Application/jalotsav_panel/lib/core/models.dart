/// Plain data types shared by the panel UI, the simulator and the tests.
/// No Flutter imports here on purpose, so the core stays pure Dart.
library;

class TemperatureReading {
  const TemperatureReading(this.celsius, this.at);

  final double celsius;
  final DateTime at;
}

enum NodeId { sensor, buzzer }

/// Node 1's PT100 calibration, as it reports it.
class CalibrationInfo {
  const CalibrationInfo({required this.offset, required this.ohms})
    : available = true;

  /// No link to Node 1, so it can't be read or changed.
  const CalibrationInfo.unavailable() : offset = 0, ohms = 0, available = false;

  /// Added to the raw reading, °C. Stored on Node 1.
  final double offset;

  /// Probe resistance right now (100 Ω at 0 °C for a PT100).
  final double ohms;
  final bool available;
}

class NodeStatus {
  const NodeStatus({required this.id, required this.online, this.lastSeen});

  final NodeId id;
  final bool online;
  final DateTime? lastSeen;
}

/// normal → pending (above setpoint, waiting for delay) → alarm → acknowledged.
/// Clearing (temp below setpoint − hysteresis) returns to normal.
enum AlarmState { normal, pending, alarm, acknowledged }

class AlarmConfig {
  const AlarmConfig({
    this.setpoint = 35,
    this.hysteresis = 2,
    this.delay = const Duration(seconds: 3),
    this.sensorTimeout = const Duration(seconds: 10),
  });

  final double setpoint;
  final double hysteresis;
  final Duration delay;
  final Duration sensorTimeout;

  double get clearBelow => setpoint - hysteresis;

  AlarmConfig copyWith({
    double? setpoint,
    double? hysteresis,
    Duration? delay,
  }) => AlarmConfig(
    setpoint: setpoint ?? this.setpoint,
    hysteresis: hysteresis ?? this.hysteresis,
    delay: delay ?? this.delay,
    sensorTimeout: sensorTimeout,
  );
}

enum AlarmEventType {
  raised,
  acknowledged,
  cleared,
  sensorLost,
  sensorRestored,
  buzzerTest,
}

class AlarmEvent {
  const AlarmEvent(this.type, this.at, {this.celsius});

  final AlarmEventType type;
  final DateTime at;
  final double? celsius;
}

/// What the siren node (ESP32 Node 2) reports. The node owns the alarm
/// decision; the panel mirrors it.
class SirenSnapshot {
  const SirenSnapshot({
    required this.state,
    required this.sirenOn,
    required this.config,
    this.testActive = false,
    this.hearsSensor = true,
  });

  final AlarmState state;
  final bool sirenOn;
  final bool testActive;
  final AlarmConfig config;

  /// Node 2 is getting good readings from Node 1 over Wi-Fi. While false
  /// it can't judge the temperature (it stays NORMAL, LED blinking blue).
  final bool hearsSensor;
}
