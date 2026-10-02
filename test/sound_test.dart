import 'dart:typed_data';

import 'package:block_nest/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chimes are soft wavs', () {
    for (final sfx in Sfx.values) {
      final bytes = renderSfx(sfx);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: '$sfx');
      final data = ByteData.sublistView(bytes, 44);
      var peak = 0;
      for (var i = 0; i < data.lengthInBytes; i += 2) {
        final sample = data.getInt16(i, Endian.little).abs();
        if (sample > peak) peak = sample;
      }
      expect(peak, greaterThan(4000), reason: '$sfx');
      expect(peak, lessThan(22000), reason: '$sfx');
    }
  });
}
