import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/widgets/mostro_qr.dart';
import 'package:qr/qr.dart';
import 'package:zxing2/qrcode.dart';

/// A BOLT 11 invoice of [length] characters: the bech32 alphabet after a
/// mainnet prefix, from a fixed seed so every run draws the same code.
String _invoice(int length, {int seed = 1}) {
  const alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final random = Random(seed);
  const prefix = 'lnbc2520n1p';
  return prefix +
      String.fromCharCodes([
        for (var i = prefix.length; i < length; i++)
          alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ]);
}

/// A Cashu token: base64url, so mixed case and never upper-cased.
String _token(int length) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final random = Random(7);
  final body = String.fromCharCodes([
    for (var i = 6; i < length; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
  return 'cashuB$body';
}

int _byteModules(String data, int level) =>
    QrImage(QrCode.fromData(data: data, errorCorrectLevel: level)).moduleCount;

/// The worst centre a node can have: a black disc over the whole logo box.
Widget _blackDisc(double side) => const DecoratedBox(
  decoration: BoxDecoration(color: Colors.black, shape: BoxShape.circle),
);

typedef _Image = ({int width, int height, Int32List pixels});

/// Renders [qr] at [pixelRatio], as 0xRRGGBB pixels.
Future<_Image> _render(
  WidgetTester tester,
  Widget qr,
  double pixelRatio,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: RepaintBoundary(key: key, child: qr)),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = Int32List(image.width * image.height);
    for (var i = 0; i < pixels.length; i++) {
      final a = rgba.getUint8(i * 4 + 3);
      // Over white: the card's rounded corners are transparent.
      int over(int c) => (c * a + 255 * (255 - a)) ~/ 255;
      pixels[i] =
          over(rgba.getUint8(i * 4)) << 16 |
          over(rgba.getUint8(i * 4 + 1)) << 8 |
          over(rgba.getUint8(i * 4 + 2));
    }
    return (width: image.width, height: image.height, pixels: pixels);
  });
  return image!;
}

/// Renders [qr] at [pixelRatio] and decodes it as a phone's scanner would.
Future<String> _scan(WidgetTester tester, Widget qr, double pixelRatio) async {
  final image = await _render(tester, qr, pixelRatio);
  final source = RGBLuminanceSource(image.width, image.height, image.pixels);
  return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
}

/// Whether a 0xRRGGBB pixel reads dark to a scanner.
bool _isInk(int rgb) {
  final r = rgb >> 16 & 0xFF, g = rgb >> 8 & 0xFF, b = rgb & 0xFF;
  return 0.299 * r + 0.587 * g + 0.114 * b < 128;
}

