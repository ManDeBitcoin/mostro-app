import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/simple_mode/screens/simple_buy_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

OrderItem _sell({
  required String id,
  double? fiat,
  double? min,
  double? max,
  OrderStatus status = OrderStatus.pending,
  bool isMine = false,
}) => OrderItem(
  id: id,
  kind: 'sell',
  fiatAmount: fiat,
  fiatAmountMin: min,
  fiatAmountMax: max,
  fiatCode: 'USD',
  paymentMethod: 'Transferencia',
  premium: 0,
  creatorPubkey: 'node',
  createdAt: DateTime.utc(2026),
  status: status,
  isMine: isMine,
);

Future<void> _pumpBuy(WidgetTester tester, List<OrderItem> book) async {
  // Wide enough that the test font (every glyph a square) does not overflow
  // the offer card's rows.
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [orderBookProvider.overrideWith((ref) => Stream.value(book))],
      child: const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SimpleBuyScreen()),
      ),
    ),
  );
  // The book is a stream: one frame to subscribe, one to deliver.
  await tester.pump();
  await tester.pump();
}

FilledButton _buyButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<FilledButton>(),
      ),
    );

void main() {
  testWidgets('SimpleBuyScreen renders amount input and preset chips',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

  testWidgets('SimpleBuyScreen offers only untaken orders of other users',
      (tester) async {
    await _pumpBuy(tester, [
      _sell(id: 'free', fiat: 50),
      // Someone's trade in progress, and the user's own order: both sit in
      // the book, neither is an offer.
      _sell(id: 'taken', fiat: 50, status: OrderStatus.inProgress),
      _sell(id: 'mine', fiat: 50, isMine: true),
    ]);

    expect(find.text('COMPRAR 50 USD'), findsOneWidget);
  });

  testWidgets('SimpleBuyScreen takes a range order only for a valid amount',
      (tester) async {
    await _pumpBuy(tester, [_sell(id: 'range', min: 100, max: 200)]);

    // With nothing typed there is no amount to take a range order for: the
    // offer is listed, its button is dead and it says what is missing.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(_buyButton(tester, 'COMPRAR').onPressed, isNull);
    expect(
      find.text('Escribe arriba un importe entero entre 100 y 200 USD'),
      findsOneWidget,
    );

    // Decimals stay on screen and are no amount: a field that dropped the
    // separator would read 1505 here — or 150 for a typed `15.0`, which is
    // inside the range and would have been offered.
    for (final typed in ['150.5', '15.0', '150,']) {
      await tester.enterText(find.byType(TextField).first, typed);
      await tester.pump();
      expect(find.text(typed), findsOneWidget, reason: typed);
      expect(_buyButton(tester, 'COMPRAR').onPressed, isNull, reason: typed);
      expect(
        find.text(
          'Escribe un importe entero: solo cifras, sin decimales ni separadores.',
        ),
        findsOneWidget,
        reason: typed,
      );
    }

    // Nothing but digits and the two separators reaches the field.
    await tester.enterText(find.byType(TextField).first, '+1a5 0');
    await tester.pump();
    expect(find.text('150'), findsOneWidget);
    expect(_buyButton(tester, 'COMPRAR 150 USD').onPressed, isNotNull);

    await tester.enterText(find.byType(TextField).first, '150');
    await tester.pump();
    expect(_buyButton(tester, 'COMPRAR 150 USD').onPressed, isNotNull);
    expect(find.text('Comprarás: 150 USD'), findsOneWidget);
  });
}
