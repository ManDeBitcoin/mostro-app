import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/screens/simple_trade_detail_view.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  testWidgets(
    'SimpleTradeDetailView renders YA PAGUÉ for buyer in active state',
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
          'Verifica cuidadosamente los datos antes de enviar el dinero. Tu Bitcoin estará protegido en custodia.',
        ),
        findsOneWidget,
      );

      // Assistance button
      expect(find.text('PEDIR AYUDA'), findsOneWidget);
    },
  );

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
          'Confirma únicamente después de ver el dinero reflejado en tu propia cuenta bancaria. Esta acción no se puede deshacer.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SimpleTradeDetailView renders SUBIR FACTURA LIGHTNING for buyer in waitingBuyerInvoice state',
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
              orderId: 'trade-test-3',
              status: OrderStatus.waitingBuyerInvoice,
              isBuyer: true,
              fiatAmount: 50.0,
              fiatCode: 'USD',
              amountSats: 125000,
              paymentMethod: 'Bancolombia',
            ),
          ),
        ),
      );

      expect(find.text('SUBIR FACTURA LIGHTNING'), findsOneWidget);
      expect(find.text('Factura Lightning requerida'), findsOneWidget);
    },
  );

  testWidgets(
    'SimpleTradeDetailView renders PAGAR FACTURA DE CUSTODIA for seller in waitingPayment state',
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
              orderId: 'trade-test-4',
              status: OrderStatus.waitingPayment,
              isBuyer: false,
              fiatAmount: 80.0,
              fiatCode: 'USD',
              amountSats: 200000,
              paymentMethod: 'Transferencia',
            ),
          ),
        ),
      );

      expect(find.text('PAGAR FACTURA DE CUSTODIA'), findsOneWidget);
      expect(find.text('Depósito de custodia requerido'), findsOneWidget);
    },
  );

  testWidgets(
    'SimpleTradeDetailView renders PAGAR FIANZA DE GARANTÍA in waitingMakerBond state',
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
              orderId: 'trade-test-5',
              status: OrderStatus.waitingMakerBond,
              isBuyer: false,
              fiatAmount: 100.0,
              fiatCode: 'USD',
              amountSats: 250000,
              paymentMethod: 'Zelle',
            ),
          ),
        ),
      );

      expect(find.text('PAGAR FIANZA DE GARANTÍA'), findsOneWidget);
      expect(find.text('Depósito de fianza requerido'), findsOneWidget);
    },
  );

  testWidgets(
    'SimpleTradeDetailView does not ask a buyer to pay while only taken',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // `inProgress` is the public book's "taken": it says nothing about the
      // seller having locked the sats, so there is nothing to pay yet.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SimpleTradeDetailView(
              orderId: 'trade-test-6',
              status: OrderStatus.inProgress,
              isBuyer: true,
              fiatAmount: 50.0,
              fiatCode: 'USD',
              amountSats: 125000,
              paymentMethod: 'Bancolombia',
            ),
          ),
        ),
      );

      expect(find.text('YA PAGUÉ'), findsNothing);
      expect(
        find.text('Operación tomada. Esperando el siguiente paso del nodo…'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Todavía no envíes el dinero: el Bitcoin aún no está asegurado.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SimpleTradeDetailView shows the deposit step only for a bonded trade',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<void> pump({required bool hasBond}) => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SimpleTradeDetailView(
              orderId: 'trade-test-7',
              status: OrderStatus.active,
              isBuyer: true,
              fiatAmount: 50.0,
              fiatCode: 'USD',
              amountSats: 125000,
              paymentMethod: 'Bancolombia',
              hasBond: hasBond,
            ),
          ),
        ),
      );

      // No bond on this trade — every trade on a node with bonds off, and
      // the side that locks nothing on a node that bonds only the other.
      await pump(hasBond: false);
      expect(find.text('Garantía temporal bloqueada'), findsNothing);

      await pump(hasBond: true);
      expect(find.text('Garantía temporal bloqueada'), findsOneWidget);
    },
  );

  testWidgets("SimpleTradeDetailView writes an order's methods as a list", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> pump({required bool isBuyer}) => tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SimpleTradeDetailView(
            // A fresh view per side.
            key: ValueKey(isBuyer),
            orderId: 'trade-methods',
            status: OrderStatus.active,
            isBuyer: isBuyer,
            fiatAmount: 50.0,
            fiatCode: 'USD',
            amountSats: 125000,
            // As the user's own order carries them: nothing after the comma.
            paymentMethod: 'Banco Pichincha,Deuna, USDT',
          ),
        ),
      ),
    );

    // The buyer, told how to pay.
    await pump(isBuyer: true);
    expect(find.text('Método: Banco Pichincha, Deuna, USDT'), findsOneWidget);
    expect(find.textContaining('Pichincha,Deuna'), findsNothing);

    // The seller, told what they are waiting for.
    await pump(isBuyer: false);
    expect(
      find.textContaining('Banco Pichincha, Deuna, USDT'),
      findsOneWidget,
    );
    expect(find.textContaining('Pichincha,Deuna'), findsNothing);
  });
}
