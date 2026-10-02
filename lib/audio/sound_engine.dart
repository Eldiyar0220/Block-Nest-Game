import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'synth.dart';

/// Plays the generated chimes. Playback is best-effort: if the device refuses
/// a clip, the puzzle keeps going.
class SoundEngine {
  SoundEngine({required this.enabled}) {
    for (final sfx in Sfx.values) {
      _clips[sfx] = renderSfx(sfx);
    }
  }

  bool enabled;
  final Map<Sfx, Uint8List> _clips = {};
  final List<AudioPlayer> _players = [];
  var _cursor = 0;
  var _ready = false;
  var _disposed = false;

  Future<void> init() async {
    final context = AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.game,
        audioFocus: AndroidAudioFocus.none,
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    );
    try {
      await AudioPlayer.global.setAudioContext(context);
    } on Object {
      // Mixing setup is optional.
    }
    if (_disposed) return;

    final created = <AudioPlayer>[];
    try {
      for (var i = 0; i < 5; i++) {
        final player = AudioPlayer();
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume(0.85);
        created.add(player);
      }
    } on Object {
      for (final player in created) {
        unawaited(player.dispose());
      }
      return;
    }
    if (_disposed) {
      for (final player in created) {
        unawaited(player.dispose());
      }
      return;
    }
    _players.addAll(created);
    _ready = true;
  }

  void play(Sfx sfx) {
    if (!enabled || !_ready || _players.isEmpty) return;
    final clip = _clips[sfx];
    if (clip == null) return;
    final player = _players[_cursor];
    _cursor = (_cursor + 1) % _players.length;
    unawaited(_start(player, clip));
  }

  Future<void> _start(AudioPlayer player, Uint8List clip) async {
    try {
      await player.stop();
      await player.play(BytesSource(clip, mimeType: 'audio/wav'));
    } on Object {
      return;
    }
  }

  void dispose() {
    _disposed = true;
    _ready = false;
    for (final player in _players) {
      unawaited(player.dispose());
    }
    _players.clear();
  }
}
