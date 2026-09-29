import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/screens/simple_trade_detail_view.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  testWidgets('SimpleTradeDetailView renders YA PAGUÉ for buyer in active state',
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
          home: SimpleTradeDetailView(
            orderId: 'trade-test-1',
            status: OrderStatus.active,
            isBuyer: true,
            fiatAmount: 50.0,
            fiatCode: 'USD',
            amountSats: 125000,
            paymentMethod: 'Bancolombia',
            paymentDetails: 'Cuenta de Ahorros 123-456-789',
          ),
        ),
      ),
    );

    // Header and amount
    expect(find.text('Compra de Bitcoin'), findsOneWidget);
    expect(find.text('50.0 USD'), findsOneWidget);
    expect(find.text('≈ 125000 sats'), findsOneWidget);

    // Primary action
    expect(find.text('YA PAGUÉ'), findsOneWidget);

    // Safety notice
    expect(
        find.text(
            'Verifica cuidadosamente los datos antes de enviar el dinero. Tu Bitcoin estará protegido en custodia.'),
        findsOneWidget);

    // Assistance button
    expect(find.text('PEDIR AYUDA'), findsOneWidget);
  });

  testWidgets(
      'SimpleTradeDetailView renders RECIBÍ EL DINERO for seller in fiatSent state',
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
          home: SimpleTradeDetailView(
            orderId: 'trade-test-2',
            status: OrderStatus.fiatSent,
            isBuyer: false,
            fiatAmount: 100.0,
            fiatCode: 'USD',
            amountSats: 250000,
            paymentMethod: 'Zelle',
          ),
        ),
      ),
    );

    // Header and title
    expect(find.text('Venta de Bitcoin'), findsOneWidget);
    expect(find.text('100.0 USD'), findsOneWidget);

    // Primary action
    expect(find.text('RECIBÍ EL DINERO'), findsOneWidget);

    // Safety notice for seller
    expect(
        find.text(
            'Confirma únicamente después de ver el dinero reflejado en tu propia cuenta bancaria. Esta acción no se puede deshacer.'),
        findsOneWidget);
  });
}
