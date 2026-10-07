import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/features/simple_mode/providers/payment_method_providers.dart';
import 'package:mostro/features/simple_mode/screens/simple_sell_screen.dart';
import 'package:mostro/features/simple_mode/widgets/payment_details_editor.dart';
import 'package:mostro/features/simple_mode/widgets/payment_method_field.dart';
import 'package:mostro/features/simple_mode/widgets/simple_price_stepper.dart';
import 'package:mostro/features/simple_mode/widgets/simple_sell_confirm_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;
import 'package:mostro/src/rust/api/types.dart' show NewOrderParams;

import '../../support/fake_payment_details.dart';

CommunityProfile _card(List<String> methods) => CommunityProfile(
  version: 1,
  name: 'BitMaxis',
  pubkey: 'node',
  relays: const [],
  currency: 'USD',
  paymentMethods: methods,
  feeBps: 80,
  bondPercent: 5,
  signature: 'sig-${methods.join('|')}',
);

const _whole =
    'Escribe un importe entero: solo cifras, sin decimales ni separadores.';

void main() {
  testWidgets('SimpleSellScreen renders amount input and steps explanation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SimpleSellScreen(),
          ),
        ),
      ),
    );

    // Initial render
    expect(find.text('¿Cuánto quieres vender?'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('Selecciona cómo quieres recibir el dinero'), findsOneWidget);
    expect(find.text('Tus datos para recibir el pago'), findsOneWidget);
    expect(find.text('Cómo funciona la venta'), findsOneWidget);
    expect(find.text('Publicar oferta'), findsOneWidget);
    // No method stands until the seller ticks one: the field says so, and
    // so does the line beside the button it keeps off.
    expect(find.text('Elige uno o varios'), findsOneWidget);
    expect(find.text('Elige al menos un método de pago'), findsOneWidget);

    // Tap preset chip '250'
    final chip250 = find.text('250 USD');
    if (chip250.evaluate().isNotEmpty) {
      await tester.tap(chip250);
      await tester.pump();
      expect(find.text('250'), findsOneWidget);
    }
  });

  testWidgets('SimpleSellScreen will not publish without a whole amount',
      (tester) async {
    // Tall enough for the publish button to be built: the list is lazy, and
    // the button sits under everything the seller fills in.
    tester.view.physicalSize = const Size(360, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // A method is ticked: the amount is all that is in question here.
          sellTickedMethodsProvider.overrideWith((ref) => {'transferencia'}),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SimpleSellScreen()),
        ),
      ),
    );

    FilledButton publish() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Publicar oferta'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );

    // The default amount is publishable.
    expect(publish().onPressed, isNotNull);

    // An empty field used to publish 100 units.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(publish().onPressed, isNull);
    // Under the field, and again beside the button it disables.
    expect(find.text(_whole), findsNWidgets(2));

    // A typed separator stays on screen. A digits-only field dropped it and
    // kept what followed: 50.9 became a publishable 509.
    for (final typed in ['50.9', '50,9', '10.50']) {
      await tester.enterText(find.byType(TextField).first, typed);
      await tester.pump();
      expect(find.text(typed), findsOneWidget, reason: typed);
      expect(
        find.text(typed.replaceAll(RegExp('[.,]'), '')),
        findsNothing,
        reason: typed,
      );
      expect(publish().onPressed, isNull, reason: typed);
      expect(find.text(_whole), findsNWidgets(2), reason: typed);
    }

    // Anything else never reaches the field, and a whole amount publishes.
    await tester.enterText(find.byType(TextField).first, '-5a 0');
    await tester.pump();
    expect(find.text('50'), findsOneWidget);
    expect(publish().onPressed, isNotNull);
    expect(find.text(_whole), findsNothing);
  });

  testWidgets("SimpleSellScreen offers the community's methods and never chooses one", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The community's card as the core has it stored; it changes below.
    CommunityProfile? stored = _card(['Efectivo', 'Transferencia', 'Deuna']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCommunityProfileProvider.overrideWith(
            (ref) => ActiveCommunityNotifier(read: () async => stored),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SimpleSellScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    FilledButton publish() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Publicar oferta'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    Future<void> cardBecomes(List<String> methods) async {
      stored = _card(methods);
      await tester.pump(ActiveCommunityNotifier.reloadEvery);
      await tester.pump();
    }

    // Nothing is ticked for the seller — the first method used to be — so
    // nothing can be published yet.
    expect(find.text('Elige uno o varios'), findsOneWidget);
    expect(publish().onPressed, isNull);

    // The picker holds the card's list, exactly — none of the built-in
    // ones — under its headings.
    await tester.tap(find.text('Elige uno o varios'));
    await tester.pumpAndSettle();
    for (final listed in ['Efectivo', 'Transferencia', 'Deuna']) {
      expect(find.text(listed), findsOneWidget, reason: listed);
    }
    for (final builtIn in ['Zelle', 'Móvil']) {
      expect(find.text(builtIn), findsNothing, reason: builtIn);
    }
    for (final heading in ['BANCOS', 'BILLETERAS Y APPS', 'EFECTIVO']) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }

    // Two of them ticked, and the picker closed: both are on the screen,
    // and the offer can go out.
    await tester.tap(find.text('Transferencia'));
    await tester.tap(find.text('Deuna'));
    await tester.pump();
    await tester.tap(find.text('Listo · 2 elegidos'));
    await tester.pumpAndSettle();
    expect(find.text('2 elegidos'), findsOneWidget);
    // On its chip. The name is also over its payment-details field, below.
    Finder chip(String method) => find.descendant(
      of: find.byType(PaymentMethodField),
      matching: find.text(method),
    );
    expect(chip('Transferencia'), findsOneWidget);
    expect(chip('Deuna'), findsOneWidget);
    expect(find.text('Efectivo'), findsNothing);
    expect(publish().onPressed, isNotNull);

    // The operator drops both. Nothing stands in for them: nothing is
    // chosen, and nothing can be published, until the seller ticks again.
    await cardBecomes(['efectivo', 'Payphone']);
    expect(find.text('Elige uno o varios'), findsOneWidget);
    expect(find.text('efectivo'), findsNothing);
    expect(publish().onPressed, isNull);

    // One comes back written another way: it is still the seller's choice.
    await cardBecomes(['Payphone', 'TRANSFERENCIA']);
    expect(find.text('1 elegido'), findsOneWidget);
    expect(chip('TRANSFERENCIA'), findsOneWidget);
    expect(find.text('Payphone'), findsNothing);
    expect(publish().onPressed, isNotNull);

    // Its cross unticks it where it stands, without opening the picker.
    await tester.tap(find.bySemanticsLabel('Quitar TRANSFERENCIA'));
    await tester.pump();
    expect(find.text('Elige uno o varios'), findsOneWidget);
    expect(publish().onPressed, isNull);
  });

  testWidgets('SimpleSellScreen publishes every method ticked', (tester) async {
    // Wide: the summary's labels are drawn in the test font, every glyph a
    // square.
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeCommunityProfileProvider.overrideWith(
            (ref) => ActiveCommunityNotifier(
              read: () async =>
                  _card(['Banco Pichincha', 'USDT', 'Deuna', 'Produbanco']),
            ),
          ),
          // Ticked in another order than the list's, and one of them a
          // method the list no longer has.
          sellTickedMethodsProvider.overrideWith(
            (ref) => {'deuna', 'zelle', 'banco pichincha'},
          ),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SimpleSellScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Publicar oferta'));
    await tester.pumpAndSettle();

    // What goes to the summary is what is ticked and on the list, in the
    // order the picker shows it: the bank first, then the wallet.
    final sheet = tester.widget<SimpleSellConfirmSheet>(
      find.byType(SimpleSellConfirmSheet),
    );
    expect(sheet.paymentMethods, ['Banco Pichincha', 'Deuna']);
    // And it is what the summary says, one method to a line.
    expect(find.text('Métodos de pago'), findsOneWidget);
    expect(find.text('Banco Pichincha\nDeuna'), findsOneWidget);
  });

  testWidgets('SimpleSellScreen sells at a discount as it sells at a premium', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    NewOrderParams? published;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sellTickedMethodsProvider.overrideWith((ref) => {'transferencia'}),
          paymentDetailsGatewayProvider.overrideWithValue(
            FakePaymentDetailsGateway(),
          ),
          mostroNodeProvider.overrideWith((ref) async => null),
          createOrderActionProvider.overrideWithValue((params) async {
            published = params;
            throw Exception('Order rejected by Mostro: InvalidFiatCurrency');
          }),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SimpleSellScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // One control on one row where seven chips stood, none of them below
    // the market.
    expect(find.byType(SimplePriceStepper), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(find.text('Mercado'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('simple-price-lower')));
    await tester.tap(find.byKey(const ValueKey('simple-price-lower')));
    await tester.pump();
    expect(find.text('-2%'), findsOneWidget);

    await tester.tap(find.text('Publicar oferta'));
    await tester.pumpAndSettle();
    // The summary signs it as it is: it used to print a plus before any
    // premium.
    expect(
      tester
          .widget<SimpleSellConfirmSheet>(find.byType(SimpleSellConfirmSheet))
          .premium,
      -2,
    );
    expect(
      find.descendant(
        of: find.byType(SimpleSellConfirmSheet),
        matching: find.text('-2%'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('+-'), findsNothing);

    await tester.tap(find.text('CONFIRMAR Y PUBLICAR'));
    await tester.pump();
    await tester.pump();
    expect(published!.premium, -2);
    expect(published!.amountSats, isNull);
  });

  testWidgets("SimpleSellScreen reads a buyer's premium from the seller's side", (
    tester,
  ) async {
    // Wide and tall: the buyers' cards are the end of a lazy list.
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    OrderItem buy(String id, double premium) => OrderItem(
      id: id,
      kind: 'buy',
      fiatAmount: 50,
      fiatCode: 'USD',
      paymentMethod: 'Transferencia',
      premium: premium,
      creatorPubkey: 'peer-$id',
      createdAt: DateTime.utc(2026),
      status: OrderStatus.pending,
      isMine: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderBookProvider.overrideWith(
            (ref) => Stream.value([buy('over', 2), buy('under', -2)]),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SimpleSellScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final pal = OrderBookPalette.of(
      tester.element(find.byType(SimpleSellScreen)),
    );
    Color? color(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    // A buyer who pays over the market is the better offer for whoever
    // sells to them, and one who asks a discount the worse: the card used
    // to colour them as the Buy tab colours a seller's.
    expect(color('+2.0% sobre mercado'), pal.limeText);
    expect(color('-2.0% bajo mercado'), Colors.orangeAccent);
  });

  testWidgets(
    "SimpleSellScreen keeps the seller's payment details on the device and off the order",
    (tester) async {
      // Wide and tall: the test font draws every glyph as a square, and the
      // tab is a lazy list with the publish button at its end.
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final gateway = FakePaymentDetailsGateway(
        kept: {'efectivo': 'En persona, Quito norte'},
      );
      NewOrderParams? published;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeCommunityProfileProvider.overrideWith(
              (ref) => ActiveCommunityNotifier(
                read: () async => _card(['Efectivo', 'Transferencia']),
              ),
            ),
            paymentDetailsGatewayProvider.overrideWithValue(gateway),
            mostroNodeProvider.overrideWith((ref) async => null),
            createOrderActionProvider.overrideWithValue((params) async {
              published = params;
              throw Exception('Order rejected by Mostro: InvalidFiatCurrency');
            }),
          ],
          child: const MaterialApp(
            locale: Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SimpleSellScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      Finder field(String method) => find.byKey(
        ValueKey('payment-details-field-${paymentMethodKey(method)}'),
      );
      final ticks = ProviderScope.containerOf(
        tester.element(find.byType(SimpleSellScreen)),
      ).read(sellTickedMethodsProvider.notifier);
      Future<void> tick(Set<String> methods) async {
        ticks.state = methods;
        // The fields, then what the device keeps for them.
        await tester.pump();
        await tester.pump();
        await tester.pump();
      }

      // Nothing ticked: no account is asked for before the seller has said
      // how they are paid — and what the device keeps is not put on screen.
      expect(
        find.text('Elige primero cómo quieres recibir el dinero.'),
        findsOneWidget,
      );
      expect(find.byType(PaymentDetailsEditor), findsNothing);
      expect(find.textContaining('Quito norte'), findsNothing);

      // A field for the method ticked, opened with what the device keeps
      // for it, and said to stay on the device.
      await tick({'efectivo'});
      expect(
        tester.widget<TextField>(field('Efectivo')).controller!.text,
        'En persona, Quito norte',
      );
      expect(field('Transferencia'), findsNothing);
      expect(
        find.text(
          'Se guardan solo en este dispositivo. No se publican con la oferta: se los envías al comprador por el chat cifrado cuando tu Bitcoin ya esté bloqueado.',
        ),
        findsOneWidget,
      );

      // A second method has its own account, and none kept yet.
      await tick({'efectivo', 'transferencia'});
      expect(
        tester.widget<TextField>(field('Transferencia')).controller!.text,
        isEmpty,
      );
      await tester.enterText(field('Transferencia'), 'Banco X 123 · Ana P.');
      await tester.pump(kPaymentDetailsSaveDelay);
      // Kept for the next sale, each under its method.
      expect(gateway.kept, {
        'efectivo': 'En persona, Quito norte',
        'transferencia': 'Banco X 123 · Ana P.',
      });

      // Unticking a method takes its field away, not what the device keeps.
      await tick({'transferencia'});
      expect(field('Efectivo'), findsNothing);
      expect(gateway.kept['efectivo'], 'En persona, Quito norte');

      await tester.tap(find.text('Publicar oferta'));
      await tester.pumpAndSettle();

      // The sheet shows the details of the method on the order, and only
      // that one's.
      expect(find.text('Datos de cobro · Transferencia'), findsOneWidget);
      expect(find.textContaining('Quito norte'), findsNothing);
      final sheet = tester.widget<SimpleSellConfirmSheet>(
        find.byType(SimpleSellConfirmSheet),
      );
      expect(sheet.paymentDetails, const [
        PaymentDetailsEntry(
          method: 'Transferencia',
          details: 'Banco X 123 · Ana P.',
        ),
      ]);

      await tester.tap(find.text('CONFIRMAR Y PUBLICAR'));
      await tester.pump();
      await tester.pump();

      // What is published names the method. The account is nowhere on it.
      expect(published!.paymentMethod, 'Transferencia');
      expect(published!.paymentMethod, isNot(contains('Banco X')));
      expect(published!.fiatCode, isNot(contains('Banco X')));
      // And nothing was sent to anyone from here.
      expect(gateway.sent, isEmpty);
    },
  );
}
