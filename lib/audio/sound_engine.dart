import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

enum Sfx {
  tap,
  rotate,
  pickup,
  lift,
  place,
  reject,
  toggle,
  complete,
  victory,
  boom,
}

/// Plays the clips in `assets/audio` through Flame.
class SoundEngine {
  SoundEngine({required this.enabled});

  bool enabled;
  var _ready = false;
  var _disposed = false;

  static const _files = {
    Sfx.tap: 'tap.wav',
    Sfx.rotate: 'rotate.wav',
    Sfx.pickup: 'pickup.wav',
    Sfx.lift: 'lift.wav',
    Sfx.place: 'place.wav',
    Sfx.reject: 'reject.wav',
    Sfx.toggle: 'toggle.wav',
    Sfx.complete: 'complete.wav',
    Sfx.victory: 'victory.wav',
    Sfx.boom: 'boom.wav',
  };

  Future<void> init() async {
    try {
      await FlameAudio.audioCache.loadAll(_files.values.toList());
    } on Object {
      return;
    }
    if (_disposed) return;
    _ready = true;
  }

  void play(Sfx sfx) {
    if (!enabled || !_ready) return;
    final file = _files[sfx];
    if (file == null) return;
    unawaited(_start(file));
  }

  Future<void> _start(String file) async {
    try {
      final player = await FlameAudio.play(file, volume: 0.8);
      try {
        await player.onPlayerComplete.first.timeout(const Duration(seconds: 2));
      } on Object {
        // A short clip can finish before the callback is wired.
      }
      await player.dispose();
    } on Object {
      return;
    }
  }

  void dispose() {
    _disposed = true;
    _ready = false;
  }
}
