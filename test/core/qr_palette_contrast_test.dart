import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/qr_palette.dart';

import 'order_book_palette_contrast_test.dart' show contrastRatio;

/// The luminance a scanner thresholds: zxing's green-weighted average of the
/// channels, 0–255.
int _scannerLuminance(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return (r + 2 * g + b) ~/ 4;
}

/// A scanner splits light from dark: every ink of the Mostro QR has to read
/// dark on its paper, the green finder centres included.
void main() {
  for (final (label, ink) in [
    ('modules', QrPalette.ink),
    ('finder centres', QrPalette.eye),
  ]) {
    test('$label read dark on the paper', () {
      expect(_scannerLuminance(ink), lessThan(128), reason: label);
      expect(_scannerLuminance(QrPalette.paper), greaterThan(200));
      expect(
        contrastRatio(ink, QrPalette.paper),
        greaterThanOrEqualTo(3),
        reason: label,
      );
    });
  }
}
