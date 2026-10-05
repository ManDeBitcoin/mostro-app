import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/simple_mode/widgets/simple_buy_confirm_sheet.dart';
import 'package:mostro/features/simple_mode/widgets/simple_sell_confirm_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart'
    show NewOrderParams, OrderKind, TradeRole;

import '../../support/fake_orders.dart';

/// A node with the given bond policy; everything else is left unset.
MostroInstance _node({
  BondPolicy policy = BondPolicy.disabled,
  BondApplyTo? applyTo,
  double? pct,
}) => MostroInstance(
  pubKey: 'node',
  bondPolicy: policy,
  bondApplyTo: applyTo,
  bondAmountPct: pct,
);

Future<void> _pumpSheet(
  WidgetTester tester,
  Widget sheet, {
  required List<Override> overrides,
}) async {
  // Wide and tall: the test font draws every glyph as a square.
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: sheet)),
      ),
    ),
  );
  // One frame for the sheet, one for the node lookup to answer.
  await tester.pump();
  await tester.pump();
}

/// Pumps a stand-in for the tab the sheets open over — what keeps the node's
/// info alive between one opening and the next — and shows [sheet] once
/// [open] is set. [fetch] stands in for the node lookup, one call per fetch.
Future<void> _pumpUnderTab(
  WidgetTester tester, {
  required Widget sheet,
  required ValueNotifier<bool> open,
  required Future<MostroInstance?> Function() fetch,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mostroNodeProvider.overrideWith((ref) => fetch())],
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(mostroNodeProvider);
              return ValueListenableBuilder<bool>(
                valueListenable: open,
                builder: (context, isOpen, _) => isOpen
                    ? SingleChildScrollView(child: sheet)
                    : const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    ),
  );
  // One frame for the tab, one for its lookup to answer.
  await tester.pump();
  await tester.pump();
}

