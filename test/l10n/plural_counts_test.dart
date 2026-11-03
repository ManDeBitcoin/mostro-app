import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DS-L10N-5: a count in a plural string is grouped for the locale
/// (`1,323 ratings`; `1.323 calificaciones`), like every other figure the app
/// shows. gen-l10n prints a bare `int` placeholder ungrouped (`1323`) unless
/// the template gives it a number format.
void main() {
  test('every count in a plural string of app_en.arb is grouped', () {
    final raw =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final ungrouped = [
      for (final MapEntry(:key, :value) in raw.entries)
        if (!key.startsWith('@') && value is String && value.contains('plural'))
          for (final MapEntry(key: name, value: meta)
              in ((raw['@$key'] as Map<String, dynamic>?)?['placeholders']
                          as Map<String, dynamic>? ??
                      const {})
                  .entries)
            if ((meta as Map<String, dynamic>)['type'] case 'int' || 'num')
              if (value.contains('{$name}') &&
                  meta['format'] != 'decimalPattern')
                '$key.$name',
    ];
    expect(ungrouped, isEmpty, reason: 'set "format": "decimalPattern"');
  });
}
