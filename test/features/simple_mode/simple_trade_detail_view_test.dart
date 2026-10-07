import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/features/simple_mode/screens/simple_trade_detail_view.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/fake_payment_details.dart';

const _fromSeller =
    'El vendedor te envía sus datos de pago por el chat cifrado. Si aún no han llegado, pídeselos ahí.';
const _sendTitle = 'Envía tus datos de cobro al comprador';

/// The Simple Mode view of a trade, with the device's payment details and
/// the chat's unread count standing in for Rust.
Future<void> _pumpTrade(
  WidgetTester tester, {
  required OrderStatus status,
  required bool isBuyer,
  FakePaymentDetailsGateway? gateway,
  int unread = 0,
  String paymentMethod = 'Banco Pichincha,De Una',
}) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // A scope of its own each time: pumped over the last one, the trade
      // would keep the answers it already read.
      key: UniqueKey(),
      overrides: [
        paymentDetailsGatewayProvider.overrideWithValue(
          gateway ?? FakePaymentDetailsGateway(),
        ),
        unreadFromPeerProvider.overrideWith((ref, orderId) => unread),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SimpleTradeDetailView(
          orderId: 'trade-details',
          status: status,
          isBuyer: isBuyer,
          fiatAmount: 100.0,
          fiatCode: 'USD',
          amountSats: 250000,
          paymentMethod: paymentMethod,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

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
    'SimpleTradeDetailView tells a buyer about to pay where the account comes from',
    (tester) async {
      await _pumpTrade(tester, status: OrderStatus.active, isBuyer: true);

      // The order names the methods, never the account: an order is public.
      expect(find.text(_fromSeller), findsOneWidget);
      expect(find.text('Abrir chat'), findsOneWidget);
      // Nothing unread, nothing said about it.
      expect(find.textContaining('mensaje'), findsNothing);
      // And the buyer is never the one asked for payment details.
      expect(find.text(_sendTitle), findsNothing);

      await _pumpTrade(
        tester,
        status: OrderStatus.active,
        isBuyer: true,
        unread: 2,
      );
      expect(find.text('2 mensajes nuevos'), findsOneWidget);

      await _pumpTrade(
        tester,
        status: OrderStatus.active,
        isBuyer: true,
        unread: 1,
      );
      expect(find.text('1 mensaje nuevo'), findsOneWidget);
    },
  );

  testWidgets(
    'SimpleTradeDetailView asks the seller for the payment details once the escrow is locked',
    (tester) async {
      final gateway = FakePaymentDetailsGateway(
        kept: {'De Una': '099 123 4567'},
      );
      await _pumpTrade(
        tester,
        status: OrderStatus.active,
        isBuyer: false,
        gateway: gateway,
      );

      // A field to each of the order's methods, with what the device keeps.
      expect(find.text(_sendTitle), findsOneWidget);
      expect(find.text('Banco Pichincha'), findsOneWidget);
      expect(find.text('099 123 4567'), findsOneWidget);
      // It is the seller's step, so it comes before the line that waits.
      expect(
        tester.getTopLeft(find.text(_sendTitle)).dy,
        lessThan(
          tester
              .getTopLeft(find.textContaining('Esperando que el comprador'))
              .dy,
        ),
      );

      await tester.tap(find.text('Enviar al comprador'));
      await tester.pump();
      await tester.pump();
      expect(gateway.sent.single.orderId, 'trade-details');
      expect(
        gateway.sent.single.content,
        'Mis datos para recibir el pago:\n\nDe Una\n099 123 4567',
      );
      expect(find.text(_sendTitle), findsNothing);
      expect(
        find.textContaining('Datos de cobro enviados al comprador'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SimpleTradeDetailView never asks for payment details before the escrow is locked',
    (tester) async {
      // The seller's sats are not locked in any of these: nobody is about
      // to pay, and the public book's "taken" is not "locked" either.
      for (final status in [
        OrderStatus.pending,
        OrderStatus.waitingMakerBond,
        OrderStatus.waitingBuyerInvoice,
        OrderStatus.waitingPayment,
        OrderStatus.inProgress,
      ]) {
        final gateway = FakePaymentDetailsGateway(
          kept: {'De Una': '099 123 4567'},
        );
        await _pumpTrade(
          tester,
          status: status,
          isBuyer: false,
          gateway: gateway,
        );
        expect(find.text(_sendTitle), findsNothing, reason: '$status');
        expect(find.text('099 123 4567'), findsNothing, reason: '$status');
        expect(find.text('Enviar al comprador'), findsNothing, reason: '$status');
      }
    },
  );

  testWidgets(
    'SimpleTradeDetailView stops asking once the buyer has paid',
    (tester) async {
      // Never sent from the card: a buyer who marked the payment had an
      // account to pay into, so the seller is not asked now.
      await _pumpTrade(tester, status: OrderStatus.fiatSent, isBuyer: false);
      expect(find.text(_sendTitle), findsNothing);
      expect(find.text('RECIBÍ EL DINERO'), findsOneWidget);

      // Sent from the card: it says so, and can send them again.
      final gateway = FakePaymentDetailsGateway();
      gateway.sentAtByOrder['trade-details'] = DateTime(2026, 10, 7, 14, 32);
      await _pumpTrade(
        tester,
        status: OrderStatus.fiatSent,
        isBuyer: false,
        gateway: gateway,
      );
      expect(
        find.textContaining('Datos de cobro enviados al comprador'),
        findsOneWidget,
      );
      expect(find.text('Enviar de nuevo'), findsOneWidget);
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
