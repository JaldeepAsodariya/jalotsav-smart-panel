import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../core/ble_protocol.dart';
import '../core/device_gateway.dart';
import '../core/link_merger.dart';
import '../core/models.dart';

/// Talks Bluetooth LE to both ESP32 nodes at once:
///
/// - **Node 1 `FC26-TEMP`**: the temperature (primary source).
/// - **Node 2 `FC26-SIREN`**: alarm state, siren, limits and commands.
///
/// Each link is found, connected and re-connected on its own, so either board
/// can be switched off and on. What reaches the UI is decided by [LinkMerger].
/// Nothing to configure: no pairing, no passwords.
class BleDeviceGateway implements DeviceGateway {
  BleDeviceGateway({
    this.retryDelay = const Duration(seconds: 2),
    this.scanWindow = const Duration(seconds: 10),
  }) {
    _merge = LinkMerger(
      onTemperature: _guard(_temp.add),
      onStatus: _guard(_status.add),
      onSiren: _guard(_siren.add),
      onCalibration: _guard(_calibration.add),
    );
    unawaited(_run());
  }

  final Duration retryDelay;

  /// How long each scan looks for the missing node(s) before pausing.
  final Duration scanWindow;

  final _temp = StreamController<TemperatureReading>.broadcast();
  final _status = StreamController<NodeStatus>.broadcast();
  final _siren = StreamController<SirenSnapshot>.broadcast();
  final _calibration = StreamController<CalibrationInfo>.broadcast();
  late final LinkMerger _merge;

  String? _tempId;
  TempFault? _lastFault;
  String? _sirenId;
  final _subs = <String, List<StreamSubscription<Object?>>>{};
  Completer<void>? _wake;
  bool _disposed = false;

  @override
  Stream<TemperatureReading> get temperature => _temp.stream;

  @override
  Stream<NodeStatus> get nodeStatus => _status.stream;

  @override
  Stream<SirenSnapshot> get siren => _siren.stream;

  @override
  Stream<CalibrationInfo> get calibration => _calibration.stream;

  @override
  Future<void> acknowledge() => _write(Fc26Ble.acknowledge());

  @override
  Future<void> testSiren() => _write(Fc26Ble.testSiren());

  @override
  Future<void> writeConfig(AlarmConfig config) =>
      _write(Fc26Ble.config(config));

  @override
  Future<void> calibrate(double realCelsius) =>
      _writeTemp(Fc26Ble.calibrate(realCelsius));

  @override
  Future<void> setOffset(double offset) =>
      _writeTemp(Fc26Ble.setOffset(offset));

  Future<void> _writeTemp(Uint8List bytes) async {
    final id = _tempId;
    if (id == null) throw StateError('${Fc26Ble.tempName} is not connected');
    await UniversalBle.write(
      id,
      Fc26Ble.tempService,
      Fc26Ble.tempCommand,
      bytes,
    );
  }

  /// Finds whichever node is missing, connects it, and repeats. With both
  /// linked, sleeps until one drops.
  Future<void> _run() async {
    while (!_disposed) {
      final wantTemp = _tempId == null;
      final wantSiren = _sirenId == null;
      if (!wantTemp && !wantSiren) {
        _wake = Completer<void>();
        await _wake!.future;
        continue;
      }
      _Found? found;
      try {
        await UniversalBle.requestPermissions();
        found = await _scan(wantTemp: wantTemp, wantSiren: wantSiren);
      } on Object catch (e) {
        debugPrint('[ble] scan failed: $e');
      }
      if (_disposed) return;
      if (found == null) {
        final missing = [
          if (wantTemp) Fc26Ble.tempName,
          if (wantSiren) Fc26Ble.sirenName,
        ].join(' + ');
        debugPrint('[ble] $missing not in range, still looking');
        await Future<void>.delayed(retryDelay);
        continue;
      }
      try {
        if (found.isSiren) {
          await _connectSiren(found.deviceId);
        } else {
          await _connectTemp(found.deviceId);
        }
      } on Object catch (e) {
        debugPrint('[ble] ${found.name}: $e, retrying');
        await _release(found.deviceId, disconnect: true);
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  /// First wanted node seen in [scanWindow], or null.
  Future<_Found?> _scan({
    required bool wantTemp,
    required bool wantSiren,
  }) async {
    final found = Completer<_Found?>();
    final sub = UniversalBle.scanStream.listen((d) {
      if (found.isCompleted) return;
      final services = d.services.map((s) => s.toLowerCase());
      final isSiren =
          d.name == Fc26Ble.sirenName ||
          services.contains(Fc26Ble.sirenService);
      final isTemp =
          d.name == Fc26Ble.tempName || services.contains(Fc26Ble.tempService);
      if (isSiren && wantSiren) {
        found.complete(_Found(d.deviceId, isSiren: true));
      } else if (isTemp && wantTemp) {
        found.complete(_Found(d.deviceId, isSiren: false));
      }
    });
    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          withServices: [Fc26Ble.tempService, Fc26Ble.sirenService],
        ),
      );
      return await found.future.timeout(scanWindow, onTimeout: () => null);
    } finally {
      await sub.cancel();
      await UniversalBle.stopScan();
    }
  }

