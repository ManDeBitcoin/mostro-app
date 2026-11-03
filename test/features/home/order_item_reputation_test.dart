import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

OrderInfo _info({
  double rating = 0,
  int totalReviews = 0,
  int daysActive = 0,
  int? makerSince,
}) {
  return OrderInfo(
    id: 'order-1',
    kind: OrderKind.sell,
    status: OrderStatus.pending,
    fiatAmount: 100,
    fiatCode: 'USD',
    paymentMethod: 'Wire',
    premium: 1.5,
    nodePubkey: 'node-pubkey',
    createdAt: 1000,
    isMine: false,
    rating: rating,
    totalReviews: totalReviews,
    daysActive: daysActive,
    makerSince: makerSince,
  );
}

void main() {
  group('OrderItem.fromInfo reputation mapping', () {
    test('maps rating, totalReviews, and daysActive from the bridge', () {
      // Arrange
      final info = _info(rating: 4.9, totalReviews: 47, daysActive: 312);

      // Act
      final item = OrderItem.fromInfo(info);

      // Assert
      expect(item.rating, 4.9);
      expect(item.tradeCount, 47);
      expect(item.daysActive, 312);
    });

    test('keeps zeros for makers with no reputation (full privacy)', () {
      // Arrange
      final info = _info();

      // Act
      final item = OrderItem.fromInfo(info);

      // Assert
      expect(item.rating, 0.0);
      expect(item.tradeCount, 0);
      expect(item.daysActive, 0);
      expect(item.makerSince, isNull);
    });

    test('maps makerSince from Unix seconds to a UTC date', () {
      // Arrange — 2023-11-14 00:00:00 UTC.
      final info = _info(daysActive: 10, makerSince: 1699920000);

      // Act
      final item = OrderItem.fromInfo(info);

      // Assert
      expect(item.makerSince, DateTime.utc(2023, 11, 14));
      expect(item.daysActive, 10);
    });
  });

  group('OrderItem.makerFirstTrade', () {
    test('is makerSince, not the stale count', () {
      // Arrange
      final item = OrderItem.fromInfo(
        _info(daysActive: 10, makerSince: 1699920000),
      );

      // Act
      final day = withClock(
        Clock.fixed(DateTime.utc(2024, 11, 13, 18)),
        () => item.makerFirstTrade,
      );

      // Assert
      expect(day, DateTime.utc(2023, 11, 14));
    });

    test('counts daysActive back from now without since', () {
      // Arrange
      final now = DateTime.utc(2024, 11, 13, 18);
      final item = OrderItem.fromInfo(_info(daysActive: 10));

      // Act
      final day = withClock(Clock.fixed(now), () => item.makerFirstTrade);

      // Assert
      expect(day, now.subtract(const Duration(days: 10)));
    });

    test('an order with since differs from one without it', () {
      // Arrange
      final withSince = OrderItem.fromInfo(_info(makerSince: 1699920000));
      final without = OrderItem.fromInfo(_info());

      // Assert — makerSince is part of value equality.
      expect(withSince == without, isFalse);
      expect(withSince, OrderItem.fromInfo(_info(makerSince: 1699920000)));
    });
  });
}
