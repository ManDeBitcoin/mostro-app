import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/features/simple_mode/screens/simple_sell_screen.dart';
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
      const ProviderScope(
        child: MaterialApp(
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

  testWidgets("SimpleSellScreen offers the community's methods and never swaps a chosen one", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The community's card as the core has it stored; it changes below.
    CommunityProfile? stored = _card(['Efectivo', 'Transferencia']);

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

    bool selected(String method) => tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, method))
        .selected;
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

    // The card's list, exactly — none of the built-in ones — and the first
    // stands until the user picks.
    expect(find.widgetWithText(ChoiceChip, 'Efectivo'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Transferencia'), findsOneWidget);
    for (final builtIn in ['Zelle', 'Móvil']) {
      expect(find.widgetWithText(ChoiceChip, builtIn), findsNothing);
    }
    expect(selected('Efectivo'), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transferencia'));
    await tester.pump();
    expect(selected('Transferencia'), isTrue);
    expect(publish().onPressed, isNotNull);

    // The operator drops that method. The pick is not swapped for another:
    // nothing is selected, and nothing can be published, until they choose.
    await cardBecomes(['efectivo', 'DeUna']);
    expect(selected('efectivo'), isFalse);
    expect(selected('DeUna'), isFalse);
    expect(publish().onPressed, isNull);

    // It comes back written another way: it is still the user's choice.
    await cardBecomes(['DeUna', 'TRANSFERENCIA']);
    expect(selected('TRANSFERENCIA'), isTrue);
    expect(selected('DeUna'), isFalse);
    expect(publish().onPressed, isNotNull);
  });
}
