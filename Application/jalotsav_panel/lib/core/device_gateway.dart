import 'models.dart';

/// The only door between app logic and the hardware.
///
/// The siren node (ESP32 Node 2) runs the alarm itself, so the alarm still
/// works with the app closed. The gateway reports what the node decided and
/// forwards the operator's commands.
///
/// Implementations: [BleDeviceGateway] (real nodes over Bluetooth LE) and
/// [FakeDeviceGateway] (simulated nodes, for UI work and rehearsals).
abstract interface class DeviceGateway {
  Stream<TemperatureReading> get temperature;
  Stream<NodeStatus> get nodeStatus;
  Stream<SirenSnapshot> get siren;
  Stream<CalibrationInfo> get calibration;

  /// Silences an active alarm (same as touching the TTP223).
  Future<void> acknowledge();

  /// Sounds the siren for two seconds.
  Future<void> testSiren();

  /// Stores new limits on the siren node.
  Future<void> writeConfig(AlarmConfig config);

  /// Tells the PT100 node the real temperature right now (from a reference
  /// thermometer); it stores offset = real − raw.
  Future<void> calibrate(double realCelsius);

  /// Sets the PT100 node's offset directly (0 = no correction).
  Future<void> setOffset(double offset);

  Future<void> dispose();
}
