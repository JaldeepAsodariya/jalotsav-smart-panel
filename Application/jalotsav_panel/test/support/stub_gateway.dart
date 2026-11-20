import 'dart:async';

import 'package:jalotsav_panel/core/device_gateway.dart';
import 'package:jalotsav_panel/core/models.dart';
import 'package:jalotsav_panel/core/siren_node_model.dart';

/// Test double that behaves like the real nodes: readings pushed into [temp]
/// also feed a [SirenNodeModel], which reports back on [siren] synchronously.
class StubGateway implements DeviceGateway {
  StubGateway({AlarmConfig config = const AlarmConfig()})
    : node = SirenNodeModel(config) {
    _tempIn.stream.listen((r) {
      _temp.add(r);
      if (hearsSensor) node.feed(r);
      _emit();
    });
  }

  final SirenNodeModel node;
  final _tempIn = StreamController<TemperatureReading>.broadcast(sync: true);
  final _temp = StreamController<TemperatureReading>.broadcast(sync: true);
  final status = StreamController<NodeStatus>.broadcast(sync: true);
  final _siren = StreamController<SirenSnapshot>.broadcast(sync: true);

  /// Push Node 1's calibration as if it reported it.
  final calibrationIn = StreamController<CalibrationInfo>.broadcast(sync: true);
  final commands = <String>[];
  final writtenConfigs = <AlarmConfig>[];

  /// Push a reading as if Node 1 sent it.
  StreamSink<TemperatureReading> get temp => _tempIn.sink;

  /// Makes every command fail (the link is up but writes are refused).
  bool offline = false;

  /// False = no BLE link to Node 2: no snapshots, commands fail, and the
  /// panel is told the siren node is offline.
  bool get sirenLinked => _sirenLinked;
  bool _sirenLinked = true;

  void unlinkSiren() {
    _sirenLinked = false;
    status.add(const NodeStatus(id: NodeId.buzzer, online: false));
  }

  /// False = Node 2 is linked but gets nothing from Node 1 over Wi-Fi
  /// (its LED blinks blue): it never sees a temperature and stays NORMAL.
  bool hearsSensor = true;

  void relinkSiren() {
    _sirenLinked = true;
    _emit();
  }

  @override
  Stream<TemperatureReading> get temperature => _temp.stream;

  @override
  Stream<NodeStatus> get nodeStatus => status.stream;

  @override
  Stream<SirenSnapshot> get siren => _siren.stream;

  @override
  Stream<CalibrationInfo> get calibration => calibrationIn.stream;

  /// Same as touching the TTP223 on the hardware.
  void touchButton(DateTime now) {
    node.acknowledge(now);
    _emit();
  }

  @override
  Future<void> acknowledge() async {
    _check('ack');
    node.acknowledge(DateTime.now());
    _emit();
  }

  @override
  Future<void> testSiren() async {
    _check('test');
    node.startTest(DateTime.now());
    _emit();
  }

  @override
  Future<void> writeConfig(AlarmConfig config) async {
    _check('config');
    writtenConfigs.add(config);
    node.config = config;
    _emit();
  }

  @override
  Future<void> calibrate(double realCelsius) async {
    if (offline) throw StateError('PT100 node not connected');
    commands.add('cal ${_fmt(realCelsius)}');
  }

  @override
  Future<void> setOffset(double offset) async {
    if (offline) throw StateError('PT100 node not connected');
    commands.add('ofs ${_fmt(offset)}');
    calibrationIn.add(CalibrationInfo(offset: offset, ohms: 110));
  }

  static String _fmt(double v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  void _check(String command) {
    if (offline || !_sirenLinked) throw StateError('siren node not connected');
    commands.add(command);
  }

  /// Like the real link: every state notification also proves Node 2 is up.
  void _emit() {
    if (!_sirenLinked) return;
    status.add(
      NodeStatus(id: NodeId.buzzer, online: true, lastSeen: DateTime.now()),
    );
    final s = node.snapshot();
    _siren.add(
      SirenSnapshot(
        state: s.state,
        sirenOn: s.sirenOn,
        testActive: s.testActive,
        config: s.config,
        hearsSensor: hearsSensor,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _tempIn.close();
    await _temp.close();
    await status.close();
    await _siren.close();
    await calibrationIn.close();
  }
}
