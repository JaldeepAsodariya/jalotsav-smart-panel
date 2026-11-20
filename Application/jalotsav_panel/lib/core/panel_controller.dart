import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'alarm_sound.dart';
import 'device_gateway.dart';
import 'models.dart';
import 'siren_node_model.dart';

/// Mirrors the hardware for the UI. The siren node owns the alarm decision;
/// this controller keeps history, turns state changes into an event log, and
/// forwards operator commands. Uses only ChangeNotifier.
///
/// **While the siren node (Node 2) isn't linked, or is linked but gets no
/// readings from Node 1, the phone takes over:** it runs the same rules
/// ([SirenNodeModel]) on Node 1's readings and plays [sound] instead of the
/// hooter. Silence and Test siren then act on the phone. As soon as Node 2 is
/// linked and hearing Node 1, it is in charge and the phone stops.
class PanelController extends ChangeNotifier {
  PanelController(
    this._gateway, {
    this._config = const AlarmConfig(),
    DateTime Function()? clock,
    this.historyLength = 600,
    this.configDebounce = const Duration(milliseconds: 400),
    this.sound = const SilentAlarmSound(),
  }) : _clock = clock ?? DateTime.now,
       _local = SirenNodeModel(_config) {
    _subs
      ..add(_gateway.temperature.listen(_onReading))
      ..add(_gateway.nodeStatus.listen(_onNodeStatus))
      ..add(_gateway.siren.listen(_onSiren))
      ..add(_gateway.calibration.listen(_onCalibration));
    _staleTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => checkSensorTimeout(),
    );
  }

  final DeviceGateway _gateway;

  /// The phone's siren, used only while Node 2 is offline.
  final AlarmSound sound;
  final SirenNodeModel _local;
  SirenSnapshot? _localSnap;
  bool _phoneSounding = false;
  final DateTime Function() _clock;
  final int historyLength;

  /// Slider drags produce many changes; only the last one is sent.
  final Duration configDebounce;
  final _subs = <StreamSubscription<Object>>[];
  late final Timer _staleTimer;
  Timer? _configWrite;

  final _history = ListQueue<TemperatureReading>();
  final _events = <AlarmEvent>[];
  final _nodes = <NodeId, NodeStatus>{};
  AlarmConfig _config;
  SirenSnapshot? _siren;
  bool _sensorLost = false;
  String? _lastError;
  CalibrationInfo? _calibration;

  AlarmConfig get config => _config;

  /// True while the app has a live link to Node 2.
  bool get sirenNodeOnline => _nodes[NodeId.buzzer]?.online ?? false;

  /// Node 2 is linked and can see the temperature, so its decision counts.
  bool get sirenNodeInCharge =>
      sirenNodeOnline && (_siren?.hearsSensor ?? true);

  /// Node 2's state when it is in charge, otherwise the phone's own.
  AlarmState get alarmState =>
      (sirenNodeInCharge ? _siren : _localSnap)?.state ?? AlarmState.normal;
  bool get sensorLost => _sensorLost;

  /// The hooter on Node 2. False (unknown) while Node 2 isn't linked.
  bool get buzzerOn => sirenNodeOnline && (_siren?.sirenOn ?? false);

  /// The phone is sounding in place of the hooter.
  bool get phoneAlarmOn =>
      !sirenNodeInCharge && !_sensorLost && (_localSnap?.sirenOn ?? false);

  /// The last command that failed (e.g. siren node not connected), if any.
  String? get lastError => _lastError;
  TemperatureReading? get latest => _history.isEmpty ? null : _history.last;
  List<TemperatureReading> get history => List.unmodifiable(_history);

  /// Newest first.
  List<AlarmEvent> get events => List.unmodifiable(_events.reversed);
  NodeStatus? node(NodeId id) => _nodes[id];

  /// Node 1's calibration; null until it has reported once.
  CalibrationInfo? get calibration => _calibration;

  void _onCalibration(CalibrationInfo c) {
    final was = _calibration;
    _calibration = c;
    if (was?.offset != c.offset ||
        was?.available != c.available ||
        was?.ohms != c.ohms) {
      notifyListeners();
    }
  }

  void _onReading(TemperatureReading r) {
    _history.add(r);
    while (_history.length > historyLength) {
      _history.removeFirst();
    }
    if (_sensorLost) {
      _sensorLost = false;
      _log(AlarmEvent(AlarmEventType.sensorRestored, r.at, celsius: r.celsius));
    }
    _local.feed(r);
    _updateLocal(r.at);
    notifyListeners();
  }

  void _onNodeStatus(NodeStatus s) {
    final prev = _nodes[s.id];
    _nodes[s.id] = s;
    if (prev?.online != s.online) {
      _syncSound();
      notifyListeners();
    }
  }

  void _onSiren(SirenSnapshot s) {
    final was = _siren;
    _siren = s;
    if (s.hearsSensor) _logTransition(was, s, _clock());
    // The node is the source of truth, except while a local edit is in flight.
    if (!(_configWrite?.isActive ?? false)) _setConfig(s.config);
    _syncSound();
    notifyListeners();
  }

  /// Turns a state change (from Node 2 or the phone) into log entries.
  void _logTransition(SirenSnapshot? was, SirenSnapshot s, DateTime now) {
    final c = latest?.celsius;
    final before = was?.state ?? AlarmState.normal;
    if (s.state != before) {
      if (s.state == AlarmState.alarm) {
        _log(AlarmEvent(AlarmEventType.raised, now, celsius: c));
      } else if (s.state == AlarmState.acknowledged &&
          before == AlarmState.alarm) {
        _log(AlarmEvent(AlarmEventType.acknowledged, now));
      } else if (s.state == AlarmState.normal &&
          (before == AlarmState.alarm || before == AlarmState.acknowledged)) {
        _log(AlarmEvent(AlarmEventType.cleared, now, celsius: c));
      }
    }
    if (s.testActive && !(was?.testActive ?? false)) {
      _log(AlarmEvent(AlarmEventType.buzzerTest, now));
    }
  }

  /// Re-evaluates the phone's copy of the alarm; logs it while it is in
  /// charge (Node 2 offline) and starts or stops the phone's sound.
  void _updateLocal(DateTime now) {
    _local.tick(now);
    final was = _localSnap;
    final s = _local.snapshot();
    _localSnap = s;
    if (!sirenNodeInCharge) _logTransition(was, s, now);
    _syncSound();
  }

  void _setConfig(AlarmConfig c) {
    _config = c;
    _local.config = c;
  }

  void _syncSound() {
    final want = phoneAlarmOn;
    if (want == _phoneSounding) return;
    _phoneSounding = want;
    unawaited(_play(want));
  }

  Future<void> _play(bool on) async {
    try {
      await (on ? sound.start() : sound.stop());
    } on Object catch (e) {
      debugPrint('[panel] phone alarm sound failed: $e');
    }
  }

  /// Raises "sensor lost" when no reading arrived within the timeout.
  /// Public so tests can drive it with a fake clock.
  void checkSensorTimeout() {
    final now = _clock();
    final testWas = _localSnap?.testActive ?? false;
    _updateLocal(now); // also ends a 2 s phone test
    if (testWas != (_localSnap?.testActive ?? false)) notifyListeners();
    final last = latest;
    if (last == null || _sensorLost) return;
    if (now.difference(last.at) >= config.sensorTimeout) {
      _sensorLost = true;
      _log(AlarmEvent(AlarmEventType.sensorLost, now));
      _syncSound();
      notifyListeners();
    }
  }

  /// Silences the alarm on whichever is in charge: Node 2 or the phone.
  void acknowledge() {
    if (sirenNodeInCharge) {
      unawaited(_send('acknowledge', _gateway.acknowledge));
      return;
    }
    final now = _clock();
    _local.acknowledge(now);
    _updateLocal(now);
    notifyListeners();
  }

  /// Two seconds of siren: the hooter when Node 2 is in charge, else the
  /// phone.
  Future<void> testBuzzer() async {
    if (sirenNodeInCharge) return _send('test siren', _gateway.testSiren);
    final now = _clock();
    _local.startTest(now);
    _updateLocal(now);
    notifyListeners();
  }

  /// "The real temperature is [realCelsius]": Node 1 stores the offset.
  Future<void> calibrate(double realCelsius) =>
      _send('calibrate', () => _gateway.calibrate(realCelsius));

  /// Removes the correction (offset 0).
  Future<void> resetOffset() =>
      _send('reset the offset', () => _gateway.setOffset(0));

  void updateConfig(AlarmConfig next) {
    _setConfig(next);
    notifyListeners();
    _configWrite?.cancel();
    _configWrite = Timer(
      configDebounce,
      () => unawaited(
        _send('save settings', () => _gateway.writeConfig(_config)),
      ),
    );
  }

  Future<void> _send(String what, Future<void> Function() command) async {
    try {
      await command();
      if (_lastError != null) {
        _lastError = null;
        notifyListeners();
      }
    } on Object catch (e) {
      _lastError = 'Could not $what: $e';
      debugPrint('[panel] $_lastError');
      notifyListeners();
    }
  }

  void _log(AlarmEvent e) {
    _events.add(e);
    if (_events.length > 200) _events.removeAt(0);
  }

  @override
  void dispose() {
    _staleTimer.cancel();
    unawaited(_play(false));
    _configWrite?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
