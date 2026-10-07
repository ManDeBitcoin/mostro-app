import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart';

/// The methods on the BitMaxis community's card, in the card's order, as
/// read from the node's relays on 2026-10-07.
const _bitmaxis = [
  'Banco Guayaquil',
  'Banco Pichincha',
  'USDT',
  'Banco del Pacífico',
  'Produbanco',
  'Banco Internacional',
  'Banco Bolivariano',
  'Banco del Austro',
  'Cooperativa JEP',
  'Deuna',
  'peiGo',
  'Payphone',
  'Efectivo (USD)',
  'Retiro sin tarjeta en cajero automático (ATM)',
];

void main() {
  group('paymentMethodCategory', () {
    test("files every method on the community's card", () {
      expect(
        {for (final method in _bitmaxis) method: paymentMethodCategory(method)},
        {
          'Banco Guayaquil': PaymentMethodCategory.banks,
          'Banco Pichincha': PaymentMethodCategory.banks,
          'USDT': PaymentMethodCategory.crypto,
          'Banco del Pacífico': PaymentMethodCategory.banks,
          'Produbanco': PaymentMethodCategory.banks,
          'Banco Internacional': PaymentMethodCategory.banks,
          'Banco Bolivariano': PaymentMethodCategory.banks,
          'Banco del Austro': PaymentMethodCategory.banks,
          'Cooperativa JEP': PaymentMethodCategory.cooperatives,
          'Deuna': PaymentMethodCategory.wallets,
          'peiGo': PaymentMethodCategory.wallets,
          'Payphone': PaymentMethodCategory.wallets,
          'Efectivo (USD)': PaymentMethodCategory.cash,
          'Retiro sin tarjeta en cajero automático (ATM)':
              PaymentMethodCategory.cash,
        },
      );
    });

    test('files what sellers have written on the book', () {
      for (final (method, category) in const [
        ('Transferencia', PaymentMethodCategory.banks),
        ('Transferencia bancaria', PaymentMethodCategory.banks),
        ('Transferencia interbancaria', PaymentMethodCategory.banks),
        ('Interbancaria', PaymentMethodCategory.banks),
        ('Depósito bancario', PaymentMethodCategory.banks),
        ('Bank Transfer', PaymentMethodCategory.banks),
        ('Wire transfer', PaymentMethodCategory.banks),
        ('ACH', PaymentMethodCategory.banks),
        ('SWIFT', PaymentMethodCategory.banks),
        ('SPI', PaymentMethodCategory.banks),
        ('Banca Móvil', PaymentMethodCategory.banks),
        ('Transferencia por banca móvil', PaymentMethodCategory.banks),
        // The card's banks as people write them, without the word.
        ('Pichincha', PaymentMethodCategory.banks),
        ('Guayaquil', PaymentMethodCategory.banks),
        ('Pacífico', PaymentMethodCategory.banks),
        ('Bolivariano', PaymentMethodCategory.banks),
        ('Austro', PaymentMethodCategory.banks),
        ('Pago Móvil', PaymentMethodCategory.wallets),
        ('Cooprogreso', PaymentMethodCategory.cooperatives),
        ('COAC Jardín Azuayo', PaymentMethodCategory.cooperatives),
        ('USDT_TRC20', PaymentMethodCategory.crypto),
        ('USDT-BEP20', PaymentMethodCategory.crypto),
        ('Cash', PaymentMethodCategory.cash),
        ('Cash deposit', PaymentMethodCategory.cash),
        ('Efectivo en Guayaquil', PaymentMethodCategory.cash),
        ('Venmo', PaymentMethodCategory.wallets),
        ('PayPal', PaymentMethodCategory.wallets),
        ('Zelle', PaymentMethodCategory.wallets),
        ('Móvil', PaymentMethodCategory.wallets),
        ('Efectivo', PaymentMethodCategory.cash),
        ('Cash in person', PaymentMethodCategory.cash),
        ('Coop. Jardín Azuayo', PaymentMethodCategory.cooperatives),
        ('USDT (TRC20)', PaymentMethodCategory.crypto),
        ('Binance Pay', PaymentMethodCategory.crypto),
      ]) {
        expect(paymentMethodCategory(method), category, reason: method);
      }
    });

    test('reads a name whatever its case, accents or outer spaces', () {
      for (final method in ['MÓVIL', 'movil', ' Móvil ', 'PAGO MOVIL']) {
        expect(
          paymentMethodCategory(method),
          PaymentMethodCategory.wallets,
          reason: method,
        );
      }
      expect(
        paymentMethodCategory('CAJERO AUTOMATICO'),
        PaymentMethodCategory.cash,
      );
      // An accent written as a letter and a combining mark.
      expect(
        paymentMethodCategory('Mo\u0301vil'),
        PaymentMethodCategory.wallets,
      );
      expect(
        paymentMethodCategory('Banco del Paci\u0301fico'),
        PaymentMethodCategory.banks,
      );
    });

    test('goes by the first rule a name matches', () {
      // An app before it is cash.
      expect(paymentMethodCategory('Cash App'), PaymentMethodCategory.wallets);
      // A name that says `banco` is a bank's, whatever else it says.
      expect(
        paymentMethodCategory('Banco Coopnacional'),
        PaymentMethodCategory.banks,
      );
      // A cooperative's transfer is the cooperative's, not a bank's.
      expect(
        paymentMethodCategory('Transferencia Cooperativa JEP'),
        PaymentMethodCategory.cooperatives,
      );
      // Cash handed over a bank's counter is paid in cash.
      expect(
        paymentMethodCategory('Depósito en efectivo Banco Pichincha'),
        PaymentMethodCategory.cash,
      );
      // The wallet, not the bank that runs it.
      expect(
        paymentMethodCategory('Deuna (Banco Pichincha)'),
        PaymentMethodCategory.wallets,
      );
    });

    test('matches whole words, not fragments of other names', () {
      for (final method in [
        // `usd` is a currency, not `usdt`.
        'Giro USD',
        // `wise` inside another word.
        'Likewise',
        // `atm` and `dai` inside other words.
        'Platmo',
        'Daily Pay',
        // `de una` anywhere but at the start is ordinary Spanish.
        'Envío de una remesa',
        // Somebody's brand, not cash: `cash` counts where a name starts
        // with it.
        'Lemon Cash',
        'Ugly Cash',
        // A product name with a number run into it.
        'Transfer365',
      ]) {
        expect(
          paymentMethodCategory(method),
          PaymentMethodCategory.other,
          reason: method,
        );
      }
      expect(paymentMethodCategory('De Una'), PaymentMethodCategory.wallets);
    });

    test('files a name it does not know under other, never under offers', () {
      for (final method in ['Western Union', 'Tarjeta de regalo', '', '???']) {
        expect(
          paymentMethodCategory(method),
          PaymentMethodCategory.other,
          reason: method,
        );
      }
    });
  });

  group('groupPaymentMethods', () {
    test("puts the community's card under its headings", () {
      expect(groupPaymentMethods(_bitmaxis), const [
        PaymentMethodGroup(PaymentMethodCategory.banks, [
          'Banco Guayaquil',
          'Banco Pichincha',
          'Banco del Pacífico',
          'Produbanco',
          'Banco Internacional',
          'Banco Bolivariano',
          'Banco del Austro',
        ]),
        PaymentMethodGroup(PaymentMethodCategory.cooperatives, [
          'Cooperativa JEP',
        ]),
        PaymentMethodGroup(PaymentMethodCategory.wallets, [
          'Deuna',
          'peiGo',
          'Payphone',
        ]),
        PaymentMethodGroup(PaymentMethodCategory.cash, [
          'Efectivo (USD)',
          'Retiro sin tarjeta en cajero automático (ATM)',
        ]),
        PaymentMethodGroup(PaymentMethodCategory.crypto, ['USDT']),
      ]);
    });

    test('keeps every method, once, and no heading without one', () {
      final groups = groupPaymentMethods([
        'Zelle',
        'Western Union',
        'Efectivo',
      ]);

      expect(
        [for (final group in groups) group.category],
        [
          PaymentMethodCategory.wallets,
          PaymentMethodCategory.cash,
          PaymentMethodCategory.other,
        ],
      );
      expect(
        methodsOf(groups),
        unorderedEquals(['Zelle', 'Western Union', 'Efectivo']),
      );
      expect(groupPaymentMethods(const []), isEmpty);
    });

    test("closes with the offers' own methods, as they are given", () {
      final groups = groupPaymentMethods(
        ['Banco Pichincha'],
        // A bank by its name, and still not the community's: it is filed
        // with the offers, not among the community's banks.
        onOffers: ['Venmo', 'Banco Machala'],
      );

      expect(groups, const [
        PaymentMethodGroup(PaymentMethodCategory.banks, ['Banco Pichincha']),
        PaymentMethodGroup(PaymentMethodCategory.onOffers, [
          'Venmo',
          'Banco Machala',
        ]),
      ]);
      expect(methodsOf(groups), ['Banco Pichincha', 'Venmo', 'Banco Machala']);
    });
  });

  group('paymentMethodMatches', () {
    test('finds a name by any part of it, whatever the case or accents', () {
      for (final query in [
        'pacifico',
        'PACÍFICO',
        'Pací',
        'del pac',
        '  banco   del  ',
        // In any order.
        'pacifico banco',
      ]) {
        expect(
          paymentMethodMatches(query, method: 'Banco del Pacífico'),
          isTrue,
          reason: query,
        );
      }
      expect(
        paymentMethodMatches('cajero atm', method: _bitmaxis.last),
        isTrue,
      );
    });

    test('wants every word typed, not any of them', () {
      expect(
        paymentMethodMatches('banco pichincha', method: 'Banco Guayaquil'),
        isFalse,
      );
      expect(paymentMethodMatches('zelle', method: 'Banco Guayaquil'), isFalse);
    });

    test('finds a method by the heading it is under', () {
      // No wallet is called one.
      expect(paymentMethodMatches('billeteras', method: 'Deuna'), isFalse);
      expect(
        paymentMethodMatches(
          'billeteras',
          method: 'Deuna',
          heading: 'Billeteras y apps',
        ),
        isTrue,
      );
      // A word from each.
      expect(
        paymentMethodMatches(
          'apps deu',
          method: 'Deuna',
          heading: 'Billeteras y apps',
        ),
        isTrue,
      );
    });

    test('finds everything with nothing typed', () {
      expect(paymentMethodMatches('', method: 'Deuna'), isTrue);
      expect(paymentMethodMatches('   ', method: 'Deuna'), isTrue);
    });

    test('reads what is typed as letters, never as a pattern', () {
      // A bracket finds the name that has one, and no other.
      expect(paymentMethodMatches('(usd)', method: 'Efectivo (USD)'), isTrue);
      expect(paymentMethodMatches('(', method: 'Efectivo (USD)'), isTrue);
      expect(paymentMethodMatches('(', method: 'Deuna'), isFalse);
      // Each of these would find the name if it were read as a pattern.
      for (final query in ['.*', 'efectivo.', r'\w+', '[a-z]', 'u+', 'e|x']) {
        expect(
          paymentMethodMatches(query, method: 'Efectivo (USD)'),
          isFalse,
          reason: query,
        );
      }
      // Any text at all, a face included, is a query and no more.
      expect(paymentMethodMatches('😀', method: 'Deuna'), isFalse);
    });
  });

  group('isPaymentMethodSearch', () {
    test('is whether anything is asked for', () {
      for (final query in ['a', ' pichincha ', '(', '😀']) {
        expect(isPaymentMethodSearch(query), isTrue, reason: query);
      }
      // Spaces ask for nothing, and neither does what is read as one.
      for (final query in ['', '   ', '_', ' _ ']) {
        expect(isPaymentMethodSearch(query), isFalse, reason: '"$query"');
      }
    });
  });

  group('searchPaymentMethods', () {
    String heading(PaymentMethodCategory category) => switch (category) {
      PaymentMethodCategory.banks => 'Bancos',
      PaymentMethodCategory.wallets => 'Billeteras y apps',
      PaymentMethodCategory.cash => 'Efectivo',
      _ => category.name,
    };
    final groups = groupPaymentMethods(_bitmaxis);

    test('is the whole list while nothing is asked for', () {
      for (final query in ['', '  ', '_']) {
        expect(
          searchPaymentMethods(groups, query, heading),
          same(groups),
          reason: '"$query"',
        );
      }
    });

    test('keeps the methods found, under their headings, in their order', () {
      expect(searchPaymentMethods(groups, 'banco p', heading), const [
        PaymentMethodGroup(PaymentMethodCategory.banks, [
          'Banco Pichincha',
          'Banco del Pacífico',
          'Produbanco',
        ]),
      ]);
      // A whole heading by its name, and one method of another by its own.
      expect(searchPaymentMethods(groups, 'efectivo', heading), const [
        PaymentMethodGroup(PaymentMethodCategory.cash, [
          'Efectivo (USD)',
          'Retiro sin tarjeta en cajero automático (ATM)',
        ]),
      ]);
    });

    test('leaves no heading without a method, and nothing for no match', () {
      expect(
        [
          for (final group in searchPaymentMethods(groups, 'de', heading))
            group.category,
        ],
        [PaymentMethodCategory.banks, PaymentMethodCategory.wallets],
      );
      expect(searchPaymentMethods(groups, 'nequi', heading), isEmpty);
    });
  });
}
