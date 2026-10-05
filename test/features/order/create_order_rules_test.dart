import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/about/models/mostro_instance.dart'
    show BondApplyTo, BondPolicy;
import 'package:mostro/features/order/models/create_order_rules.dart';

void main() {
  group('makerBondApplies', () {
    test('applies only to an enabled policy that bonds makers', () {
      expect(
        makerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.make),
        isTrue,
      );
      expect(
        makerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.both),
        isTrue,
      );
      expect(
        makerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.take),
        isFalse,
      );
    });
    test('unknown, disabled or missing policy publishes as before', () {
      expect(
        makerBondApplies(
          policy: BondPolicy.disabled,
          applyTo: BondApplyTo.both,
        ),
        isFalse,
      );
      expect(
        makerBondApplies(policy: BondPolicy.unsupported, applyTo: null),
        isFalse,
      );
      expect(makerBondApplies(policy: null, applyTo: null), isFalse);
    });
  });

  group('takerBondApplies', () {
    test('applies only to an enabled policy that bonds takers', () {
      expect(
        takerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.take),
        isTrue,
      );
      expect(
        takerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.both),
        isTrue,
      );
      expect(
        takerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.make),
        isFalse,
      );
    });
    test('unknown, disabled or missing policy takes as before', () {
      expect(
        takerBondApplies(
          policy: BondPolicy.disabled,
          applyTo: BondApplyTo.both,
        ),
        isFalse,
      );
      expect(
        takerBondApplies(policy: BondPolicy.unsupported, applyTo: null),
        isFalse,
      );
      expect(takerBondApplies(policy: null, applyTo: null), isFalse);
    });
  });

  group('premiumFavour (maker side)', () {
    test('selling above market favours the maker', () {
      expect(premiumFavour(OrderType.sell, 3), PremiumFavour.good);
    });

    test('selling below market plays against the maker', () {
      expect(premiumFavour(OrderType.sell, -3), PremiumFavour.bad);
    });

    test('buying below market favours the maker', () {
      expect(premiumFavour(OrderType.buy, -3), PremiumFavour.good);
    });

    test('buying above market plays against the maker', () {
      expect(premiumFavour(OrderType.buy, 3), PremiumFavour.bad);
    });

    test('zero is neutral on both sides', () {
      expect(premiumFavour(OrderType.buy, 0), PremiumFavour.zero);
      expect(premiumFavour(OrderType.sell, 0), PremiumFavour.zero);
    });

    test('switching side with a premium set inverts the colour', () {
      // Arrange
      const premium = 2.0;

      // Act
      final asSeller = premiumFavour(OrderType.sell, premium);
      final asBuyer = premiumFavour(OrderType.buy, premium);

      // Assert
      expect(asSeller, PremiumFavour.good);
      expect(asBuyer, PremiumFavour.bad);
    });
  });

  group('quickAmounts', () {
    test('USD keeps the base amounts', () {
      expect(quickAmounts(1), [10, 25, 50, 100]);
    });

    test('rounds a weak currency to round figures', () {
      // 1 USD ≈ 1450 ARS → 14 500 / 36 250 / 72 500 / 145 000 raw.
      expect(quickAmounts(1450), [10000, 25000, 50000, 100000]);
    });

    test('rounds a strong currency without collapsing to nothing', () {
      // 1 USD ≈ 0.92 EUR → 9.2 / 23 / 46 / 92 raw.
      expect(quickAmounts(0.92), [10, 25, 50, 100]);
    });

    test('drops duplicates and gives up below two distinct chips', () {
      // 1 USD ≈ 0.31 KWD → 3.1 / 7.75 / 15.5 / 31.
      expect(quickAmounts(0.31), [3, 10, 20, 25]);
      // Rate so small every candidate is under one unit.
      expect(quickAmounts(0.001), isEmpty);
    });

    test('returns nothing without a usable rate', () {
      expect(quickAmounts(null), isEmpty);
      expect(quickAmounts(0), isEmpty);
      expect(quickAmounts(-5), isEmpty);
      expect(quickAmounts(double.nan), isEmpty);
      expect(quickAmounts(double.infinity), isEmpty);
    });
  });

  group('isGroupedWhole', () {
    test('digits alone, or groups of three behind the separator', () {
      for (final text in ['7', '150', '1000', '1.000', '25.000', '1.234.567']) {
        expect(isGroupedWhole(text, '.'), isTrue, reason: text);
      }
      expect(isGroupedWhole('1,000', ','), isTrue);
      expect(isGroupedWhole('1\u202f000', '\u202f'), isTrue);
    });

    test('not a separator that groups nothing, nor another mark', () {
      for (final text in [
        '',
        '10.50',
        '1.00',
        '10.',
        '.5',
        '1.0000',
        '1000.000',
        '1..000',
        '1,000',
        '1.000,5',
        // No field writes a group behind a leading zero.
        '0.500',
        '0.000',
        '00.500',
      ]) {
        expect(isGroupedWhole(text, '.'), isFalse, reason: '"$text"');
      }
    });
  });

  group('canonicalAmount', () {
    String? es(String text) =>
        canonicalAmount(text, groupSeparator: '.', decimalSeparator: ',');
    String? en(String text) =>
        canonicalAmount(text, groupSeparator: ',', decimalSeparator: '.');

    test('strips the group separator of the locale', () {
      expect(es('25.000'), '25000');
      expect(en('25,000'), '25000');
    });

    test('normalises the decimal separator to a dot', () {
      expect(es('1.000,50'), '1000.50');
      expect(en('1,000.50'), '1000.50');
    });

    test('accepts a plain number and trims whitespace', () {
      expect(en(' 42 '), '42');
    });

    test('reads no amount in a group separator that groups nothing', () {
      // Stripped wherever it stood, the dot of a typed `10.50` left 1050.
      expect(es('10.50'), isNull);
      expect(es('100.5'), isNull);
      expect(es('1.00'), isNull);
      expect(es('10.'), isNull);
      expect(es('1.0000'), isNull);
      expect(en('10,50'), isNull);
      expect(en('1,00'), isNull);
      expect(es('0.500'), isNull);
      expect(en('0,500'), isNull);
      // After the decimal separator there is nothing to group.
      expect(es('1,000.5'), isNull);
      // Grouping proper still reads, to any length.
      expect(es('1.000.000'), '1000000');
      expect(en('1,234,567.5'), '1234567.5');
    });

    test('rejects empty, non-numeric, zero, negative and special doubles', () {
      expect(en(''), isNull);
      expect(en('abc'), isNull);
      expect(en('0'), isNull);
      expect(en('-5'), isNull);
      expect(en('Infinity'), isNull);
      expect(en('NaN'), isNull);
      expect(en('1e5'), isNull);
    });
  });

  group('preview markup', () {
    test('recovers each role from a filled-in template', () {
      // Arrange
      final amount = markPreview('5.000 ARS', PreviewRole.amount);
      final premium = markPreview('+3%', PreviewRole.premium);
      final duration = markPreview('24 h', PreviewRole.duration);
      final sentence = 'Vendes BTC por $amount a mercado $premium · $duration';

      // Act
      final fragments = previewFragments(sentence);

      // Assert
      expect(fragments, const [
        PreviewFragment('Vendes BTC por ', PreviewRole.text),
        PreviewFragment('5.000 ARS', PreviewRole.amount),
        PreviewFragment(' a mercado ', PreviewRole.text),
        PreviewFragment('+3%', PreviewRole.premium),
        PreviewFragment(' · ', PreviewRole.text),
        PreviewFragment('24 h', PreviewRole.duration),
      ]);
    });

    test('a sentence without markers is one plain fragment', () {
      expect(previewFragments('hello'), const [
        PreviewFragment('hello', PreviewRole.text),
      ]);
    });

    test('tells sats apart from amount even when the figures match', () {
      final sentence =
          '${markPreview('5.000 sats', PreviewRole.sats)} por '
          '${markPreview('5.000 ARS', PreviewRole.amount)}';
      final roles = previewFragments(sentence).map((f) => f.role).toList();
      expect(roles, [PreviewRole.sats, PreviewRole.text, PreviewRole.amount]);
    });
  });
}
