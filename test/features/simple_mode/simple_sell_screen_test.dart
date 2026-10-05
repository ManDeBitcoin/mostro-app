import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/screens/simple_sell_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

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
}
