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
  OrderStatus status = OrderStatus.pending,
  bool isMine = false,
}) => OrderItem(
  id: 'order-1',
  kind: kind,
  fiatAmount: fiat,
  fiatAmountMin: min,
  fiatAmountMax: max,
  fiatCode: fiatCode,
  paymentMethod: 'Transferencia',
  premium: 0,
  creatorPubkey: 'node',
  createdAt: DateTime.utc(2026),
  status: status,
  isMine: isMine,
);

void main() {
  group('simpleSellOrder', () {
    test('never carries sats, whatever the premium', () {
      // The node answers fixed sats with a premium with InvalidParameters —
      // "la prima de venta no es válida" — and Simple Mode used to send the
      // screen's estimate as the fixed amount.
      for (final premium in [0.0, 1.0, 5.0, 10.0]) {
        final params = simpleSellOrder(
          fiatAmount: 100,
          fiatCode: 'USD',
          paymentMethod: 'Transferencia',
          premium: premium,
        );
        expect(params.amountSats, isNull, reason: 'premium $premium');
        expect(params.premium, premium);
        expect(params.kind, OrderKind.sell);
        expect(params.fiatAmount, 100);
        expect(params.fiatAmountMin, isNull);
        expect(params.fiatAmountMax, isNull);
      }
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
