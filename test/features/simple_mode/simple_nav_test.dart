import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/providers/simple_nav_provider.dart';

void main() {
  group('SimpleNavProvider', () {
    test('defaults to index 0 (buy)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(simpleNavIndexProvider), equals(0));
    });

    test('can switch to all 5 destinations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Buy (0)
      container.read(simpleNavIndexProvider.notifier).state = 0;
      expect(container.read(simpleNavIndexProvider), equals(0));

      // Sell (1)
      container.read(simpleNavIndexProvider.notifier).state = 1;
      expect(container.read(simpleNavIndexProvider), equals(1));

      // Trades (2)
      container.read(simpleNavIndexProvider.notifier).state = 2;
      expect(container.read(simpleNavIndexProvider), equals(2));

      // Profile (3)
      container.read(simpleNavIndexProvider.notifier).state = 3;
      expect(container.read(simpleNavIndexProvider), equals(3));

      // Help (4)
      container.read(simpleNavIndexProvider.notifier).state = 4;
      expect(container.read(simpleNavIndexProvider), equals(4));
    });
  });
}
