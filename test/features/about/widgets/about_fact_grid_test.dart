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

/// The same card in English, at the widest figures a node sends.
const _wideEnglish = [
  AboutFact('Min order', '1,000,000', unit: 'sats'),
  AboutFact('Max order', '10,000,000', unit: 'sats'),
  AboutFact('Fee', '0.6%'),
  AboutFact('Deposit', '1.5%'),
  AboutFact('Currencies', 'ARS, EUR +5'),
  AboutFact('Expiration', '24 h'),
];

/// The German card while the node has not answered.
final _loading = [for (final fact in _facts) AboutFact(fact.label, '—')];

/// Pumps the grid as 12a lays it out on a [screenWidth] phone: inside the
/// page's viewport and SafeArea, in a card with the node card's inset.
Future<void> _pump(
  WidgetTester tester, {
  required double screenWidth,
  List<AboutFact> facts = _facts,
  double textScale = 1,
  bool boldText = false,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = Size(screenWidth, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 1600),
          padding: padding,
          textScaler: TextScaler.linear(textScale),
          boldText: boldText,
        ),
        child: Scaffold(
          body: SafeArea(
            child: AboutFillViewport(
              children: [
                AboutCard(
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: AboutFactGrid(facts: facts, inset: 1 + 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// How many cells share the first row.
int _firstRowCount(WidgetTester tester, List<AboutFact> facts) {
  final top = tester.getTopLeft(find.text(facts.first.label)).dy;
  return facts
      .where((fact) => tester.getTopLeft(find.text(fact.label)).dy == top)
      .length;
}

/// Lines [value]'s paragraph takes.
int _lines(WidgetTester tester, String value) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(value).first,
  );
  final line = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
  return (paragraph.size.height / line).round();
}

/// The facts whose value or label does not read whole: a one-word value on
/// more than one line, or a label cut by its ellipsis.
List<String> _broken(WidgetTester tester, List<AboutFact> facts) => [
  for (final fact in facts)
    if (!fact.value.contains(' ') && _lines(tester, fact.value) > 1) fact.value,
  for (final fact in facts)
    if (tester
        .renderObject<RenderParagraph>(find.text(fact.label))
        .didExceedMaxLines)
      fact.label,
];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('three to a row on a common phone', (tester) async {
    await _pump(tester, screenWidth: 393);

    expect(_firstRowCount(tester, _facts), 3);
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

    expect(_firstRowCount(tester, _facts), 2);
    expect(_lines(tester, '10.000.000'), 1);
  });

  testWidgets('one per line at 2x on a 320 dp phone, nothing split', (
    tester,
  ) async {
    await _pump(tester, screenWidth: 320, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(_firstRowCount(tester, _facts), 1);
    for (final fact in _facts) {
      expect(_lines(tester, fact.value), 1, reason: fact.value);
    }
  });

  testWidgets('no figure splits and no label is cut, at any phone width', (
    tester,
  ) async {
    for (final scale in const [1.0, 1.15, 1.3]) {
      for (var width = 320.0; width <= 430; width++) {
        for (final facts in [_facts, _wideEnglish]) {
          await _pump(
            tester,
            screenWidth: width,
            textScale: scale,
            facts: facts,
          );
          expect(
            _broken(tester, facts),
            isEmpty,
            reason: '$width dp at ${scale}x',
          );
        }
      }
    }
  });

  testWidgets('bold text is measured bold', (tester) async {
    await _pump(tester, screenWidth: 360, facts: _wideEnglish, boldText: true);

    expect(_broken(tester, _wideEnglish), isEmpty);
  });

  testWidgets('the system insets narrow the grid', (tester) async {
    // Landscape split screen next to a 48 dp side navigation bar.
    await _pump(
      tester,
      screenWidth: 400,
      facts: _wideEnglish,
      padding: const EdgeInsets.only(right: 48),
    );

    expect(_broken(tester, _wideEnglish), isEmpty);
  });

  testWidgets('the labels read whole while the node loads', (tester) async {
    for (final width in const [320.0, 360.0, 393.0]) {
      await _pump(tester, screenWidth: width, facts: _loading);

      expect(_broken(tester, _loading), isEmpty, reason: '$width dp');
    }
  });
}
