/// Pure rules shared by the Simple Mode buy and sell flows. No Flutter here,
/// so each is unit-testable; the screens only render what these return.
library;

import 'package:intl/intl.dart';

import 'package:mostro/features/home/providers/home_order_providers.dart'
    show OrderItem;
import 'package:mostro/features/order/models/bond_rules.dart'
    show bondSharePercent;
import 'package:mostro/src/rust/api/types.dart'
    show NewOrderParams, OrderKind, OrderStatus;

/// The whole fiat amount typed in [text], or null when it is not one an
/// order can carry: empty, zero, negative, or with decimals.
///
/// The protocol takes fiat amounts as integers. `50.9` is therefore not
/// "about 50": sent as it is, the node would trade 50 while the screen said
/// 50.9, so it is refused here instead.
int? wholeFiatAmount(String text) {
  final amount = int.tryParse(text.trim());
  return amount != null && amount >= 1 ? amount : null;
}

/// The order Simple Mode publishes for a sale of [fiatAmount] (a whole
/// amount): always at market price, so it carries no sats.
///
/// The node fixes the sats when the order is taken and applies [premium]
/// then. Fixed sats together with a premium is what the node refuses with
/// `CantDo(InvalidParameters)`; fixed sats with no premium would freeze a
/// price the screen calls "market". The estimate on screen is for display.
NewOrderParams simpleSellOrder({
  required double fiatAmount,
  required String fiatCode,
  required String paymentMethod,
  required double premium,
}) => NewOrderParams(
  kind: OrderKind.sell,
  fiatAmount: fiatAmount,
  fiatCode: fiatCode,
  paymentMethod: paymentMethod,
  premium: premium,
  amountSats: null,
);

/// Whether Simple Mode offers [order] to someone looking for an order of
/// [kind] (`sell` on the Buy tab, `buy` on the Sell tab): untaken on the
/// public book, in [currency], and not the user's own.
///
/// The book also carries taken orders and the user's own trades, in every
/// status; only `pending` is an offer. Even that is the node's public view
/// and can lag a take by someone else — the take itself is what settles it.
bool isOfferedInSimpleMode(
  OrderItem order, {
  required String kind,
  required String currency,
}) =>
    order.kind == kind &&
    order.status == OrderStatus.pending &&
    !order.isMine &&
    order.fiatCode.toUpperCase() == currency.toUpperCase();

/// The amount a buyer would take [order] for, given the whole amount they
/// typed: a fixed order's own amount, or [typed] when it falls inside a
/// range order's limits. Null for a range order with no usable amount — it
/// cannot be taken without one, and the minimum is not a guess to make for
/// the user.
int? takeAmountFor(OrderItem order, int? typed) {
  if (!order.isRange) return order.fiatAmount?.toInt();
  if (typed == null) return null;
  final inRange =
      typed >= order.fiatAmountMin! && typed <= order.fiatAmountMax!;
  return inRange ? typed : null;
}

/// What Simple Mode shows for the deposit the node asks before a trade: the
/// core's estimate in sats when it has one, else the node's percentage.
/// Null when the node advertises neither, so the row is left out rather
/// than filled with an invented figure.
String? simpleBondFigure({
  required int? estimateSats,
  required double? fraction,
  required String locale,
}) {
  if (estimateSats != null && estimateSats > 0) {
    final sats = NumberFormat.decimalPattern(locale).format(estimateSats);
    return '≈ $sats sats';
  }
  final pct = bondSharePercent(fraction);
  return pct == null ? null : '$pct %';
}
