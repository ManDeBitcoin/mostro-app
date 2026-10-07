import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/features/simple_mode/providers/payment_method_providers.dart';
import 'package:mostro/features/simple_mode/screens/simple_sell_screen.dart';
import 'package:mostro/features/simple_mode/widgets/simple_sell_confirm_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;

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
    tester.view.physicalSize = const Size(360, 1600);
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
    tester.view.physicalSize = const Size(360, 1600);
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
    expect(find.text('Transferencia'), findsOneWidget);
    expect(find.text('Deuna'), findsOneWidget);
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
    expect(find.text('TRANSFERENCIA'), findsOneWidget);
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
}
