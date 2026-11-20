import 'package:flutter_test/flutter_test.dart';
import 'package:jalotsav_panel/core/models.dart';
import 'package:jalotsav_panel/core/siren_node_model.dart';

void main() {
  final t0 = DateTime(2026, 11, 21, 15, 30);
  TemperatureReading at(int sec, double c) =>
      TemperatureReading(c, t0.add(Duration(seconds: sec)));

  test('sounds after the delay and stops when acknowledged', () {
    final node = SirenNodeModel();
    node.feed(at(0, 51));
    expect(node.snapshot().sirenOn, isFalse); // still within the 3 s delay
    node.feed(at(3, 51));
    expect(node.snapshot().state, AlarmState.alarm);
    expect(node.snapshot().sirenOn, isTrue);

    node.acknowledge(t0.add(const Duration(seconds: 4)));
    expect(node.snapshot().state, AlarmState.acknowledged);
    expect(node.snapshot().sirenOn, isFalse);
  });

  test('a siren test lasts two seconds', () {
    final node = SirenNodeModel()..startTest(t0);
    expect(node.snapshot().sirenOn, isTrue);
    expect(node.snapshot().testActive, isTrue);

    node.tick(t0.add(const Duration(milliseconds: 1999)));
    expect(node.snapshot().sirenOn, isTrue);
    node.tick(t0.add(SirenNodeModel.testLength));
    expect(node.snapshot().sirenOn, isFalse);
  });

  test('acknowledge also stops a running test', () {
    final node = SirenNodeModel()..startTest(t0);
    node.acknowledge(t0);
    expect(node.snapshot().sirenOn, isFalse);
  });
}