void main() {
  group('layout', () {
    test(
      'an invoice is upper-cased: at level Q it stays near its old size',
      () {
        final invoice = _invoice(400);
        final layout = MostroQrLayout.of(invoice, withLogo: true);
        expect(layout.errorCorrectLevel, QrErrorCorrectLevel.Q);
        // The plain QR was byte mode at level L; byte mode at level H, the
        // website's, would be far denser.
        expect(
          layout.moduleCount,
          lessThanOrEqualTo(_byteModules(invoice, QrErrorCorrectLevel.L) + 8),
        );
        expect(
          layout.moduleCount,
          lessThan(_byteModules(invoice, QrErrorCorrectLevel.H)),
        );
      },
    );

    test('the cleared centre is a quarter of the side, odd, and dotless', () {
      final layout = MostroQrLayout.of(_invoice(400), withLogo: true);
      final n = layout.moduleCount;
      expect(layout.clearedModules.isOdd, isTrue);
      expect(layout.clearedModules, closeTo(n / 4, 1));
      final start = (n - layout.clearedModules) ~/ 2;
      // Centred: as many modules before it as after it.
      expect(n - start - layout.clearedModules, start);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          if (layout.inCentre(x, y)) expect(layout.isDot(x, y), isFalse);
        }
      }
      expect(layout.logoSide, layout.clearedModules - 1.4);
    });

    test('the finder eyes are drawn as eyes, never as dots', () {
      final layout = MostroQrLayout.of(_invoice(300), withLogo: true);
      final far = layout.moduleCount - 7;
      for (final (x0, y0) in [(0, 0), (far, 0), (0, far)]) {
        for (var y = y0; y < y0 + 7; y++) {
          for (var x = x0; x < x0 + 7; x++) {
            expect(layout.isDot(x, y), isFalse, reason: '($x, $y)');
          }
        }
      }
    });

    test('without a logo: level L and nothing cleared', () {
      final token = _token(600);
      final layout = MostroQrLayout.of(token, withLogo: false);
      expect(layout.errorCorrectLevel, QrErrorCorrectLevel.L);
      expect(layout.hasLogo, isFalse);
      expect(layout.logoSide, 0);
      // Mixed case is never upper-cased: the same code as the plain QR's.
      expect(layout.moduleCount, _byteModules(token, QrErrorCorrectLevel.L));
    });

    test('only an all-lower or all-upper invoice is upper-cased', () {
      // Mixed case is not bech32: upper-casing it would change what it says.
      const mixed =
          'lnurl1Dp68gurn8ghj7mrww4exctnxd9shg6npvchxxmmd9akxuatjd3cz7';
      final layout = MostroQrLayout.of(mixed, withLogo: true);
      expect(layout.moduleCount, _byteModules(mixed, QrErrorCorrectLevel.Q));
    });

    test('a code too small to clear its centre keeps it', () {
      // Version 1: a 7-module centre would start beside the format
      // information.
      final layout = MostroQrLayout.of('lnbc1', withLogo: true);
      expect(layout.moduleCount, 21);
      expect(layout.hasLogo, isFalse);
    });

    test('data too long to give up its centre is laid out without a logo', () {
      // Fits level L in byte mode (2 953 bytes), not level Q (1 663).
      final layout = MostroQrLayout.of('x' * 2000, withLogo: true);
      expect(layout.hasLogo, isFalse);
      expect(layout.errorCorrectLevel, QrErrorCorrectLevel.L);
    });

    test('fits: what a QR can carry, and no more', () {
      expect(MostroQr.fits('x' * 2000), isTrue);
      expect(MostroQr.fits('x' * 3000), isFalse);
    });
  });

  group('scans', () {
    // The narrowest the app draws a QR: the token dialog on a 320 dp phone,
    // where the invoice cards are 250 dp. Phone screens are 2x to 3x.
    Widget narrowest(MostroQr qr) => SizedBox(width: 232, child: qr);

    for (final pixelRatio in [2.0, 3.0]) {
      for (final length in [300, 450, 650]) {
        testWidgets('a $length-character hold invoice with a logo, '
            '${pixelRatio}x', (tester) async {
          final invoice = _invoice(length, seed: length);
          final text = await _scan(
            tester,
            narrowest(MostroQr(data: invoice, logo: _blackDisc)),
            pixelRatio,
          );
          expect(text, invoice.toUpperCase());
        });
      }

      testWidgets('a bond invoice with a logo, ${pixelRatio}x', (tester) async {
        final invoice = _invoice(320, seed: 3);
        final text = await _scan(
          tester,
          narrowest(MostroQr(data: invoice, logo: _blackDisc)),
          pixelRatio,
        );
        expect(text, invoice.toUpperCase());
      });

      testWidgets('a Cashu token without a logo, ${pixelRatio}x', (
        tester,
      ) async {
        final token = _token(600);
        final text = await _scan(
          tester,
          narrowest(MostroQr(data: token)),
          pixelRatio,
        );
        expect(text, token);
      });
    }
  });

  group('quiet zone', () {
    // The QR standard asks for four modules of white around the code, and
    // the card stands on a dark page: its own white is all a camera gets.
    // Measured in modules, so it holds at any width the card is drawn.
    for (final length in [218, 400]) {
      for (final width in [232.0, MostroQr.maxSide]) {
        testWidgets('a $length-character invoice keeps four modules, '
            '${width.round()} dp wide', (tester) async {
          final invoice = _invoice(length, seed: length);
          final image = await _render(
            tester,
            SizedBox(
              width: width,
              child: MostroQr(data: invoice, logo: _blackDisc),
            ),
            2,
          );
          // The ink spans the code: the finder eyes reach both its edges.
          var left = image.width, right = -1, top = image.height;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (!_isInk(image.pixels[y * image.width + x])) continue;
              left = min(left, x);
              right = max(right, x);
              top = min(top, y);
            }
          }
          final modules = MostroQrLayout.of(invoice, withLogo: true);
          final module = (right - left + 1) / modules.moduleCount;
          // A pixel of antialiasing aside.
          expect(left / module, greaterThan(3.8));
          expect((image.width - 1 - right) / module, greaterThan(3.8));
          expect(top / module, greaterThan(3.8));
        });
      }
    }
  });

  group('widget', () {
    testWidgets('the logo gets the side the layout leaves it', (tester) async {
      final invoice = _invoice(400);
      double? side;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 260,
              child: MostroQr(
                data: invoice,
                logo: (s) {
                  side = s;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      final layout = MostroQrLayout.of(invoice, withLogo: true);
      expect(side, closeTo(layout.logoSide * 260 / layout.cardModules, 1e-9));
      // Big enough to tell a node's picture apart.
      expect(side, greaterThan(48));
      expect(tester.getSize(find.byType(MostroQr)), const Size.square(260));
    });

    // A long invoice or token reads best as wide as the screen allows, but
    // a tablet or a desktop window would draw a poster.
    testWidgets('takes the width it is given, up to its cap', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: MostroQr(data: _token(600))),
        ),
      );
      expect(
        tester.getSize(find.byType(MostroQr)),
        const Size.square(MostroQr.maxSide),
      );
    });

    // Both invoice screens lay their page out with IntrinsicHeight.
    for (final (width, side) in [(260.0, 260.0), (500.0, MostroQr.maxSide)]) {
      testWidgets('an intrinsic-height page holds it, ${width.round()} dp '
          'wide', (tester) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: MostroQr(data: _invoice(400), logo: _blackDisc),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(MostroQr)), Size.square(side));
        // The pass measured the square it then laid out: no gap below.
        expect(tester.getSize(find.byType(Column)).height, side);
      });
    }

    testWidgets('reads as an image with its label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: MostroQr(
              data: _invoice(300),
              logo: (_) => const Text('M'),
              semanticsLabel: 'Invoice QR',
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Invoice QR'), findsOneWidget);
      // The centre is part of the picture, not a text of its own.
      expect(find.bySemanticsLabel('M'), findsNothing);
      handle.dispose();
    });
  });
}
