import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sfx clips are soft wavs', () async {
    const names = [
      'tap',
      'rotate',
      'pickup',
      'lift',
      'place',
      'reject',
      'toggle',
      'complete',
      'victory',
      'boom',
    ];
    for (final name in names) {
      final data = await rootBundle.load('assets/audio/$name.wav');
      final bytes = data.buffer.asUint8List();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: name);
      final view = ByteData.sublistView(bytes, 44);
      var peak = 0;
      for (var i = 0; i < view.lengthInBytes; i += 2) {
        final sample = view.getInt16(i, Endian.little).abs();
        if (sample > peak) peak = sample;
      }
      expect(peak, greaterThan(4000), reason: name);
      expect(peak, lessThan(22000), reason: name);
    }
  });
}
