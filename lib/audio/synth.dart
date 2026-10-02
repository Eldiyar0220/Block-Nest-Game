import 'dart:math' as math;
import 'dart:typed_data';

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

class _Tone {
  const _Tone(
    this.freq,
    this.start,
    this.duration,
    this.amp, {
    this.bright = 0.4,
    this.bend = 0,
  });

  final double freq;
  final double start;
  final double duration;
  final double amp;

  /// How much of the soft upper partials stay in the mallet.
  final double bright;

  /// A short downward pitch fall at the attack, like a mallet strike.
  final double bend;
}

/// Warm mallet notes in D major, written as a tiny WAV so the game needs no
/// sound files.
Uint8List renderSfx(Sfx sfx) {
  final tones = switch (sfx) {
    Sfx.tap => const [_Tone(587.33, 0, 0.14, 0.3, bright: 0.62)],
    Sfx.rotate => const [
      _Tone(329.63, 0, 0.18, 0.28, bright: 0.32, bend: 0.035),
      _Tone(440, 0.09, 0.22, 0.26, bright: 0.55),
    ],
    Sfx.pickup => const [_Tone(493.88, 0, 0.18, 0.26, bright: 0.48)],
    Sfx.lift => const [_Tone(369.99, 0, 0.24, 0.24, bright: 0.28)],
    Sfx.place => const [
      _Tone(220, 0, 0.16, 0.22, bright: 0.08, bend: 0.05),
      _Tone(440, 0.012, 0.3, 0.26, bright: 0.5),
    ],
    Sfx.reject => const [
      _Tone(440, 0, 0.2, 0.18, bright: 0.18),
      _Tone(329.63, 0.09, 0.28, 0.16, bright: 0.12),
    ],
    Sfx.toggle => const [
      _Tone(440, 0, 0.18, 0.24, bright: 0.4),
      _Tone(587.33, 0.08, 0.24, 0.2, bright: 0.52),
    ],
    Sfx.complete => const [
      _Tone(293.66, 0.0, 0.42, 0.24, bright: 0.22),
      _Tone(369.99, 0.1, 0.42, 0.24, bright: 0.34),
      _Tone(440, 0.2, 0.44, 0.24, bright: 0.46),
      _Tone(587.33, 0.3, 0.5, 0.22, bright: 0.58),
    ],
    Sfx.victory => const [
      _Tone(293.66, 0.0, 0.55, 0.22, bright: 0.2),
      _Tone(369.99, 0.12, 0.52, 0.22, bright: 0.3),
      _Tone(440, 0.24, 0.52, 0.22, bright: 0.42),
      _Tone(493.88, 0.36, 0.54, 0.2, bright: 0.5),
      _Tone(587.33, 0.5, 0.62, 0.2, bright: 0.58),
    ],
    Sfx.boom => const [
      _Tone(146.83, 0, 0.42, 0.34, bright: 0.1, bend: 0.07),
      _Tone(220, 0.02, 0.36, 0.2, bright: 0.18),
      _Tone(293.66, 0.05, 0.34, 0.14, bright: 0.42),
    ],
  };

  var length = 0.0;
  for (final tone in tones) {
    final end = tone.start + tone.duration;
    if (end > length) length = end;
  }
  const sampleRate = 22050;
  final count = ((length + 0.02) * sampleRate).ceil();
  final samples = List<double>.filled(count, 0);
  for (final tone in tones) {
    _addMallet(samples, sampleRate, tone);
  }

  var peak = 0.0;
  for (final sample in samples) {
    final mag = sample.abs();
    if (mag > peak) peak = mag;
  }
  if (peak > 1e-6) {
    final gain = 0.46 / peak;
    for (var i = 0; i < samples.length; i++) {
      samples[i] *= gain;
    }
  }
  return _wav(samples, sampleRate);
}

void _addMallet(List<double> samples, int sampleRate, _Tone tone) {
  final start = (tone.start * sampleRate).floor();
  final end = math.min(
    samples.length,
    ((tone.start + tone.duration) * sampleRate).ceil(),
  );
  final step = 1 / sampleRate;
  var phase = 0.0;
  for (var i = start; i < end; i++) {
    final local = i / sampleRate - tone.start;
    if (local < 0 || local > tone.duration) continue;
    final glide = 1 + tone.bend * math.exp(-local * 26);
    phase += 2 * math.pi * tone.freq * glide * step;
    final fifth = math.exp(-local * 8);
    final octave = math.exp(-local * 14);
    final voice =
        math.sin(phase) +
        tone.bright * 0.22 * fifth * math.sin(phase * 1.5) +
        tone.bright * 0.07 * octave * math.sin(phase * 2);
    samples[i] += tone.amp * _env(local, tone.duration) * voice;
  }
}

double _env(double t, double duration) {
  final attack = math.min(0.016, duration * 0.14);
  final release = math.min(0.055, duration * 0.24);
  final attackAmp = t < attack ? t / attack : 1.0;
  final decay = math.exp(-1.05 * t / duration);
  final releaseAmp = t > duration - release
      ? ((duration - t) / release).clamp(0.0, 1.0)
      : 1.0;
  return attackAmp * decay * releaseAmp;
}

Uint8List _wav(List<double> samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  void write(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  write(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  write(8, 'WAVE');
  write(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  write(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    bytes.setInt16(44 + i * 2, (clamped * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
