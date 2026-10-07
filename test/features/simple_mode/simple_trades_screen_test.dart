import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/simple_mode/screens/simple_trades_screen.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

import '../../support/load_app_fonts.dart';

/// The methods on the BitMaxis community's card, as an order the user
/// published from Simple Mode carries them: comma-separated, nothing after
/// the comma.
const _everyMethod =
    'Banco Guayaquil,Banco Pichincha,Banco del Pacífico,Produbanco,'
    'Banco Internacional,Banco Bolivariano,Banco del Austro,Cooperativa JEP,'
    'Deuna,peiGo,Payphone,Efectivo (USD),'
    'Retiro sin tarjeta en cajero automático (ATM),USDT';

TradeRow _row({required String id, required String method, String? peer}) =>
    TradeRow(
      orderId: id,
      status: OrderStatus.active,
      state: const TradeRowState(
        group: TradeGroup.inProgress,
        chip: TradeChipLabel.inProgress,
        verb: TradeRowVerb.none,
      ),
      isSelling: true,
      isMaker: true,
      fiatAmount: 100,
      fiatAmountMin: null,
      fiatAmountMax: null,
      fiatCode: 'USD',
      premium: 0,
      amountSats: 118054,
      paymentMethod: method,
      startedAt: 1790000000,
      peerHandle: peer,
    );

Future<void> _pump(WidgetTester tester, List<TradeRow> rows) async {
  // A narrow phone, in logical pixels.
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tradeRowsProvider.overrideWithValue(AsyncValue.data(rows))],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SimpleTradesScreen()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // The real fonts: whether a line fits the card is what is checked here.
  setUpAll(loadAppFonts);

  testWidgets('SimpleTradesScreen fits an order that takes every method', (
    tester,
  ) async {
    await _pump(tester, [
      _row(id: 'many', method: _everyMethod, peer: 'jaguar-veloz-de-los-andes'),
      _row(id: 'one', method: 'Banco Pichincha'),
    ]);

    // Written out, the fourteen ran off the card and took the peer's name
    // with them.
    expect(tester.takeException(), isNull);
    // The first and how many more; one method is written whole.
    expect(find.text('Método: Banco Guayaquil +13'), findsOneWidget);
    expect(find.text('Método: Banco Pichincha'), findsOneWidget);
    // And the peer's name is on the card, inside the screen.
    final peer = find.text('Con: jaguar-veloz-de-los-andes');
    expect(peer, findsOneWidget);
    expect(tester.getBottomRight(peer).dx, lessThanOrEqualTo(360 - 18));
  });

  testWidgets('SimpleTradesScreen cuts a long first method short', (
    tester,
  ) async {
    await _pump(tester, [
      _row(
        id: 'long',
        method: 'Retiro sin tarjeta en cajero automático (ATM),USDT',
        peer: 'jaguar-veloz-de-los-andes',
      ),
    ]);

    expect(tester.takeException(), isNull);
    final peer = find.text('Con: jaguar-veloz-de-los-andes');
    expect(peer, findsOneWidget);
    expect(tester.getBottomRight(peer).dx, lessThanOrEqualTo(360 - 18));
  });

  testWidgets('SimpleTradesScreen gives a long peer name part of the row', (
    tester,
  ) async {
    await _pump(tester, [
      _row(
        id: 'peer',
        method: 'Banco Pichincha',
        peer: 'un-seudonimo-tan-largo-que-no-cabe-en-ninguna-fila-de-la-lista',
      ),
    ]);

    expect(tester.takeException(), isNull);
    // The name is cut short, inside the card, and the method beside it is
    // still there to read.
    final peer = find.textContaining('Con: un-seudonimo');
    expect(tester.getBottomRight(peer).dx, lessThanOrEqualTo(360 - 18));
    expect(
      tester.getSize(find.text('Método: Banco Pichincha')).width,
      greaterThan(90),
    );
  });
}
