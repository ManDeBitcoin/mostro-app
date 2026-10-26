import 'package:flutter/painting.dart';

/// Inks of the Mostro QR (`MostroQr`), after the website's
/// (MostroP2P/MostroP2P.github.io#34): near-black modules and finder rings,
/// green finder centres, on white.
///
/// The same in both themes: a scanner needs dark modules on a light ground,
/// so a QR never follows the theme.
/// `test/core/qr_palette_contrast_test.dart` locks how dark each ink is.
abstract final class QrPalette {
  /// The card the code sits on, quiet zone included.
  static const paper = Color(0xFFFFFFFF);

  /// Data modules and the finder rings.
  static const ink = Color(0xFF0E130C);

  /// The centres of the three finder eyes: lime as a dot on a light surface
  /// (DS-COL-5), where the website draws `#4A9A26`.
  static const eye = Color(0xFF5C9130);
}
