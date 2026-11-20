/// The phone's own siren, used when the siren node (Node 2) isn't linked.
/// Kept as an interface so the alarm logic stays plugin-free and testable.
abstract interface class AlarmSound {
  /// Starts a looping alarm. Calling it while already playing is harmless.
  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

/// No sound: the default in tests and where audio isn't wanted.
class SilentAlarmSound implements AlarmSound {
  const SilentAlarmSound();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
