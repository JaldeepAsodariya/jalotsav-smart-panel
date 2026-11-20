import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jalotsav_panel/core/ble_protocol.dart';

/// Builds a packet exactly like node1_temperature.ino's BLE reading.
List<int> reading({
  int centiC = 2731,
  int centiOhms = 11063,
  int fault = 0,
  int seq = 4,
  int centiOffset = -50,
}) {
  final d = ByteData(8)
    ..setInt16(0, centiC, Endian.little)
    ..setUint16(2, centiOhms, Endian.little)
    ..setUint8(4, fault)
    ..setUint8(5, seq)
    ..setInt16(6, centiOffset, Endian.little);
  return d.buffer.asUint8List();
}

void main() {
  group('TempNodeReading.decode', () {
    test('decodes a good reading', () {
      final r = TempNodeReading.decode(reading());
      expect(r.celsius, 27.31);
      expect(r.ohms, 110.63);
      expect(r.fault, TempFault.none);
      expect(r.seq, 4);
      expect(r.offset, -0.5);
    });

    test('a fault carries no temperature', () {
      final r = TempNodeReading.decode(
        reading(centiC: Fc26Ble.noReading, fault: 2),
      );
      expect(r.celsius, isNull);
      expect(r.fault, TempFault.open);
    });

    test('negative temperatures survive', () {
      expect(TempNodeReading.decode(reading(centiC: -1250)).celsius, -12.5);
    });

    test('rejects short packets and unknown faults', () {
      expect(
        () => TempNodeReading.decode([1, 2, 3]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => TempNodeReading.decode(reading(fault: 9)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
