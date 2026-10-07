import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderKind, OrderStatus;

OrderItem _order({
  String kind = 'sell',
  double? fiat = 100,
  double? min,
  double? max,
  String fiatCode = 'USD',
  String method = 'Transferencia',
  OrderStatus status = OrderStatus.pending,
  bool isMine = false,
}) => OrderItem(
  id: 'order-1',
  kind: kind,
  fiatAmount: fiat,
  fiatAmountMin: min,
  fiatAmountMax: max,
  fiatCode: fiatCode,
  paymentMethod: method,
  premium: 0,
  creatorPubkey: 'node',
  createdAt: DateTime.utc(2026),
  status: status,
  isMine: isMine,
);

void main() {
  group('sellPaymentMethods', () {
    test("is the community's own list, exactly and in its order", () {
      expect(sellPaymentMethods(['Banco Pichincha', 'DeUna', 'Efectivo']), [
        'Banco Pichincha',
        'DeUna',
        'Efectivo',
      ]);
    });

    test('is the built-in list while the community has published none', () {
      expect(sellPaymentMethods(null), simpleFallbackPaymentMethods);
      expect(sellPaymentMethods(const []), simpleFallbackPaymentMethods);
      expect(sellPaymentMethods(const ['', '  ']), simpleFallbackPaymentMethods);
    });

    test('drops blanks and a second spelling of the same method', () {
      expect(sellPaymentMethods([' Zelle ', '', 'zelle', 'DeUna']), [
        'Zelle',
        'DeUna',
      ]);
    });

    test('writes a comma in a name as a space', () {
      // An order carries its methods comma-separated: with its comma this
      // one would leave as `Transferencia (Pichincha` and `Guayaquil)`.
      expect(
        sellPaymentMethods(['Transferencia (Pichincha, Guayaquil)', ' , ']),
        ['Transferencia (Pichincha Guayaquil)'],
      );
      // And the order made of what is listed splits back into the list.
      final order = simpleSellOrder(
        fiatAmount: 100,
        fiatCode: 'USD',
        paymentMethods: sellPaymentMethods(['A, B', 'C']),
        premium: 0,
      );
      expect(order.paymentMethod.split(','), ['A B', 'C']);
    });
  });

  group('offerOnlyPaymentMethods', () {
    test("is what the offers carry beyond the community's list", () {
      final methods = offerOnlyPaymentMethods(
        official: ['Transferencia', 'DeUna'],
        offers: [
          _order(method: 'Venmo,PayPal'),
          _order(method: 'Banco Pichincha'),
          // Already on the list, in another case.
          _order(method: 'transferencia'),
        ],
      );

      // None of the community's own; the rest alphabetically.
      expect(methods, ['Banco Pichincha', 'PayPal', 'Venmo']);
    });

    test('is nothing when the book adds nothing', () {
      expect(
        offerOnlyPaymentMethods(official: ['DeUna'], offers: const []),
        isEmpty,
      );
      // With no card the built-in list is the community's.
      expect(
        offerOnlyPaymentMethods(
          official: null,
          offers: [_order(method: 'Efectivo, zelle')],
        ),
        isEmpty,
      );
    });

    test('the ones most offers share come first', () {
      final methods = offerOnlyPaymentMethods(
        official: ['Transferencia'],
        offers: [
          _order(method: 'Venmo'),
          _order(method: 'PayPal'),
          _order(method: 'paypal, Venmo'),
          _order(method: 'Venmo'),
          // Named twice by one order: one offer all the same.
          _order(method: 'Zelle, zelle, ZELLE'),
        ],
      );

      expect(methods, ['Venmo', 'PayPal', 'Zelle']);
    });

    test('are capped, so one order cannot fill the picker with rows', () {
      final many = [for (var i = 0; i < 50; i++) 'Metodo ${i.toString().padLeft(2, '0')}'];
      final methods = offerOnlyPaymentMethods(
        official: ['Transferencia'],
        offers: [_order(method: many.join(','))],
      );

      expect(methods, hasLength(maxBookPaymentMethods));
      expect(methods.first, 'Metodo 00');
      expect(methods.last, 'Metodo 11');
    });

    test('keep a ticked one past the cap, while an offer carries it', () {
      final many = [for (var i = 0; i < 50; i++) 'Metodo ${i.toString().padLeft(2, '0')}'];
      final methods = offerOnlyPaymentMethods(
        official: ['Transferencia'],
        offers: [_order(method: many.join(','))],
        // The fortieth by rank, and one no offer carries.
        ticked: {'metodo 39', 'venmo'},
      );

      // Dropped for its rank, it would stop filtering with its offer still
      // on the book, and could not be unticked.
      expect(methods, hasLength(maxBookPaymentMethods + 1));
      expect(methods.last, 'Metodo 39');
      expect(methods, isNot(contains('venmo')));
    });
  });

  group('tickedMethods', () {
    test('are the ticked ones, as the list writes and orders them', () {
      expect(
        tickedMethods(
          ['efectivo', ' DeUna ', 'Zelle'],
          {paymentMethodKey('deuna'), paymentMethodKey('Efectivo')},
        ),
        ['efectivo', ' DeUna '],
      );
    });

    test('never hold a method the user did not tick', () {
      expect(tickedMethods(['Efectivo', 'Zelle'], const {}), isEmpty);
      // One that left the list is not replaced by one that is on it.
      expect(tickedMethods(['Efectivo'], {'zelle'}), isEmpty);
      expect(tickedMethods(const [], {'zelle'}), isEmpty);
    });

    test('take a method back when the list does', () {
      final ticked = {paymentMethodKey('Zelle')};
      expect(tickedMethods(['Efectivo'], ticked), isEmpty);
      expect(tickedMethods(['Efectivo', 'ZELLE'], ticked), ['ZELLE']);
    });
  });

  group('isPaidByAny', () {
    test('no method is every method', () {
      expect(isPaidByAny(_order(method: 'Venmo'), const []), isTrue);
    });

    test('matches one of the order methods whole, whatever the case', () {
      final order = _order(method: 'Banco Pichincha, Transferencia');
      expect(isPaidByAny(order, ['Transferencia']), isTrue);
      expect(isPaidByAny(order, ['banco pichincha']), isTrue);
      expect(isPaidByAny(order, ['Venmo']), isFalse);
      // Not a fragment: `Banco` is not this order's method.
      expect(isPaidByAny(order, ['Banco']), isFalse);
    });

    test('one method in common is enough', () {
      final order = _order(method: 'Banco Pichincha, Transferencia');
      expect(isPaidByAny(order, ['Venmo', 'Transferencia']), isTrue);
      expect(isPaidByAny(order, ['Venmo', 'PayPal']), isFalse);
    });
  });

  group('offersByMethod', () {
    test('counts an offer once for each method it takes', () {
      expect(
        offersByMethod([
          _order(method: 'Banco Pichincha, Deuna'),
          _order(method: 'deuna'),
          // Named twice by one order: one offer all the same.
          _order(method: 'Zelle, zelle'),
          _order(method: ' , '),
        ]),
        {'banco pichincha': 1, 'deuna': 2, 'zelle': 1},
      );
    });
  });

  group('listedTicks', () {
    test('are the ticks a change starts from: the ones on the list', () {
      expect(
        listedTicks(['Efectivo', ' DeUna '], {'deuna', 'zelle', 'efectivo'}),
        {'deuna', 'efectivo'},
      );
      expect(listedTicks(const [], {'zelle'}), isEmpty);
      expect(listedTicks(['Zelle'], const {}), isEmpty);
    });

    test('are a set of their own, safe to change', () {
      final ticked = {'deuna'};
      listedTicks(['DeUna'], ticked).remove('deuna');
      expect(ticked, {'deuna'});
    });
  });

  group('simpleCurrency', () {
    test("is the card's when the community published one", () {
      expect(simpleCurrency(card: 'usd', accepted: 'EUR'), 'USD');
    });

    test('is the one currency the node accepts', () {
      expect(simpleCurrency(card: null, accepted: 'EUR'), 'EUR');
      expect(simpleCurrency(card: '', accepted: ' eur '), 'EUR');
    });

    test('is USD when the node takes several, or any', () {
      expect(simpleCurrency(card: null, accepted: 'USD,EUR'), 'USD');
      expect(simpleCurrency(card: null, accepted: ''), 'USD');
      expect(simpleCurrency(card: null, accepted: null), 'USD');
    });
  });

  group('simpleSellOrder', () {
    test('never carries sats, whatever the premium', () {
      // The node answers fixed sats with a premium with InvalidParameters —
      // "la prima de venta no es válida" — and Simple Mode used to send the
      // screen's estimate as the fixed amount.
      for (final premium in [0.0, 1.0, 5.0, 10.0]) {
        final params = simpleSellOrder(
          fiatAmount: 100,
          fiatCode: 'USD',
          paymentMethods: ['Transferencia'],
          premium: premium,
        );
        expect(params.amountSats, isNull, reason: 'premium $premium');
        expect(params.premium, premium);
        expect(params.kind, OrderKind.sell);
        expect(params.fiatAmount, 100);
        expect(params.fiatAmountMin, isNull);
        expect(params.fiatAmountMax, isNull);
        expect(params.paymentMethod, 'Transferencia');
      }
    });

    test('carries every method ticked, as the node splits them', () {
      final params = simpleSellOrder(
        fiatAmount: 100,
        fiatCode: 'USD',
        paymentMethods: ['Banco Pichincha', 'Deuna', 'Efectivo (USD)'],
        premium: 0,
      );
      // One string, comma-separated and nothing else between: the node
      // makes one value of the public order's `pm` tag out of each.
      expect(params.paymentMethod, 'Banco Pichincha,Deuna,Efectivo (USD)');
    });
  });

  group('wholeFiatAmount', () {
    test('reads a whole positive amount', () {
      expect(wholeFiatAmount('100'), 100);
      expect(wholeFiatAmount(' 50 '), 50);
      expect(wholeFiatAmount('1'), 1);
    });

    test('is null for anything an order cannot carry', () {
      // Empty used to publish 100; a decimal used to be truncated.
      for (final text in ['', ' ', '0', '-5', '50.9', '50,9', '1e3', 'abc']) {
        expect(wholeFiatAmount(text), isNull, reason: '"$text"');
      }
    });
  });

  group('isOfferedInSimpleMode', () {
    test('offers an untaken order of the other side in the currency', () {
      expect(
        isOfferedInSimpleMode(_order(), kind: 'sell', currency: 'usd'),
        isTrue,
      );
    });

    test('hides taken orders, own orders, other currencies and sides', () {
      bool offered(OrderItem o) =>
          isOfferedInSimpleMode(o, kind: 'sell', currency: 'USD');

      // The book carries every status; `in-progress` is someone's trade.
      for (final status in [
        OrderStatus.inProgress,
        OrderStatus.active,
        OrderStatus.waitingPayment,
        OrderStatus.success,
        OrderStatus.canceled,
      ]) {
        expect(offered(_order(status: status)), isFalse, reason: '$status');
      }
      expect(offered(_order(isMine: true)), isFalse);
      expect(offered(_order(fiatCode: 'EUR')), isFalse);
      expect(offered(_order(kind: 'buy')), isFalse);
    });
  });

  group('takeAmountFor', () {
    test('a fixed order is taken for its own amount', () {
      expect(takeAmountFor(_order(fiat: 100), null), 100);
      expect(takeAmountFor(_order(fiat: 100), 30), 100);
    });

    test('a range order needs a whole amount inside its limits', () {
      final range = _order(fiat: null, min: 50, max: 200);
      expect(takeAmountFor(range, 50), 50);
      expect(takeAmountFor(range, 120), 120);
      expect(takeAmountFor(range, 200), 200);
      // No amount, or one outside the range: not takeable — never the
      // minimum picked on the user's behalf.
      expect(takeAmountFor(range, null), isNull);
      expect(takeAmountFor(range, 49), isNull);
      expect(takeAmountFor(range, 201), isNull);
    });
  });

  group('simpleBondFigure', () {
    test('prefers the sized estimate, formatted for the locale', () {
      expect(
        simpleBondFigure(estimateSats: 1056, fraction: 0.03, locale: 'en'),
        '≈ 1,056 sats',
      );
    });

    test('falls back to the node percentage', () {
      expect(
        simpleBondFigure(estimateSats: null, fraction: 0.03, locale: 'en'),
        '3 %',
      );
      expect(
        simpleBondFigure(estimateSats: 0, fraction: 0.015, locale: 'en'),
        '1.5 %',
      );
    });

    test('is null when the node advertises nothing, never a default', () {
      expect(
        simpleBondFigure(estimateSats: null, fraction: null, locale: 'en'),
        isNull,
      );
    });
  });
}
