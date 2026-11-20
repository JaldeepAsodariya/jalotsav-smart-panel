import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jalotsav_panel/core/ble_protocol.dart';
import 'package:jalotsav_panel/core/models.dart';

/// Builds a packet exactly like node2_siren.ino's notifyState().
List<int> packet({
  int centiC = 5512,
  int state = 2,
  int flags = 0x03,
  int setpoint = 5000,
  int hysteresis = 200,
  int delay = 3,
  int seq = 7,
}) {
  final d = ByteData(10)
    ..setInt16(0, centiC, Endian.little)
    ..setUint8(2, state)
    ..setUint8(3, flags)
    ..setInt16(4, setpoint, Endian.little)
    ..setUint16(6, hysteresis, Endian.little)
    ..setUint8(8, delay)
    ..setUint8(9, seq);
  return d.buffer.asUint8List();
}

void main() {
  group('SirenState.decode', () {
    test('reads temperature, state, flags and limits', () {
      final s = SirenState.decode(packet());
      expect(s.celsius, 55.12);
      expect(s.snapshot.state, AlarmState.alarm);
      expect(s.snapshot.sirenOn, isTrue);
      expect(s.sensorOnline, isTrue);
      expect(s.snapshot.testActive, isFalse);
      expect(s.sensorFault, isFalse);
      expect(s.snapshot.config.setpoint, 50);
      expect(s.snapshot.config.hysteresis, 2);
      expect(s.snapshot.config.delay, const Duration(seconds: 3));
      expect(s.seq, 7);
    });

    test('handles negative temperatures and the no-reading marker', () {
      expect(SirenState.decode(packet(centiC: -1050)).celsius, -10.5);
      expect(SirenState.decode(packet(centiC: -32768)).celsius, isNull);
    });

    test('reads the test and fault flags', () {
      final s = SirenState.decode(packet(state: 0, flags: 0x0D));
      expect(s.snapshot.state, AlarmState.normal);
      expect(s.snapshot.testActive, isTrue);
      expect(s.sensorFault, isTrue);
      expect(s.sensorOnline, isFalse);
    });

    test('Node 2 hears the sensor only when online and fault-free', () {
      expect(
        SirenState.decode(packet(flags: 0x02)).snapshot.hearsSensor,
        isTrue,
      );
      expect(
        SirenState.decode(packet(flags: 0x00)).snapshot.hearsSensor,
        isFalse,
      );
      expect(
        SirenState.decode(packet(flags: 0x0A)).snapshot.hearsSensor,
        isFalse,
      );
    });

    test('rejects short packets and unknown states', () {
      expect(() => SirenState.decode([1, 2, 3]), throwsFormatException);
      expect(() => SirenState.decode(packet(state: 9)), throwsFormatException);
    });
  });

  group('commands', () {
    test('are the text the firmware expects', () {
      expect(utf8.decode(Fc26Ble.acknowledge()), 'ACK');
      expect(utf8.decode(Fc26Ble.testSiren()), 'TEST');
      expect(utf8.decode(Fc26Ble.config(const AlarmConfig())), 'CFG=35,2,3');
      expect(
        utf8.decode(
          Fc26Ble.config(
            const AlarmConfig(
              setpoint: 42.5,
              hysteresis: 1.25,
              delay: Duration(seconds: 10),
            ),
          ),
        ),
        'CFG=42.5,1.25,10',
      );
    });

    test('fit in one BLE write', () {
      const worst = AlarmConfig(
        setpoint: 149.99,
        hysteresis: 19.99,
        delay: Duration(seconds: 60),
      );
      expect(Fc26Ble.config(worst).length, lessThanOrEqualTo(20));
    });
  });

  group('PT100 calibration commands', () {
    test('CAL= sends the real temperature', () {
      expect(utf8.decode(Fc26Ble.calibrate(24.5)), 'CAL=24.5');
      expect(utf8.decode(Fc26Ble.calibrate(-3)), 'CAL=-3');
    });

    test('OFS= sends the offset, limited to ±10 °C like the firmware', () {
      expect(utf8.decode(Fc26Ble.setOffset(0)), 'OFS=0');
      expect(utf8.decode(Fc26Ble.setOffset(-0.35)), 'OFS=-0.35');
      expect(utf8.decode(Fc26Ble.setOffset(42)), 'OFS=10');
    });
  });
}
