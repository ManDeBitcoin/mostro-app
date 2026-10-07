import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/features/simple_mode/providers/payment_method_providers.dart';
import 'package:mostro/features/simple_mode/widgets/payment_method_picker_sheet.dart';
import 'package:mostro/features/simple_mode/widgets/simple_buy_order_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;
import 'package:mostro/src/rust/api/types.dart'
    show NewOrderParams, OrderInfo, OrderKind, OrderStatus;

import '../../support/fake_trades.dart';

const _lower = ValueKey('simple-price-lower');
const _raise = ValueKey('simple-price-raise');
const _whole =
    'Escribe un importe entero: solo cifras, sin decimales ni separadores.';

CommunityProfile _card(List<String> methods, {String currency = 'USD'}) =>
    CommunityProfile(
      version: 1,
      name: 'BitMaxis',
      pubkey: 'node',
      relays: const [],
      currency: currency,
      paymentMethods: methods,
      feeBps: 80,
      bondPercent: 5,
      signature: 'sig-$currency-${methods.join('|')}',
    );

MostroInstance _node({
  BondPolicy policy = BondPolicy.disabled,
  BondApplyTo? applyTo,
  double? pct,
  double? fee,
}) => MostroInstance(
  pubKey: 'node',
  bondPolicy: policy,
  bondApplyTo: applyTo,
  bondAmountPct: pct,
  fee: fee,
);

OrderItem _offer(String method) => OrderItem(
  id: 'offer-$method',
  kind: 'sell',
  fiatAmount: 50,
  fiatCode: 'USD',
  paymentMethod: method,
  premium: 0,
  creatorPubkey: 'peer',
  createdAt: DateTime.utc(2026),
  status: OrderStatus.pending,
  isMine: false,
);

/// What the node was asked to publish, and how often.
class _Sent {
  NewOrderParams? params;
  int times = 0;
}

/// A node that refuses whatever it is sent: the sheet stays up, and nothing
/// navigates.
Future<OrderInfo> _refuse(NewOrderParams _) async =>
    throw Exception('Order rejected by Mostro: InvalidFiatCurrency');

List<Override> _overrides({
  required _Sent sent,
  required Future<OrderInfo> Function(NewOrderParams) answer,
  Set<String> ticked = const {},
  MostroInstance? node,
  List<OrderItem> book = const [],
  Future<CommunityProfile?> Function()? card,
}) => [
  activeCommunityProfileProvider.overrideWith(
    (ref) => ActiveCommunityNotifier(
      read:
          card ??
          () async => _card(['Banco Pichincha', 'Deuna', 'Efectivo']),
    ),
  ),
  orderBookProvider.overrideWith((ref) => Stream.value(book)),
  buyTickedMethodsProvider.overrideWith((ref) => ticked),
  mostroNodeProvider.overrideWith((ref) async => node ?? _node()),
  exchangeRateProvider.overrideWith((ref, code) async => 50000.0),
  createOrderActionProvider.overrideWithValue((params) {
    sent
      ..params = params
      ..times += 1;
    return answer(params);
  }),
];

/// The sheet on its own, over a node that refuses.
Future<_Sent> _pumpSheet(
  WidgetTester tester, {
  int? fiatAmount = 50,
  Set<String> ticked = const {},
  MostroInstance? node,
  List<OrderItem> book = const [],
  Future<OrderInfo> Function(NewOrderParams) answer = _refuse,
  Future<CommunityProfile?> Function()? card,
}) async {
  // Wide and tall: the test font draws every glyph as a square.
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final sent = _Sent();
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        sent: sent,
        answer: answer,
        ticked: ticked,
        node: node,
        book: book,
        card: card,
      ),
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            // The tab under the sheet: what keeps its ticks alive.
            builder: (context, ref, _) {
              ref.watch(buyTickedMethodsProvider);
              return SimpleBuyOrderSheet(fiatAmount: fiatAmount);
            },
          ),
        ),
      ),
    ),
  );
  // The sheet, then the card, the node and the rate it reads.
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return sent;
}

