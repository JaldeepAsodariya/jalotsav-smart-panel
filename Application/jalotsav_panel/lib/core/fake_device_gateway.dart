import 'dart:async';
import 'dart:math';

import 'device_gateway.dart';
import 'models.dart';
import 'siren_node_model.dart';

/// Simulates the two ESP32 nodes so the UI can be built and rehearsed
/// without hardware. Set [heating] to mimic warming the PT100 probe.
class FakeDeviceGateway implements DeviceGateway {
  FakeDeviceGateway({
    this.ambient = 28,
    Duration tick = const Duration(milliseconds: 500),
    Random? random,
  }) : _random = random ?? Random() {
    _celsius = ambient;
    _timer = Timer.periodic(tick, (_) => _step(tick));
  }

  final double ambient;
  final Random _random;
  final _node = SirenNodeModel();
  late double _celsius;
  late final Timer _timer;

  bool heating = false;
  bool sensorOnline = true;

  final _temp = StreamController<TemperatureReading>.broadcast();
  final _status = StreamController<NodeStatus>.broadcast();
  final _siren = StreamController<SirenSnapshot>.broadcast();
  final _calibration = StreamController<CalibrationInfo>.broadcast();

  /// Simulated Node 1 offset, °C.
  double _offset = 0;

  @override
  Stream<TemperatureReading> get temperature => _temp.stream;

  @override
  Stream<NodeStatus> get nodeStatus => _status.stream;

  @override
  Stream<SirenSnapshot> get siren => _siren.stream;

  @override
  Stream<CalibrationInfo> get calibration => _calibration.stream;

  @override
  Future<void> acknowledge() async {
    _node.acknowledge(DateTime.now());
    _siren.add(_node.snapshot());
  }

  @override
  Future<void> testSiren() async {
    _node.startTest(DateTime.now());
    _siren.add(_node.snapshot());
  }

  @override
  Future<void> writeConfig(AlarmConfig config) async {
    _node.config = config;
    _siren.add(_node.snapshot());
  }

  @override
  Future<void> calibrate(double realCelsius) async =>
      _offset = (realCelsius - _celsius).clamp(-10, 10).toDouble();

  @override
  Future<void> setOffset(double offset) async =>
      _offset = offset.clamp(-10, 10).toDouble();

  void _step(Duration tick) {
    final now = DateTime.now();
    final secs = tick.inMilliseconds / 1000;
    // Heats towards ~62 °C, cools back to ambient — roughly like a probe in a hand or warm water.
    final target = heating ? 62.0 : ambient;
    _celsius += (target - _celsius) * 0.08 * secs * 2;
    final noisy = _celsius + (_random.nextDouble() - 0.5) * 0.2;

    if (sensorOnline) {
      final reading = TemperatureReading(
        double.parse((noisy + _offset).toStringAsFixed(2)),
        now,
      );
      _temp.add(reading);
      _node.feed(reading);
    } else {
      _node.tick(now);
    }
    _siren.add(_node.snapshot());
    _calibration.add(
      sensorOnline
          // PT100: about 0.385 Ω per °C above 100 Ω at 0 °C.
          ? CalibrationInfo(offset: _offset, ohms: 100 + 0.385 * _celsius)
          : const CalibrationInfo.unavailable(),
    );
    _status
      ..add(NodeStatus(id: NodeId.sensor, online: sensorOnline, lastSeen: now))
      ..add(NodeStatus(id: NodeId.buzzer, online: true, lastSeen: now));
  }

  @override
  Future<void> dispose() async {
    _timer.cancel();
    await _temp.close();
    await _status.close();
    await _siren.close();
    await _calibration.close();
  }
}
