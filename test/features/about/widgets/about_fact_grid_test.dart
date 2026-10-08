import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/widgets/about_widgets.dart';

import '../../../support/load_app_fonts.dart';

/// The six facts of 12a's node card, as a German node with a wide range
/// shows them.
const _facts = [
  AboutFact('Mindestbetrag', '100.000', unit: 'sats'),
  AboutFact('Höchstbetrag', '10.000.000', unit: 'sats'),
  AboutFact('Gebühr', '0,6 %'),
  AboutFact('Einlage', '5 %'),
  AboutFact('Währungen', 'ARS, EUR, USD'),
  AboutFact('Ablauf', '24 h'),
];

/// Pumps the grid as 12a lays it out on a [screenWidth] phone: the screen
/// less the page's side padding, the card's border and its inset.
Future<void> _pump(
  WidgetTester tester, {
  required double screenWidth,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(screenWidth, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final width = screenWidth - 2 * (aboutSidePadding + 1 + 14);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 1600),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: AboutFactGrid(facts: _facts, width: width),
            ),
          ),
        ),
      ),
    ),
  );
}

/// How many cells share the first row.
int _firstRowCount(WidgetTester tester) {
  final top = tester.getTopLeft(find.text(_facts.first.label)).dy;
  return _facts
      .where((fact) => tester.getTopLeft(find.text(fact.label)).dy == top)
      .length;
}

/// Lines [value]'s paragraph takes.
int _lines(WidgetTester tester, String value) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(value));
  final line = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
  return (paragraph.size.height / line).round();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('three to a row on a common phone', (tester) async {
    await _pump(tester, screenWidth: 393);

    expect(_firstRowCount(tester), 3);
    expect(_lines(tester, '10.000.000'), 1);
  });

  testWidgets('a list wraps between its codes, at full size', (tester) async {
    await _pump(tester, screenWidth: 393);

    expect(_lines(tester, 'ARS, EUR, USD'), 2);
    expect(find.byType(FittedBox), findsNothing);
  });

  testWidgets('two to a row when a figure would split in three', (
    tester,
  ) async {
    await _pump(tester, screenWidth: 320);

    expect(_firstRowCount(tester), 2);
    expect(_lines(tester, '10.000.000'), 1);
  });

  testWidgets('one per line at 2x on a 320 dp phone, nothing split', (
    tester,
  ) async {
    await _pump(tester, screenWidth: 320, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(_firstRowCount(tester), 1);
    for (final fact in _facts) {
      expect(_lines(tester, fact.value), 1, reason: fact.value);
    }
  });
}
