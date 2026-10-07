import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/features/simple_mode/widgets/payment_details_send_card.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/fake_payment_details.dart';

const _orderId = 'order-1';
const _title = 'Envía tus datos de cobro al comprador';
const _send = 'Enviar al comprador';
const _sendAgain = 'Enviar de nuevo';
const _sentLine = 'Datos de cobro enviados al comprador · ';

Finder _field(String method) =>
    find.byKey(ValueKey('payment-details-field-${paymentMethodKey(method)}'));

Finder _tick(String method) =>
    find.byKey(ValueKey('payment-details-tick-${paymentMethodKey(method)}'));

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<FilledButton>(),
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  FakePaymentDetailsGateway gateway, {
  required bool offerToSend,
  String paymentMethod = 'Banco Pichincha,De Una',
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [paymentDetailsGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaymentDetailsSendCard(
              orderId: _orderId,
              paymentMethod: paymentMethod,
              offerToSend: offerToSend,
            ),
          ),
        ),
      ),
    ),
  );
  // Whether they were sent, then the fields, then what the device keeps.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'sends what the device keeps for the order, on the seller\'s tap only',
    (tester) async {
      final gateway = FakePaymentDetailsGateway(
        kept: {'Banco Pichincha': 'Ahorros 2201234567 · Ana P.'},
      );
      await _pump(tester, gateway, offerToSend: true);

      // Asked for, filled in, and nothing gone anywhere yet.
      expect(find.text(_title), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('Banco Pichincha')).controller!.text,
        'Ahorros 2201234567 · Ana P.',
      );
      expect(gateway.sent, isEmpty);

      await tester.tap(find.text(_send));
      await tester.pump();
      await tester.pump();

      // One message, for this order, with the method that has an account.
      expect(gateway.sent, [
        (
          orderId: _orderId,
          content:
              'Mis datos para recibir el pago:\n'
              '\n'
              'Banco Pichincha\n'
              'Ahorros 2201234567 · Ana P.',
        ),
      ]);
      // Said as sent, and no longer asked for.
      expect(find.textContaining(_sentLine), findsOneWidget);
      expect(find.text(_title), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Ver chat'), findsOneWidget);
    },
  );

  testWidgets('has nothing to send until a method has an account', (
    tester,
  ) async {
    final gateway = FakePaymentDetailsGateway();
    await _pump(tester, gateway, offerToSend: true);

    expect(_button(tester, _send).onPressed, isNull);
    expect(
      find.text('Escribe tus datos en al menos un método para poder enviarlos.'),
      findsOneWidget,
    );

    // A seller who took a buy offer never passed through a form: they
    // write the account here.
    await tester.enterText(_field('De Una'), '099 123 4567');
    await tester.pump();
    expect(_button(tester, _send).onPressed, isNotNull);

    await tester.tap(find.text(_send));
    await tester.pump();
    await tester.pump();
    expect(
      gateway.sent.single.content,
      'Mis datos para recibir el pago:\n\nDe Una\n099 123 4567',
    );
    // And the device keeps it for the next sale.
    expect(gateway.kept['de una'], '099 123 4567');
  });

  testWidgets('leaves an unticked method out of the message', (tester) async {
    final gateway = FakePaymentDetailsGateway(
      kept: {'Banco Pichincha': 'Ahorros 2201234567', 'De Una': '099 123 4567'},
    );
    await _pump(tester, gateway, offerToSend: true);

    await tester.tap(_tick('Banco Pichincha'));
    await tester.pump();
    await tester.tap(find.text(_send));
    await tester.pump();
    await tester.pump();

    expect(
      gateway.sent.single.content,
      'Mis datos para recibir el pago:\n\nDe Una\n099 123 4567',
    );
    // Left out of this message, not forgotten.
    expect(gateway.kept['banco pichincha'], 'Ahorros 2201234567');
  });

  testWidgets('a message no relay took is not said to be sent', (tester) async {
    final gateway = FakePaymentDetailsGateway(kept: {'De Una': '099 123 4567'});
    await _pump(tester, gateway, offerToSend: true);

    gateway.sendError = Exception('NoRelayAccepted');
    await tester.tap(find.text(_send));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Ningún relay aceptó tu mensaje. Revisa tus relays en Ajustes e inténtalo de nuevo',
      ),
      findsOneWidget,
    );
    expect(find.textContaining(_sentLine), findsNothing);
    // Still asked for, and the button is there to try again.
    expect(find.text(_title), findsOneWidget);
    expect(_button(tester, _send).onPressed, isNotNull);

    // The buyer's key not on this device yet is worded as a wait.
    gateway.sendError = Exception(
      'PaymentDetailsPeerUnknown: SessionNotFound: order-1',
    );
    await tester.tap(find.text(_send));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'Todavía no hay conexión con el comprador. Espera un momento e inténtalo de nuevo.',
      ),
      findsOneWidget,
    );

    // And once it does leave, it says so.
    gateway.sendError = null;
    await tester.tap(find.text(_send));
    await tester.pump();
    await tester.pump();
    expect(gateway.sent, hasLength(1));
    expect(find.textContaining(_sentLine), findsOneWidget);
  });

  testWidgets('past the paying step it only says what was sent', (
    tester,
  ) async {
    // Never sent from here — typed into the chat by hand, perhaps — and the
    // buyer already paid: nothing to nag the seller about.
    final gateway = FakePaymentDetailsGateway(kept: {'De Una': '099 123 4567'});
    await _pump(tester, gateway, offerToSend: false);
    expect(find.text(_title), findsNothing);
    expect(find.textContaining(_sentLine), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('what was sent can be sent again', (tester) async {
    final gateway = FakePaymentDetailsGateway(kept: {'De Una': '099 123 4567'});
    gateway.sentAtByOrder[_orderId] = DateTime(2026, 10, 7, 14, 32);
    await _pump(tester, gateway, offerToSend: false);

    expect(find.textContaining(_sentLine), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text(_sendAgain));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('De Una')).controller!.text,
      '099 123 4567',
    );

    await tester.tap(find.text(_sendAgain));
    await tester.pump();
    await tester.pump();
    expect(gateway.sent, hasLength(1));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows neither form before it knows whether they were sent', (
    tester,
  ) async {
    // The answer has not come back: asking for details already sent, a
    // frame before saying they were, is what this avoids.
    final gateway = _SlowAnswer();
    await _pump(tester, gateway, offerToSend: true);
    expect(find.text(_title), findsNothing);
    expect(find.textContaining(_sentLine), findsNothing);

    gateway.answer.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.text(_title), findsOneWidget);
  });
}

/// A device whose "were they sent?" takes its time.
class _SlowAnswer extends FakePaymentDetailsGateway {
  final answer = Completer<DateTime?>();

  @override
  Future<DateTime?> sentAt(String orderId) => answer.future;
}
