import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import 'package:mostro/core/qr_palette.dart';

/// The Mostro QR (#851), the website's design
/// (MostroP2P/MostroP2P.github.io#34): round dots, rounded finder eyes with a
/// green centre and, when there is a [logo], a cleared centre that shows it.
/// It sits on a white card in both themes; the card's margin is the quiet
/// zone ([MostroQrLayout.quietZone]).
///
/// The card is a square as wide as the room it is given, up to [maxSide], the
/// way a wallet shows a long invoice or token: a small code is a hard scan.
/// It answers an intrinsic-height pass at that width, so a page laid out
/// with `IntrinsicHeight` can hold it.
class MostroQr extends StatefulWidget {
  const MostroQr({
    super.key,
    required this.data,
    this.logo,
    this.semanticsLabel,
  });

  /// What the code carries. A BOLT 11 invoice is encoded upper-cased
  /// ([MostroQrLayout.of]).
  final String data;

  /// Builds the centre at the side it is given. Without it the centre keeps
  /// its modules and the code its full capacity.
  final Widget Function(double side)? logo;

  final String? semanticsLabel;

  /// The widest the card gets, quiet zone included: about what cashu.me's
  /// takes on a 390 dp phone. A tablet or a desktop window stops there.
  static const double maxSide = 304;

  /// Whether [data] fits a QR at all: without a logo, the most it can carry.
  static bool fits(String data) {
    try {
      MostroQrLayout.of(data, withLogo: false);
      return true;
    } on InputTooLongException {
      return false;
    }
  }

  @override
  State<MostroQr> createState() => _MostroQrState();
}

class _MostroQrState extends State<MostroQr> {
  /// Encoded once per [MostroQr.data]: a screen with a countdown rebuilds
  /// every second.
  late MostroQrLayout _layout = _encode();

  MostroQrLayout _encode() =>
      MostroQrLayout.of(widget.data, withLogo: widget.logo != null);

