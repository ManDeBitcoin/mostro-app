import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

PaymentDetailsEntry _entry(
  String method,
  String details, {
  bool included = true,
}) => PaymentDetailsEntry(method: method, details: details, included: included);

void main() {
  group('orderPaymentMethods', () {
    test("splits an order's one string, as the user's own order writes it", () {
      // The user's own order carries its methods with nothing after the
      // comma; the node's book writes a space.
      expect(orderPaymentMethods('Banco Pichincha,De Una,Efectivo'), [
        'Banco Pichincha',
        'De Una',
        'Efectivo',
      ]);
      expect(orderPaymentMethods(' Banco Pichincha , De Una '), [
        'Banco Pichincha',
        'De Una',
      ]);
    });

    test('names a method once, whatever its spelling', () {
      expect(orderPaymentMethods('De Una, de una,,DE UNA ,Efectivo'), [
        'De Una',
        'Efectivo',
      ]);
      expect(orderPaymentMethods(''), isEmpty);
    });
  });

  group('sellerMaySendPaymentDetails', () {
    const locked = {
      OrderStatus.active,
      OrderStatus.fiatSent,
      OrderStatus.dispute,
    };

    test('is the seller, while the escrow is locked', () {
      for (final status in OrderStatus.values) {
        expect(
          sellerMaySendPaymentDetails(isBuyer: false, status: status),
          locked.contains(status),
          reason: '$status',
        );
        // The details are the seller's to give.
        expect(
          sellerMaySendPaymentDetails(isBuyer: true, status: status),
          isFalse,
          reason: '$status',
        );
      }
    });

    test('is not the public book saying an order was taken', () {
      // `inProgress` lasts from the take until the trade ends: it does not
      // say the seller locked anything (#203).
      expect(
        sellerMaySendPaymentDetails(
          isBuyer: false,
          status: OrderStatus.inProgress,
        ),
        isFalse,
      );
    });
  });

  group('paymentDetailsMessage', () {
    const header = 'Mis datos para recibir el pago:';

    test('carries a block per method, in the order of the order', () {
      expect(
        paymentDetailsMessage(
          header: header,
          entries: [
            _entry('Banco Pichincha', 'Ahorros 2201234567\nAna P.'),
            _entry('De Una', ' 099 123 4567 '),
          ],
        ),
        'Mis datos para recibir el pago:\n'
        '\n'
        'Banco Pichincha\n'
        'Ahorros 2201234567\n'
        'Ana P.\n'
        '\n'
        'De Una\n'
        '099 123 4567',
      );
    });

    test('leaves out what the seller unticked and what they left empty', () {
      final entries = [
        _entry('Banco Pichincha', 'Ahorros 2201234567', included: false),
        _entry('De Una', '099 123 4567'),
        _entry('Efectivo', '   '),
      ];
      expect(paymentDetailsToSend(entries), [_entry('De Una', '099 123 4567')]);
      expect(
        paymentDetailsMessage(header: header, entries: entries),
        'Mis datos para recibir el pago:\n\nDe Una\n099 123 4567',
      );
    });

    test('is no message at all with nothing to say', () {
      // A header alone would read as "sent" to a buyer still without an
      // account to pay into.
      expect(paymentDetailsMessage(header: header, entries: const []), isNull);
      expect(
        paymentDetailsMessage(
          header: header,
          entries: [
            _entry('De Una', ''),
            _entry('Efectivo', 'En persona', included: false),
          ],
        ),
        isNull,
      );
    });
  });
}