  Future<void> _connectTemp(String id) async {
    await _subscribe(
      id,
      service: Fc26Ble.tempService,
      characteristic: Fc26Ble.tempReading,
      onValue: (bytes) {
        final r = _decode(() => TempNodeReading.decode(bytes));
        if (r == null) return;
        if (r.fault != _lastFault) {
          _lastFault = r.fault;
          debugPrint(
            '[ble] PT100 ${r.fault == TempFault.none ? 'ok: ${r.celsius} °C' : 'fault: ${r.fault.name} (${r.ohms} Ω)'}',
          );
        }
        _merge.tempReading(r, DateTime.now());
      },
    );
    _tempId = id;
    debugPrint('[ble] connected to ${Fc26Ble.tempName}');
  }

  Future<void> _connectSiren(String id) async {
    await _subscribe(
      id,
      service: Fc26Ble.sirenService,
      characteristic: Fc26Ble.sirenState,
      onValue: (bytes) {
        final s = _decode(() => SirenState.decode(bytes));
        if (s != null) _merge.sirenState(s, DateTime.now());
      },
    );
    _sirenId = id;
    debugPrint('[ble] connected to ${Fc26Ble.sirenName}');
  }

  /// Connect → discover → watch for the link dropping → subscribe → first read.
  Future<void> _subscribe(
    String id, {
    required String service,
    required String characteristic,
    required void Function(Uint8List) onValue,
  }) async {
    await UniversalBle.connect(id, timeout: const Duration(seconds: 15));
    await UniversalBle.discoverServices(id);
    _subs[id] = [
      UniversalBle.connectionStream(id).listen((up) {
        if (!up) unawaited(_onDisconnected(id));
      }),
      UniversalBle.characteristicValueStream(
        id,
        characteristic,
      ).listen(onValue),
    ];
    await UniversalBle.subscribeNotifications(id, service, characteristic);
    onValue(await UniversalBle.read(id, service, characteristic));
  }

  Future<void> _onDisconnected(String id) async {
    if (id == _tempId) {
      _tempId = null;
      _merge.tempLinkDown();
      debugPrint('[ble] ${Fc26Ble.tempName} disconnected');
    } else if (id == _sirenId) {
      _sirenId = null;
      _merge.sirenLinkDown();
      debugPrint('[ble] ${Fc26Ble.sirenName} disconnected');
    }
    await _release(id);
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  Future<void> _release(String id, {bool disconnect = false}) async {
    for (final s in _subs.remove(id) ?? const []) {
      await s.cancel();
    }
    if (!disconnect) return;
    try {
      await UniversalBle.disconnect(id);
    } on Object catch (e) {
      debugPrint('[ble] disconnect $id: $e');
    }
  }

  T? _decode<T>(T Function() decode) {
    try {
      return decode();
    } on FormatException catch (e) {
      debugPrint('[ble] ignored bad packet: ${e.message}');
      return null;
    }
  }

  void Function(T) _guard<T>(void Function(T) add) => (v) {
    if (!_disposed) add(v);
  };

  Future<void> _write(Uint8List bytes) async {
    final id = _sirenId;
    if (id == null) {
      throw StateError('${Fc26Ble.sirenName} is not connected');
    }
    await UniversalBle.write(
      id,
      Fc26Ble.sirenService,
      Fc26Ble.sirenCommand,
      bytes,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    for (final id in [?_tempId, ?_sirenId]) {
      await _release(id, disconnect: true);
    }
    await _temp.close();
    await _status.close();
    await _siren.close();
    await _calibration.close();
  }
}

class _Found {
  const _Found(this.deviceId, {required this.isSiren});

  final String deviceId;
  final bool isSiren;

  String get name => isSiren ? Fc26Ble.sirenName : Fc26Ble.tempName;
}