  @override
  void didUpdateWidget(MostroQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        (oldWidget.logo == null) != (widget.logo == null)) {
      _layout = _encode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final logo = widget.logo;
    return Semantics(
      label: widget.semanticsLabel,
      image: widget.semanticsLabel != null,
      excludeSemantics: true,
      child: ConstrainedBox(
        // The height too: an intrinsic-height pass hands down only the
        // width, and the square must stop at the cap there as well.
        constraints: const BoxConstraints(
          maxWidth: MostroQr.maxSide,
          maxHeight: MostroQr.maxSide,
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: QrPalette.paper,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Its own layer: a ticking countdown around it repaints
                // nothing in here.
                RepaintBoundary(
                  child: CustomPaint(painter: _MostroQrPainter(layout)),
                ),
                if (logo != null && layout.hasLogo)
                  // Positioned: a stack's intrinsic size skips it, and a
                  // LayoutBuilder cannot answer one.
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side =
                            layout.logoSide *
                            constraints.maxWidth /
                            layout.cardModules;
                        return Center(
                          child: SizedBox.square(
                            dimension: side,
                            child: logo(side),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MostroQrPainter extends CustomPainter {
  const _MostroQrPainter(this.layout);

  final MostroQrLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final margin = MostroQrLayout.quietZone.toDouble();
    canvas
      ..scale(size.width / layout.cardModules)
      ..translate(margin, margin);
    canvas.drawPath(layout.dots, Paint()..color = QrPalette.ink);
    canvas.drawPath(layout.eyeRings, Paint()..color = QrPalette.ink);
    canvas.drawPath(layout.eyeCentres, Paint()..color = QrPalette.eye);
  }

  @override
  bool shouldRepaint(_MostroQrPainter oldDelegate) =>
      oldDelegate.layout != layout;
}

/// Where the marks of a Mostro QR go, in modules: [moduleCount] a side, with
/// no quiet zone. A port of the website's `lightningQr.ts`.
class MostroQrLayout {
  MostroQrLayout._(this._image, {required this.clearedModules});

  /// The layout of [data], with a cleared centre when [withLogo].
  ///
  /// With a logo the code is encoded at level Q, which recovers the cleared
  /// centre: a quarter of the side, so a node's picture is big enough to
  /// tell apart, where the website clears 9 modules of a short address. Data
  /// too long for that, or so short that the centre would reach the format
  /// information, is laid out without the logo. Without one the level is L,
  /// which carries the most, as the plain QR did.
  ///
  /// A BOLT 11 invoice is bech32, which BIP-173 lets a QR code carry
  /// upper-cased: in alphanumeric mode a character takes 5.5 bits instead of
  /// 8, and the code stays about as dense at level Q as it was at L.
  ///
  /// Throws [InputTooLongException] when [data] does not fit a QR at all.
  factory MostroQrLayout.of(String data, {required bool withLogo}) {
    if (withLogo) {
      try {
        final image = _encode(data, QrErrorCorrectLevel.Q);
        final cleared = _clearedFor(image.moduleCount);
        // Clear of the finders, their separators and the format information
        // beside them (rows and columns 0–8): only version 1 is too small.
        if ((image.moduleCount - cleared) ~/ 2 > 8) {
          return MostroQrLayout._(image, clearedModules: cleared);
        }
      } on InputTooLongException {
        // Too long to give up its centre: drawn without the logo.
      }
    }
    return MostroQrLayout._(
      _encode(data, QrErrorCorrectLevel.L),
      clearedModules: 0,
    );
  }

  final QrImage _image;

  /// Side of the cleared centre in modules; 0 without a logo.
  final int clearedModules;

  int get moduleCount => _image.moduleCount;

  /// White around the code on each side, in modules: the quiet zone the QR
  /// standard asks for. In modules, not dp, so a card drawn wider keeps it.
  static const quietZone = 4;

  /// Side of the card in modules: the code and its quiet zone.
  int get cardModules => moduleCount + 2 * quietZone;

  /// `QrErrorCorrectLevel.Q` with a logo, `.L` without.
  int get errorCorrectLevel => _image.errorCorrectLevel;

  bool get hasLogo => clearedModules > 0;

  /// Side of the logo in modules: the cleared centre less 0.7 module of
  /// white on each side, as on the website.
  double get logoSide => hasLogo ? clearedModules - 1.4 : 0;

  static const _finder = 7;
  static const _dotRadius = 0.46;

  static final _bolt11 = RegExp(r'^(ln[0-9a-z]+|LN[0-9A-Z]+)$');

  /// The smallest version that holds [data] at [level].
  static QrImage _encode(String data, int level) {
    final upper = _bolt11.hasMatch(data);
    late InputTooLongException tooLong;
    for (var type = 1; type <= 40; type++) {
      final code = QrCode(type, level);
      if (upper) {
        code.addAlphaNumeric(data.toUpperCase());
      } else {
        code.addData(data);
      }
      try {
        return QrImage(code);
      } on InputTooLongException catch (e) {
        tooLong = e;
      }
    }
    throw tooLong;
  }

  /// A quarter of [moduleCount], odd so it centres on a module, and never
  /// under the website's 7.
  static int _clearedFor(int moduleCount) {
    var side = (moduleCount / 4).round();
    if (side.isEven) side -= 1;
    return math.max(side, 7);
  }

  /// Whether the module at column [x], row [y] is drawn as a dot: dark, and
  /// outside the finder eyes and the cleared centre.
  bool isDot(int x, int y) =>
      _image.isDark(y, x) && !_inFinder(x, y) && !inCentre(x, y);

  /// Whether the module at column [x], row [y] is in the cleared centre.
  bool inCentre(int x, int y) {
    if (!hasLogo) return false;
    final start = (moduleCount - clearedModules) ~/ 2;
    final end = start + clearedModules;
    return x >= start && x < end && y >= start && y < end;
  }

  bool _inFinder(int x, int y) {
    final far = moduleCount - _finder;
    return (x < _finder && y < _finder) ||
        (x >= far && y < _finder) ||
        (x < _finder && y >= far);
  }

  /// Top-left corners of the three finder eyes.
  List<Offset> get _eyes => [
    Offset.zero,
    Offset((moduleCount - _finder).toDouble(), 0),
    Offset(0, (moduleCount - _finder).toDouble()),
  ];

  late final Path dots = () {
    final path = Path();
    for (var y = 0; y < moduleCount; y++) {
      for (var x = 0; x < moduleCount; x++) {
        if (!isDot(x, y)) continue;
        path.addOval(
          Rect.fromCircle(center: Offset(x + 0.5, y + 0.5), radius: _dotRadius),
        );
      }
    }
    return path;
  }();

  /// The finder rings: a 7-module rounded square less a 5-module one.
  late final Path eyeRings = () {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final eye in _eyes) {
      path
        ..addRRect(_rounded(eye, 0, 7, 2.2))
        ..addRRect(_rounded(eye, 1, 5, 1.4));
    }
    return path;
  }();

  /// The finder centres, 3 modules a side.
  late final Path eyeCentres = () {
    final path = Path();
    for (final eye in _eyes) {
      path.addRRect(_rounded(eye, 2, 3, 1));
    }
    return path;
  }();

  static RRect _rounded(Offset eye, double inset, double side, double radius) =>
      RRect.fromRectAndRadius(
        Rect.fromLTWH(eye.dx + inset, eye.dy + inset, side, side),
        Radius.circular(radius),
      );
}
