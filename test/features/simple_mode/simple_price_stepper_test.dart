import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/widgets/simple_price_stepper.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/load_app_fonts.dart';

const _lower = ValueKey('simple-price-lower');
const _raise = ValueKey('simple-price-raise');
const _figure = ValueKey('simple-price-figure');
const _meaning = ValueKey('simple-price-meaning');

/// The stepper over a premium it changes itself, as a screen holds it.
Future<void> _pump(
  WidgetTester tester, {
  required PriceSide side,
  int premium = 0,
  double? rate = 60000,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  var value = premium;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SimplePriceStepper(
            premium: value,
            onStep: (step) =>
                setState(() => value = steppedPremium(value, step)),
            side: side,
            rate: rate,
            currency: 'USD',
          ),
        ),
      ),
    ),
  );
}

/// A line of the control as it reads: the price of a coin is held together
/// with no-break spaces, which a reader does not tell from spaces.
String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!.replaceAll('\u00A0', ' ');

IconButton _button(WidgetTester tester, Key key) => tester.widget<IconButton>(
  find.descendant(of: find.byKey(key), matching: find.byType(IconButton)),
);

void main() {
  // Outside a test body: reading the font files is real I/O, which the fake
  // clock of a widget test never lets finish.
  setUpAll(loadAppFonts);

  testWidgets('starts at the market and says so in words', (tester) async {
    await _pump(tester, side: PriceSide.seller);

    expect(find.text('Precio'), findsOneWidget);
    expect(_text(tester, _figure), 'Mercado');
    // At the market there is no second price to give: the tab already
    // shows the reference one.
    expect(_text(tester, _meaning), 'Vendes al precio de mercado.');
  });

  testWidgets('a seller can ask for more, or sell at a discount', (
    tester,
  ) async {
    await _pump(tester, side: PriceSide.seller);

    await tester.tap(find.byKey(_raise));
    await tester.tap(find.byKey(_raise));
    await tester.pump();
    expect(_text(tester, _figure), '+2%');
    expect(
      _text(tester, _meaning),
      // 60 000 with 2 % off the sats. Said in sats, which is exact: the
      // coin is 2.04 % dearer, not 2 %.
      'Con prima: entregas un 2 % menos de sats. 1 BTC ≈ 61.224,49 USD',
    );

    // Back through the market and below it: the chips this replaced
    // stopped at zero.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(_lower));
    }
    await tester.pump();
    expect(_text(tester, _figure), '-3%');
    expect(
      _text(tester, _meaning),
      'Con descuento: entregas un 3 % más de sats. 1 BTC ≈ 58.252,43 USD',
    );
  });

  testWidgets('says the same figure from the buyer\'s side', (tester) async {
    await _pump(tester, side: PriceSide.buyer);
    expect(_text(tester, _meaning), 'Compras al precio de mercado.');

    await tester.tap(find.byKey(_raise));
    await tester.pump();
    expect(_text(tester, _figure), '+1%');
    expect(
      _text(tester, _meaning),
      startsWith('Con prima: recibes un 1 % menos de sats.'),
    );

    await tester.tap(find.byKey(_lower));
    await tester.tap(find.byKey(_lower));
    await tester.pump();
    expect(_text(tester, _figure), '-1%');
    expect(
      _text(tester, _meaning),
      startsWith('Con descuento: recibes un 1 % más de sats.'),
    );
  });

  testWidgets('colours the figure by whom it favours', (tester) async {
    Color figureColor() =>
        tester.widget<Text>(find.byKey(_figure)).style!.color!;

    // A premium is the seller's gain and a discount their cost: the one
    // set by a slip of the finger must not look like the default.
    await _pump(tester, side: PriceSide.seller, premium: 1);
    final gain = figureColor();
    await tester.tap(find.byKey(_lower));
    await tester.tap(find.byKey(_lower));
    await tester.pump();
    expect(figureColor(), Colors.amber);
    expect(gain, isNot(Colors.amber));

    // For a buyer it is the other way round.
    await _pump(tester, side: PriceSide.buyer, premium: 1);
    expect(figureColor(), Colors.amber);
    await tester.tap(find.byKey(_lower));
    await tester.tap(find.byKey(_lower));
    await tester.pump();
    expect(figureColor(), gain);
  });

  testWidgets('draws its two signs itself, without the icon font', (
    tester,
  ) async {
    await _pump(tester, side: PriceSide.seller);

    // On the web the icon font is cut down to what a build uses, and a
    // browser can still hold the one from before a deploy: the minus sign
    // was new with this control and came out blank there. A sign that
    // changes a price is drawn, one bar or two.
    for (final key in [_lower, _raise]) {
      expect(
        find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
        findsNothing,
      );
    }
    Iterable<Size> bars(Key key) => tester
        .widgetList<Container>(
          find.descendant(of: find.byKey(key), matching: find.byType(Container)),
        )
        .map((bar) => tester.getSize(find.byWidget(bar)));
    final minus = bars(_lower).toList();
    final plus = bars(_raise).toList();
    // A minus is one bar lying down; a plus is that bar and one upright.
    expect(minus, hasLength(1));
    expect(minus.single.width, greaterThan(minus.single.height));
    expect(plus, hasLength(2));
    expect(plus.where((bar) => bar.height > bar.width), hasLength(1));
    // Painted in the button's colour, so it is there to be seen.
    for (final key in [_lower, _raise]) {
      for (final bar in tester.widgetList<Container>(
        find.descendant(of: find.byKey(key), matching: find.byType(Container)),
      )) {
        final color = (bar.decoration! as BoxDecoration).color;
        expect(color, isNotNull);
        expect(color!.a, greaterThan(0));
      }
    }
  });

  testWidgets('stops at the limit, and turns that button off', (tester) async {
    await _pump(
      tester,
      side: PriceSide.seller,
      premium: simplePremiumLimit - 1,
    );
    expect(_button(tester, _raise).onPressed, isNotNull);

    await tester.tap(find.byKey(_raise));
    await tester.pump();
    expect(_text(tester, _figure), '+$simplePremiumLimit%');
    expect(_button(tester, _raise).onPressed, isNull);
    expect(_button(tester, _lower).onPressed, isNotNull);

    await _pump(
      tester,
      side: PriceSide.seller,
      premium: -simplePremiumLimit,
    );
    expect(_text(tester, _figure), '-$simplePremiumLimit%');
    expect(_button(tester, _lower).onPressed, isNull);
    expect(_button(tester, _raise).onPressed, isNotNull);
  });

  testWidgets('gives no price of a coin while the rate is unknown', (
    tester,
  ) async {
    await _pump(tester, side: PriceSide.seller, premium: 4, rate: null);

    expect(_text(tester, _figure), '+4%');
    expect(
      _text(tester, _meaning),
      'Con prima: entregas un 4 % menos de sats.',
    );
  });

  testWidgets('fits the narrowest phone, in every language', (tester) async {
    // Measured with the app's own fonts and theme (`setUpAll`): in the test
    // font every glyph is a square and nothing here would fit.
    for (final locale in AppLocalizations.supportedLocales) {
      // The widest figure and the widest word the control shows.
      for (final premium in [-simplePremiumLimit, 0]) {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('$locale $premium'),
            theme: buildDarkTheme(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Padding(
                // The tabs' own margins.
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SimplePriceStepper(
                  premium: premium,
                  onStep: (_) {},
                  side: PriceSide.seller,
                  rate: 60000,
                  currency: 'USD',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final reason = '$locale at $premium';
        expect(tester.takeException(), isNull, reason: reason);
        // The figure is whole — it is cut with an ellipsis when it is not —
        // and the label beside it takes one line.
        expect(
          tester
              .renderObject<RenderParagraph>(find.byKey(_figure))
              .didExceedMaxLines,
          isFalse,
          reason: reason,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SimplePriceStepper)),
        );
        expect(
          tester.getSize(find.text(l10n.simplePriceLabel)).height,
          lessThan(30),
          reason: reason,
        );
      }
    }
  });
}
