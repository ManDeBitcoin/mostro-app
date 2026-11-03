import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/shared/utils/rating_format.dart';

/// A rating reads the same on every screen (DS-L10N-5): the node's average
/// to two decimals, no trailing zeros, for the locale.
void main() {
  test('keeps the second decimal: 4.97 never reads 5.0', () {
    expect(formatRating(4.97, 'en'), '4.97');
  });

  test('drops trailing zeros', () {
    expect(formatRating(4.9, 'en'), '4.9');
    expect(formatRating(5, 'en'), '5');
  });

  test('rounds past the second decimal', () {
    expect(formatRating(4.375, 'en'), '4.38');
  });

  test('uses the locale decimal separator', () {
    expect(formatRating(4.97, 'es'), '4,97');
  });

  // Each widget rounding its own rating is how the Account card came to show
  // 5,0 for a user the order book showed at 4,97.
  test('no code under lib/ formats a rating by hand', () {
    final byHand = RegExp(r'[rR]ating!?\.toStringAsFixed\(');
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.contains('lib/src/rust/'))
          for (final (i, line) in file.readAsLinesSync().indexed)
            if (byHand.hasMatch(line)) '${file.path}:${i + 1}',
    ];
    expect(offenders, isEmpty, reason: 'use formatRating (DS-L10N-5)');
  });
}