/// Sets [open] and lets the sheet build, run its check after the first
/// frame, and read whatever a fetch started by that check brings back.
Future<void> _openSheet(WidgetTester tester, ValueNotifier<bool> open) async {
  open.value = true;
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('SimpleSellConfirmSheet', () {
    const sheet = SimpleSellConfirmSheet(
      fiatAmount: 100,
      fiatCode: 'USD',
      paymentMethod: 'Transferencia',
      paymentDetails: '',
      premium: 5,
      // The estimate the screen shows. It used to be sent as the order's
      // fixed sats, next to the premium.
      estimatedSats: 112433,
    );

    testWidgets('publishes at market price and words a refusal', (
      tester,
    ) async {
      NewOrderParams? sent;
      await _pumpSheet(
        tester,
        sheet,
        overrides: [
          mostroNodeProvider.overrideWith((ref) async => _node()),
          createOrderActionProvider.overrideWithValue((params) async {
            sent = params;
            throw Exception('Order rejected by Mostro: InvalidFiatCurrency');
          }),
        ],
      );

      // What the sheet shows is what it sends.
      expect(find.text('100 USD'), findsOneWidget);

      await tester.tap(find.text('CONFIRMAR Y PUBLICAR'));
      await tester.pump();
      await tester.pump();

      // What went to the node: a market-price sell order — no sats.
      expect(sent, isNotNull);
      expect(sent!.amountSats, isNull);
      expect(sent!.premium, 5);
      expect(sent!.fiatAmount, 100);
      expect(sent!.kind, OrderKind.sell);
      // What the user reads: the reason, in their language, not the raw text.
      expect(find.text('Esta comunidad no opera en esa moneda.'), findsOneWidget);
      expect(find.textContaining('rejected by Mostro'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('shows no deposit on a node with bonds off', (tester) async {
      await _pumpSheet(
        tester,
        sheet,
        overrides: [mostroNodeProvider.overrideWith((ref) async => _node())],
      );

      expect(find.text('Garantía temporal'), findsNothing);
    });

    testWidgets('shows no deposit while the node has not answered', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        sheet,
        overrides: [mostroNodeProvider.overrideWith((ref) async => null)],
      );

      expect(find.text('Garantía temporal'), findsNothing);
    });

    testWidgets("shows the node's own deposit when it bonds makers", (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        sheet,
        overrides: [
          mostroNodeProvider.overrideWith(
            (ref) async => _node(
              policy: BondPolicy.enabled,
              applyTo: BondApplyTo.make,
              pct: 0.02,
            ),
          ),
        ],
      );

      expect(find.text('Garantía temporal'), findsOneWidget);
      // Without a bridge there is no sized estimate: the node's percentage.
      expect(find.text('2 %'), findsOneWidget);
    });

    testWidgets('shows none when the node bonds takers only', (tester) async {
      await _pumpSheet(
        tester,
        sheet,
        overrides: [
          mostroNodeProvider.overrideWith(
            (ref) async => _node(
              policy: BondPolicy.enabled,
              applyTo: BondApplyTo.take,
              pct: 0.02,
            ),
          ),
        ],
      );

      expect(find.text('Garantía temporal'), findsNothing);
    });
  });

  group('SimpleBuyConfirmSheet', () {
    testWidgets('takes for the amount it shows and words a refusal', (
      tester,
    ) async {
      double? sentAmount;
      TradeRole? sentRole;
      await _pumpSheet(
        tester,
        SimpleBuyConfirmSheet(
          order: fakeOrder(id: 'o-1', fiatAmountMin: 100, fiatAmountMax: 200),
          fiatAmount: 150,
          fiatCode: 'USD',
          estimatedSats: 170000,
        ),
        overrides: [
          mostroNodeProvider.overrideWith((ref) async => _node()),
          takeOrderActionProvider.overrideWithValue(({
            required orderId,
            required role,
            fiatAmount,
          }) async {
            sentAmount = fiatAmount;
            sentRole = role;
            throw Exception('OrderAlreadyTaken');
          }),
        ],
      );

      expect(find.text('150 USD'), findsOneWidget);

      await tester.tap(find.text('CONFIRMAR Y COMPRAR'));
      await tester.pump();
      await tester.pump();

      expect(sentAmount, 150);
      expect(sentRole, TradeRole.buyer);
      expect(find.text('La orden ya fue tomada'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets("shows the node's own deposit when it bonds takers", (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        SimpleBuyConfirmSheet(
          order: fakeOrder(id: 'o-2'),
          fiatAmount: 100,
          fiatCode: 'USD',
          estimatedSats: 118000,
        ),
        overrides: [
          mostroNodeProvider.overrideWith(
            (ref) async => _node(
              policy: BondPolicy.enabled,
              applyTo: BondApplyTo.both,
              pct: 0.03,
            ),
          ),
        ],
      );

      expect(find.text('Garantía temporal'), findsOneWidget);
      expect(find.text('3 %'), findsOneWidget);
    });

    testWidgets('shows no deposit on a node with bonds off', (tester) async {
      await _pumpSheet(
        tester,
        SimpleBuyConfirmSheet(
          order: fakeOrder(id: 'o-3'),
          fiatAmount: 100,
          fiatCode: 'USD',
          estimatedSats: 118000,
        ),
        overrides: [mostroNodeProvider.overrideWith((ref) async => _node())],
      );

      expect(find.text('Garantía temporal'), findsNothing);
    });
  });

  // Each sheet asks the node again when it opens with no answer on hand
  // (`initState`); the rule is the same in both, checked against a node that
  // bonds that sheet's side.
  final sheets = <String, (Widget Function(), MostroInstance)>{
    'SimpleSellConfirmSheet': (
      () => const SimpleSellConfirmSheet(
        fiatAmount: 100,
        fiatCode: 'USD',
        paymentMethod: 'Transferencia',
        paymentDetails: '',
        premium: 0,
        estimatedSats: 118000,
      ),
      _node(policy: BondPolicy.enabled, applyTo: BondApplyTo.make, pct: 0.02),
    ),
    'SimpleBuyConfirmSheet': (
      () => SimpleBuyConfirmSheet(
        order: fakeOrder(id: 'o-9'),
        fiatAmount: 100,
        fiatCode: 'USD',
        estimatedSats: 118000,
      ),
      _node(policy: BondPolicy.enabled, applyTo: BondApplyTo.take, pct: 0.02),
    ),
  };

  for (final MapEntry(key: name, value: (sheet, bonding)) in sheets.entries) {
    group('$name, the node lookup at open', () {
      testWidgets('asks again when the answer on hand is empty', (
        tester,
      ) async {
        var fetches = 0;
        final open = ValueNotifier(false);
        addTearDown(open.dispose);
        await _pumpUnderTab(
          tester,
          sheet: sheet(),
          open: open,
          // Nothing at the cold start, the node's policy on the second ask.
          fetch: () async => ++fetches == 1 ? null : bonding,
        );
        expect(fetches, 1);

        await _openSheet(tester, open);

        // Without the second ask the deposit stayed unannounced for as
        // long as the tab lived.
        expect(fetches, 2);
        expect(find.text('Garantía temporal'), findsOneWidget);
      });

      testWidgets('keeps an answer already on hand', (tester) async {
        var fetches = 0;
        final open = ValueNotifier(false);
        addTearDown(open.dispose);
        await _pumpUnderTab(
          tester,
          sheet: sheet(),
          open: open,
          fetch: () async {
            fetches++;
            return bonding;
          },
        );
        expect(fetches, 1);

        await _openSheet(tester, open);

        expect(fetches, 1);
        expect(find.text('Garantía temporal'), findsOneWidget);
      });

      testWidgets('asks again after a fetch that failed', (tester) async {
        var fetches = 0;
        final open = ValueNotifier(false);
        addTearDown(open.dispose);
        await _pumpUnderTab(
          tester,
          sheet: sheet(),
          open: open,
          // An error is an answer too, and an empty one.
          fetch: () async =>
              ++fetches == 1 ? throw StateError('relays unreachable') : bonding,
        );
        expect(fetches, 1);

        await _openSheet(tester, open);

        expect(fetches, 2);
        expect(find.text('Garantía temporal'), findsOneWidget);
      });

      testWidgets('asks once more when a fetch in flight comes back empty', (
        tester,
      ) async {
        var fetches = 0;
        final first = Completer<MostroInstance?>();
        final open = ValueNotifier(true);
        addTearDown(open.dispose);
        await _pumpUnderTab(
          tester,
          sheet: sheet(),
          open: open,
          fetch: () => ++fetches == 1 ? first.future : Future.value(bonding),
        );
        await tester.pump();
        expect(fetches, 1);

        // The cold-start answer arrives with the sheet already open.
        first.complete(null);
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(fetches, 2);
        expect(find.text('Garantía temporal'), findsOneWidget);
      });

      testWidgets('asks once per opening, not in a loop', (tester) async {
        var fetches = 0;
        final open = ValueNotifier(false);
        addTearDown(open.dispose);
        await _pumpUnderTab(
          tester,
          sheet: sheet(),
          open: open,
          // A node that announces nothing, however often it is asked.
          fetch: () async {
            fetches++;
            return null;
          },
        );
        expect(fetches, 1);

        await _openSheet(tester, open);
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }

        expect(fetches, 2);
        expect(find.text('Garantía temporal'), findsNothing);
      });

      testWidgets('leaves a fetch in flight to finish', (tester) async {
        var fetches = 0;
        final answer = Completer<MostroInstance?>();
        // Open from the first frame: the sheet meets the lookup mid-flight.
        final open = ValueNotifier(true);
        addTearDown(open.dispose);
        await _pumpUnderTab(
          tester,
          sheet: sheet(),
          open: open,
          fetch: () {
            fetches++;
            return answer.future;
          },
        );
        await tester.pump();

        // Restarting it would discard an answer on its way — and, reopened
        // often enough on slow relays, never let one arrive.
        expect(fetches, 1);
        expect(find.text('Garantía temporal'), findsNothing);

        answer.complete(bonding);
        await tester.pump();
        await tester.pump();
        expect(fetches, 1);
        expect(find.text('Garantía temporal'), findsOneWidget);
      });
    });
  }
}
