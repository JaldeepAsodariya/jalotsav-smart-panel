import 'ble_protocol.dart';
import 'models.dart';

/// Combines the app's two BLE links into what the panel shows.
///
/// - **Node 1 (PT100)** is the temperature source.
/// - **Node 2 (siren)** gives the alarm state, the siren and the limits. It
///   also relays Node 1's temperature (over its own Wi-Fi network); that copy is
///   shown only while the app has no link to Node 1.
class LinkMerger {
  LinkMerger({
    required this.onTemperature,
    required this.onStatus,
    required this.onSiren,
    required this.onCalibration,
  });

  final void Function(TemperatureReading) onTemperature;
  final void Function(NodeStatus) onStatus;
  final void Function(SirenSnapshot) onSiren;
  final void Function(CalibrationInfo) onCalibration;

  bool _tempLinkUp = false;
  bool _sirenLinkUp = false;

  void tempReading(TempNodeReading r, DateTime now) {
    _tempLinkUp = true;
    final c = r.celsius;
    if (c != null) onTemperature(TemperatureReading(c, now));
    onCalibration(CalibrationInfo(offset: r.offset, ohms: r.ohms));
    onStatus(
      NodeStatus(
        id: NodeId.sensor,
        online: r.fault == TempFault.none,
        lastSeen: now,
      ),
    );
  }

  void sirenState(SirenState s, DateTime now) {
    _sirenLinkUp = true;
    onStatus(NodeStatus(id: NodeId.buzzer, online: true, lastSeen: now));
    if (!_tempLinkUp) {
      final c = s.celsius;
      if (c != null) onTemperature(TemperatureReading(c, now));
      onStatus(
        NodeStatus(
          id: NodeId.sensor,
          online: s.sensorOnline && !s.sensorFault,
          lastSeen: now,
        ),
      );
    }
    onSiren(s.snapshot);
  }

  /// If Node 2 is still linked, its next state (within 1 s) reports the
  /// sensor from its relay instead.
  void tempLinkDown() {
    _tempLinkUp = false;
    onCalibration(const CalibrationInfo.unavailable());
    if (!_sirenLinkUp) {
      onStatus(const NodeStatus(id: NodeId.sensor, online: false));
    }
  }

  void sirenLinkDown() {
    _sirenLinkUp = false;
    onStatus(const NodeStatus(id: NodeId.buzzer, online: false));
    if (!_tempLinkUp) {
      onStatus(const NodeStatus(id: NodeId.sensor, online: false));
    }
  }
}
