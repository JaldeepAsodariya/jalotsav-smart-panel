import 'package:flutter_test/flutter_test.dart';
import 'package:jalotsav_panel/core/ble_protocol.dart';
import 'package:jalotsav_panel/core/link_merger.dart';
import 'package:jalotsav_panel/core/models.dart';

import 'ble_protocol_test.dart' show packet;
import 'temp_reading_test.dart' show reading;

void main() {
  final now = DateTime(2026, 11, 21, 15, 10);
  late List<double> temps;
  late List<NodeStatus> status;
  late List<SirenSnapshot> sirens;
  late List<CalibrationInfo> cals;
  late LinkMerger merge;

  setUp(() {
    temps = [];
    status = [];
    sirens = [];
    cals = [];
    merge = LinkMerger(
      onTemperature: (r) => temps.add(r.celsius),
      onStatus: status.add,
      onSiren: sirens.add,
      onCalibration: cals.add,
    );
  });

  bool? last(NodeId id) => status
      .lastWhere(
        (s) => s.id == id,
        orElse: () => const NodeStatus(id: NodeId.sensor, online: false),
      )
      .online;

  SirenState siren({int centiC = 4000, int flags = 0x03}) =>
      SirenState.decode(packet(centiC: centiC, flags: flags));

  test('Node 1 is the temperature source', () {
    merge.tempReading(TempNodeReading.decode(reading(centiC: 3412)), now);
    expect(temps, [34.12]);
    expect(last(NodeId.sensor), isTrue);
  });

  test(
    "while Node 1 is connected, Node 2's relayed temperature is ignored",
    () {
      merge.tempReading(TempNodeReading.decode(reading(centiC: 3412)), now);
      merge.sirenState(siren(centiC: 9999), now);
      expect(temps, [34.12]);
      expect(sirens, hasLength(1));
      expect(last(NodeId.buzzer), isTrue);
    },
  );

  test("without Node 1, Node 2's relayed temperature is the fallback", () {
    merge.sirenState(siren(centiC: 3650), now);
    expect(temps, [36.5]);
    expect(last(NodeId.sensor), isTrue);
  });

  test('Node 1 dropping hands temperature back to the Node 2 relay', () {
    merge.tempReading(TempNodeReading.decode(reading(centiC: 3412)), now);
    merge.tempLinkDown();
    merge.sirenState(siren(centiC: 3650), now);
    expect(temps, [34.12, 36.5]);
  });

  test('a PT100 fault shows the sensor offline with no temperature', () {
    merge.tempReading(
      TempNodeReading.decode(reading(centiC: Fc26Ble.noReading, fault: 2)),
      now,
    );
    expect(temps, isEmpty);
    expect(last(NodeId.sensor), isFalse);
  });

  test('links going down mark their node offline', () {
    merge.tempReading(TempNodeReading.decode(reading()), now);
    merge.sirenState(siren(), now);
    merge.sirenLinkDown();
    expect(last(NodeId.buzzer), isFalse);
    merge.tempLinkDown();
    expect(last(NodeId.sensor), isFalse);
  });

  test("Node 1's offset and resistance reach the calibration screen", () {
    merge.tempReading(
      TempNodeReading.decode(reading(centiOhms: 11063, centiOffset: -50)),
      now,
    );
    expect(cals.single.offset, -0.5);
    expect(cals.single.ohms, 110.63);
  });

  test('calibration is unavailable once Node 1 drops', () {
    merge.tempReading(TempNodeReading.decode(reading()), now);
    merge.tempLinkDown();
    expect(cals.last.available, isFalse);
  });
}
