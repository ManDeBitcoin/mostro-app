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

/// The payment methods offered while the community has published no card
/// (`mostro::community_card`). Once it has, its own list replaces this one.
const simpleFallbackPaymentMethods = [
  'Transferencia',
  'Efectivo',
  'Móvil',
  'Zelle',
];

/// [methods] trimmed, without blanks, and without a second spelling of one
/// already there (`Zelle`, `zelle`), in the order given.
List<String> _distinctMethods(Iterable<String> methods) {
  final seen = <String>{};
  return [
    for (final method in methods.map((m) => m.trim()))
      if (method.isNotEmpty && seen.add(method.toLowerCase())) method,
  ];
}

/// The methods a seller chooses from: the community's own list — [official],
/// from its signed card — exactly, or the built-in one while it has none.
List<String> sellPaymentMethods(List<String>? official) {
  final methods = _distinctMethods(official ?? const []);
  return methods.isEmpty ? simpleFallbackPaymentMethods : methods;
}

/// The methods the Buy tab can filter by: the seller's list
/// ([sellPaymentMethods]), then every other method an offer on the book
/// carries, alphabetically.
///
/// The book's own methods are there so that no offer is out of reach: a
/// method the list does not know yet — the operator has not added it, or a
/// seller used another client — would otherwise hide the offer for good.
List<String> buyPaymentMethods({
  required List<String>? official,
  required Iterable<OrderItem> offers,
}) {
  final fromBook = [
    for (final offer in offers) ...offer.paymentMethod.split(','),
  ]..sort((a, b) => a.trim().toLowerCase().compareTo(b.trim().toLowerCase()));
  return _distinctMethods([...sellPaymentMethods(official), ...fromBook]);
}

/// Whether [order] can be paid by [method]; any order when [method] is null
/// ("all methods").
bool isPaidBy(OrderItem order, String? method) =>
    method == null || order.paymentTokens.contains(method.trim().toLowerCase());

/// The currency Simple Mode trades in: the community card's, else the one
/// currency the node accepts when it accepts exactly one, else USD.
///
/// [accepted] is the node's `fiat_currencies_accepted` tag, comma-separated;
/// empty or absent means it takes any.
String simpleCurrency({required String? card, required String? accepted}) {
  final fromCard = card?.trim().toUpperCase() ?? '';
  if (fromCard.isNotEmpty) return fromCard;
  final codes = [
    for (final code in (accepted ?? '').split(','))
      if (code.trim().isNotEmpty) code.trim().toUpperCase(),
  ];
  return codes.length == 1 ? codes.single : 'USD';
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
