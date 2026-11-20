import 'package:audioplayers/audioplayers.dart';

import '../core/alarm_sound.dart';

/// The phone's siren: a looping wail (assets/sounds/siren.wav) played on
/// Android's **alarm** stream, so it follows the alarm volume rather than the
/// media volume, and on iOS's playback session, so the mute switch doesn't
/// silence it.
class PhoneSiren implements AlarmSound {
  final _player = AudioPlayer();
  bool _ready = false;

  Future<void> _prepare() async {
    if (_ready) return;
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.loop);
    _ready = true;
  }

  @override
  Future<void> start() async {
    await _prepare();
    await _player.play(AssetSource('sounds/siren.wav'), volume: 1);
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