/// The sheet as the app opens it: a modal route over a tab, under a router
/// that knows the two places a published order leads to.
Future<_Sent> _pumpUnderRouter(
  WidgetTester tester, {
  required Future<OrderInfo> Function(NewOrderParams) answer,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final sent = _Sent();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(buyTickedMethodsProvider);
              return Center(
                child: TextButton(
                  onPressed: () => showMostroSheet(
                    context: context,
                    builder: (_) => const SimpleBuyOrderSheet(fiatAmount: 50),
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
      GoRoute(
        path: AppRoute.tradeDetail,
        builder: (_, state) =>
            Scaffold(body: Text('trade ${state.pathParameters['orderId']}')),
      ),
      GoRoute(
        path: AppRoute.payBond,
        builder: (_, state) =>
            Scaffold(body: Text('bond ${state.pathParameters['orderId']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(sent: sent, answer: answer, ticked: {'deuna'}),
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return sent;
}

ProviderContainer _container(WidgetTester tester, Finder within) =>
    ProviderScope.containerOf(tester.element(within), listen: false);

FilledButton _publish(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(
    of: find.byType(SimpleBuyOrderSheet),
    matching: find.bySubtype<FilledButton>(),
  ),
);

void main() {
  testWidgets('publishes a buy order for the amount, the ticks and the price', (
    tester,
  ) async {
    final sent = await _pumpSheet(
      tester,
      // Ticked in another order than the list's.
      ticked: {'efectivo', 'banco pichincha'},
    );

    expect(find.text('Publica tu orden de compra'), findsOneWidget);
    expect(find.text('50 USD'), findsOneWidget);
    // 50 at 50 000, market price.
    expect(find.text('~100000 sats'), findsOneWidget);

    // The buyer offers 2 % over the market: fewer sats for the same money.
    await tester.tap(find.byKey(_raise));
    await tester.tap(find.byKey(_raise));
    await tester.pump();
    expect(find.text('+2%'), findsOneWidget);
    expect(find.text('~98000 sats'), findsOneWidget);
    expect(
      find.textContaining('Con prima: recibes un 2 % menos de sats.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Publicar orden de compra'));
    await tester.pump();
    await tester.pump();

    expect(sent.times, 1);
    final params = sent.params!;
    expect(params.kind, OrderKind.buy);
    expect(params.fiatAmount, 50);
    expect(params.fiatCode, 'USD');
    // What is ticked and on the list, in the list's order.
    expect(params.paymentMethod, 'Banco Pichincha,Efectivo');
    expect(params.premium, 2);
    // At market price: the estimate on screen is never sent as fixed sats.
    expect(params.amountSats, isNull);
    expect(params.fiatAmountMin, isNull);
    expect(params.fiatAmountMax, isNull);

    // The node's refusal, in the user's language; the sheet stays up and
    // can be sent again.
    expect(find.text('Esta comunidad no opera en esa moneda.'), findsOneWidget);
    expect(find.textContaining('rejected by Mostro'), findsNothing);
    expect(_publish(tester).onPressed, isNotNull);
  });

  testWidgets('carries a discount the buyer asks for', (tester) async {
    final sent = await _pumpSheet(tester, ticked: {'deuna'});

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(_lower));
    }
    await tester.pump();
    expect(find.text('-3%'), findsOneWidget);
    // More sats for the same money.
    expect(find.text('~103000 sats'), findsOneWidget);
    expect(
      find.textContaining('Con descuento: recibes un 3 % más de sats.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Publicar orden de compra'));
    await tester.pump();
    await tester.pump();
    expect(sent.params!.premium, -3);
    expect(sent.params!.paymentMethod, 'Deuna');
  });

  testWidgets('publishes nothing until a method is ticked', (tester) async {
    // On the tab nothing ticked is every offer. An order has to name how
    // it is paid.
    final sent = await _pumpSheet(tester);

    expect(_publish(tester).onPressed, isNull);
    expect(find.text('Elige al menos un método de pago'), findsOneWidget);
    expect(find.text('Elige uno o varios'), findsOneWidget);

    // The picker opens over the sheet, with the sheet's own words for what
    // a tick does here.
    await tester.tap(find.text('Elige uno o varios'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentMethodPickerSheet), findsOneWidget);
    expect(
      find.text(
        'Marca todos los medios con los que puedes pagar. Se publican con tu orden.',
      ),
      findsOneWidget,
    );

    // A tick there applies as it is made, and the sheet under the picker
    // reads it. It is the order's tick, not the tab's: which offers the
    // tab shows is not what the buyer was asked.
    await tester.tap(find.text('Deuna'));
    await tester.pumpAndSettle();
    final container = _container(tester, find.byType(SimpleBuyOrderSheet));
    expect(container.read(buyOrderTickedMethodsProvider), {'deuna'});
    expect(container.read(buyTickedMethodsProvider), isEmpty);
    expect(_publish(tester).onPressed, isNotNull);
    expect(sent.times, 0);
  });

  testWidgets("names the community's methods, not whatever an offer wrote", (
    tester,
  ) async {
    // The tab filters by a method only an offer carries — free text from
    // any client. A filter is not something to publish under the user's
    // name.
    final sent = await _pumpSheet(
      tester,
      ticked: {'revolut', 'deuna'},
      book: [_offer('Revolut')],
    );
    // The filter is real: the tab's list, read as the tab reads it, has it.
    final tabList = _container(
      tester,
      find.byType(SimpleBuyOrderSheet),
    ).listen(buyMethodGroupsProvider, (_, _) {});
    addTearDown(tabList.close);
    await tester.pump();
    await tester.pump();
    expect(
      tabList.read().expand((group) => group.methods).toList(),
      contains('Revolut'),
    );

    // The sheet shows what it will send: the community's one, alone.
    expect(find.text('Deuna'), findsOneWidget);
    expect(find.text('Revolut'), findsNothing);

    await tester.tap(find.text('Publicar orden de compra'));
    await tester.pump();
    await tester.pump();
    expect(sent.params!.paymentMethod, 'Deuna');

    // With only the offer's method ticked there is nothing to name.
    await tester.pumpWidget(const SizedBox.shrink());
    final none = await _pumpSheet(
      tester,
      ticked: {'revolut'},
      book: [_offer('Revolut')],
    );
    expect(_publish(tester).onPressed, isNull);
    expect(find.text('Elige al menos un método de pago'), findsOneWidget);
    expect(none.times, 0);
  });

  testWidgets('publishes nothing for an amount that is not whole', (
    tester,
  ) async {
    final sent = await _pumpSheet(
      tester,
      fiatAmount: null,
      ticked: {'deuna'},
    );

    expect(_publish(tester).onPressed, isNull);
    expect(find.text(_whole), findsOneWidget);
    // No amount, no figure made up for it.
    expect(find.textContaining('sats'), findsNothing);
    expect(sent.times, 0);
  });

  testWidgets('goes out in the currency on screen when it is sent', (
    tester,
  ) async {
    // The card can arrive with the sheet already up. The order is in what
    // the sheet shows then, not in what the tab had when it was opened.
    final card = Completer<CommunityProfile?>();
    final sent = await _pumpSheet(
      tester,
      ticked: {'efectivo'},
      card: () => card.future,
    );
    expect(find.text('50 USD'), findsOneWidget);

    card.complete(_card(['Efectivo'], currency: 'EUR'));
    await tester.pump();
    await tester.pump();
    expect(find.text('50 EUR'), findsOneWidget);

    await tester.tap(find.text('Publicar orden de compra'));
    await tester.pump();
    await tester.pump();
    expect(sent.params!.fiatCode, 'EUR');
  });

  testWidgets('shows the fee and the deposit only as the node announces them', (
    tester,
  ) async {
    // Nothing announced: no fee row, no deposit, and the sats say they are
    // before the fee.
    await _pumpSheet(tester, ticked: {'deuna'});
    expect(find.text('Comisión de la comunidad'), findsNothing);
    expect(find.text('Garantía temporal'), findsNothing);
    expect(find.text('Antes de la comisión de la comunidad'), findsOneWidget);

    // A node that charges 1 % and bonds makers: the buyer's half comes off
    // what they receive, and the deposit is the node's own figure.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpSheet(
      tester,
      ticked: {'deuna'},
      node: _node(
        policy: BondPolicy.enabled,
        applyTo: BondApplyTo.make,
        pct: 0.02,
        fee: 0.01,
      ),
    );
    expect(find.text('Comisión de la comunidad'), findsOneWidget);
    expect(find.text('≈ 500 sats'), findsOneWidget);
    expect(find.text('~99500 sats'), findsOneWidget);
    expect(find.text('Garantía temporal'), findsOneWidget);
    expect(find.text('Antes de la comisión de la comunidad'), findsNothing);

    // A node that bonds takers only asks nothing of who publishes.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpSheet(
      tester,
      ticked: {'deuna'},
      node: _node(
        policy: BondPolicy.enabled,
        applyTo: BondApplyTo.take,
        pct: 0.02,
      ),
    );
    expect(find.text('Garantía temporal'), findsNothing);
  });

  group('once the node accepts', () {
    testWidgets('closes, files the user as the buyer and opens the order', (
      tester,
    ) async {
      final sent = await _pumpUnderRouter(
        tester,
        answer: (_) async => fakeTrade(id: 'mine').order,
      );
      final container = _container(tester, find.text('open'));

      await tester.tap(find.text('Publicar orden de compra'));
      await tester.pumpAndSettle();

      expect(sent.times, 1);
      expect(sent.params!.kind, OrderKind.buy);
      // The buyer of their own order: filed as the seller, the trade view
      // would show them the other side's steps.
      expect(container.read(tradeRoleProvider), {'order-mine': true});
      expect(find.byType(SimpleBuyOrderSheet), findsNothing);
      expect(find.text('trade order-mine'), findsOneWidget);
    });

    testWidgets("opens the deposit first when the node asks a maker's", (
      tester,
    ) async {
      await _pumpUnderRouter(
        tester,
        answer: (_) async =>
            fakeTrade(id: 'bonded', status: OrderStatus.waitingMakerBond).order,
      );

      await tester.tap(find.text('Publicar orden de compra'));
      await tester.pumpAndSettle();

      expect(find.byType(SimpleBuyOrderSheet), findsNothing);
      expect(find.text('bond order-bonded'), findsOneWidget);
      expect(find.text('trade order-bonded'), findsNothing);
    });
  });

  group('while the order is on its way', () {
    testWidgets('is sent once, and nothing on the sheet can be changed', (
      tester,
    ) async {
      final answer = Completer<OrderInfo>();
      final sent = await _pumpSheet(
        tester,
        ticked: {'deuna', 'efectivo'},
        answer: (_) => answer.future,
      );
      await tester.tap(find.byKey(_raise));
      await tester.pump();

      // Two taps before a frame, then another once the button has turned
      // into a spinner.
      final button = find.descendant(
        of: find.byType(SimpleBuyOrderSheet),
        matching: find.bySubtype<FilledButton>(),
      );
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(sent.times, 1);
      expect(sent.params!.premium, 1);
      expect(_publish(tester).onPressed, isNull);

      // A step, a tick taken off, the way into the picker: none of them
      // lands. What is on screen stays what was sent.
      await tester.tap(find.byKey(_raise), warnIfMissed: false);
      await tester.tap(find.byKey(_lower), warnIfMissed: false);
      await tester.tap(find.text('Efectivo'), warnIfMissed: false);
      await tester.tap(find.text('Cambiar'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('+1%'), findsOneWidget);
      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.byType(PaymentMethodPickerSheet), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.close_rounded),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );

      // Refused: the sheet is the user's again.
      answer.completeError(
        Exception('Order rejected by Mostro: InvalidFiatCurrency'),
      );
      await tester.pump();
      await tester.pump();
      expect(_publish(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(_raise));
      await tester.pump();
      expect(find.text('+2%'), findsOneWidget);
    });

    testWidgets('a sheet put away still leads to the order it published', (
      tester,
    ) async {
      // A drag closes a sheet whatever it is doing. The order is out by
      // then: saying nothing would leave the buyer thinking it was not.
      final answer = Completer<OrderInfo>();
      final sent = await _pumpUnderRouter(tester, answer: (_) => answer.future);
      final container = _container(tester, find.text('open'));

      await tester.tap(find.text('Publicar orden de compra'));
      await tester.pump();
      expect(sent.times, 1);

      await tester.drag(
        find.text('Publica tu orden de compra'),
        const Offset(0, 1600),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SimpleBuyOrderSheet), findsNothing);
      expect(find.text('open'), findsOneWidget);

      answer.complete(fakeTrade(id: 'late').order);
      await tester.pumpAndSettle();
      expect(container.read(tradeRoleProvider), {'order-late': true});
      expect(find.text('trade order-late'), findsOneWidget);
    });

    testWidgets('a sheet put away says nothing of an order that was refused', (
      tester,
    ) async {
      final answer = Completer<OrderInfo>();
      await _pumpUnderRouter(tester, answer: (_) => answer.future);

      await tester.tap(find.text('Publicar orden de compra'));
      await tester.pump();
      await tester.drag(
        find.text('Publica tu orden de compra'),
        const Offset(0, 1600),
      );
      await tester.pumpAndSettle();

      answer.completeError(
        Exception('Order rejected by Mostro: InvalidFiatCurrency'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('open'), findsOneWidget);
      expect(find.textContaining('trade'), findsNothing);
    });
  });
}
