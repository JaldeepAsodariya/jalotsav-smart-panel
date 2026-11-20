import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// The BLE contract with the ESP32 nodes. Keep in sync with
/// esp32/*/fc26_protocol.h and esp32/ble-test.html (see esp32/README.md).
abstract final class Fc26Ble {
  static const _suffix = '-6a1b-4d2e-9f3c-8b5e7a0c1d2f';

  static const sirenName = 'FC26-SIREN';
  static const sirenService = 'fc260200$_suffix';
  static const sirenState = 'fc260201$_suffix';
  static const sirenCommand = 'fc260202$_suffix';

  /// Node 1 (PT100). The app's primary temperature source; Node 2's relayed
  /// copy is used only while this link is down (see link_merger.dart).
  static const tempName = 'FC26-TEMP';
  static const tempService = 'fc260100$_suffix';
  static const tempReading = 'fc260101$_suffix';
  static const tempCommand = 'fc260102$_suffix';

  /// Node 1 limits the offset to this, either way.
  static const maxOffset = 10.0;

  static const noReading = -32768;

  static Uint8List acknowledge() => _text('ACK');
  static Uint8List testSiren() => _text('TEST');
  static Uint8List config(AlarmConfig c) => _text(
    'CFG=${_num(c.setpoint)},${_num(c.hysteresis)},${c.delay.inSeconds}',
  );

  static Uint8List calibrate(double realCelsius) =>
      _text('CAL=${_num(realCelsius)}');
  static Uint8List setOffset(double offset) =>
      _text('OFS=${_num(offset.clamp(-maxOffset, maxOffset))}');

  static Uint8List _text(String s) => Uint8List.fromList(utf8.encode(s));
  static String _num(double v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// One notification from the siren node's state characteristic.
class SirenState {
  const SirenState({
    required this.celsius,
    required this.snapshot,
    required this.sensorOnline,
    required this.sensorFault,
    required this.seq,
  });

  /// 10 bytes, little-endian: int16 centi-°C · uint8 state · uint8 flags ·
  /// int16 centi setpoint · uint16 centi hysteresis · uint8 delay s · uint8 seq.
  factory SirenState.decode(List<int> bytes) {
    if (bytes.length < 10) {
      throw FormatException('Siren state needs 10 bytes, got ${bytes.length}');
    }
    final d = ByteData.sublistView(Uint8List.fromList(bytes));
    final raw = d.getInt16(0, Endian.little);
    final stateIndex = d.getUint8(2);
    if (stateIndex >= AlarmState.values.length) {
      throw FormatException('Unknown alarm state $stateIndex');
    }
    final flags = d.getUint8(3);
    return SirenState(
      celsius: raw == Fc26Ble.noReading ? null : raw / 100,
      sensorOnline: flags & 2 != 0,
      sensorFault: flags & 8 != 0,
      seq: d.getUint8(9),
      snapshot: SirenSnapshot(
        state: AlarmState.values[stateIndex],
        sirenOn: flags & 1 != 0,
        testActive: flags & 4 != 0,
        hearsSensor: flags & 2 != 0 && flags & 8 == 0,
        config: AlarmConfig(
          setpoint: d.getInt16(4, Endian.little) / 100,
          hysteresis: d.getUint16(6, Endian.little) / 100,
          delay: Duration(seconds: d.getUint8(8)),
        ),
      ),
    );
  }

  final double? celsius;
  final SirenSnapshot snapshot;
  final bool sensorOnline;
  final bool sensorFault;
  final int seq;
}

/// Why Node 1 has no temperature (same order as `fc26::Fault`).
enum TempFault { none, adcMissing, open, short, range }

/// One notification from Node 1's reading characteristic.
class TempNodeReading {
  const TempNodeReading({
    required this.celsius,
    required this.ohms,
    required this.fault,
    required this.seq,
    required this.offset,
  });

  /// 8 bytes, little-endian: int16 centi-°C · uint16 centi-ohms ·
  /// uint8 fault · uint8 seq · int16 centi-°C calibration offset.
  factory TempNodeReading.decode(List<int> bytes) {
    if (bytes.length < 8) {
      throw FormatException('Temp reading needs 8 bytes, got ${bytes.length}');
    }
    final d = ByteData.sublistView(Uint8List.fromList(bytes));
    final faultIndex = d.getUint8(4);
    if (faultIndex >= TempFault.values.length) {
      throw FormatException('Unknown sensor fault $faultIndex');
    }
    final raw = d.getInt16(0, Endian.little);
    return TempNodeReading(
      celsius: raw == Fc26Ble.noReading ? null : raw / 100,
      ohms: d.getUint16(2, Endian.little) / 100,
      fault: TempFault.values[faultIndex],
      seq: d.getUint8(5),
      offset: d.getInt16(6, Endian.little) / 100,
    );
  }

  /// Already includes the calibration [offset]; null while [fault] is set.
  final double? celsius;
  final double ohms;
  final TempFault fault;
  final int seq;
  final double offset;
}
