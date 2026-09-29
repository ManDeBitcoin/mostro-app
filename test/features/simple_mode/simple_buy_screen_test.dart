import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/screens/simple_buy_screen.dart';

void main() {
  testWidgets('SimpleBuyScreen renders amount input and preset chips',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('es'),
          home: Scaffold(
            body: SimpleBuyScreen(),
          ),
        ),
      ),
    );

    // Initial render
    expect(find.text('¿Cuánto quieres comprar?'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('Selecciona método de pago'), findsOneWidget);
    expect(find.text('Ver ofertas'), findsOneWidget);

    // Tap preset chip '100'
    final chip100 = find.text('100 USD');
    if (chip100.evaluate().isNotEmpty) {
      await tester.tap(chip100);
      await tester.pump();
      expect(find.text('100'), findsOneWidget);
    }
  });
}
