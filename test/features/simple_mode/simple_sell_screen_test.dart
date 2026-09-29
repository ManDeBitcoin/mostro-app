import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/screens/simple_sell_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

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
}
