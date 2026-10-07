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
///
/// [paymentMethods] are every method the seller takes, at least one. An
/// order carries them as one string, comma-separated: the node splits it
/// into the values of the public order's `pm` tag, which is why no method's
/// name may hold a comma.
NewOrderParams simpleSellOrder({
  required double fiatAmount,
  required String fiatCode,
  required List<String> paymentMethods,
  required double premium,
}) => _simpleOrder(
  kind: OrderKind.sell,
  fiatAmount: fiatAmount,
  fiatCode: fiatCode,
  paymentMethods: paymentMethods,
  premium: premium,
);

/// The order Simple Mode publishes for a purchase of [fiatAmount] (a whole
/// amount): the buyer's side of [simpleSellOrder], and built the same way —
/// at market price, without sats, every method the buyer can pay with in
/// one string.
///
/// [premium] reads as on any order: the percent taken off the sats. Above
/// zero the buyer gets fewer sats for the same money, which is paying over
/// the market; below zero is asking for a discount.
NewOrderParams simpleBuyOrder({
  required double fiatAmount,
  required String fiatCode,
  required List<String> paymentMethods,
  required double premium,
}) => _simpleOrder(
  kind: OrderKind.buy,
  fiatAmount: fiatAmount,
  fiatCode: fiatCode,
  paymentMethods: paymentMethods,
  premium: premium,
);

NewOrderParams _simpleOrder({
  required OrderKind kind,
  required double fiatAmount,
  required String fiatCode,
  required List<String> paymentMethods,
  required double premium,
}) => NewOrderParams(
  kind: kind,
  fiatAmount: fiatAmount,
  fiatCode: fiatCode,
  paymentMethod: paymentMethods.join(','),
  premium: premium,
  amountSats: null,
);

/// How far from the market price Simple Mode sets an order, in whole percent
/// either way. The protocol has no limit of its own; this is the reach of
/// the control ([steppedPremium]), the same the create form's bar opens
/// with.
const simplePremiumLimit = 10;

/// [premium] moved by [step] percent, and no further than
/// [simplePremiumLimit] from the market either way. Whole, because the wire
/// carries a premium as an integer.
int steppedPremium(int premium, int step) =>
    (premium + step).clamp(-simplePremiumLimit, simplePremiumLimit);

/// What one BTC costs the buyer of an order with [premium], given the
/// market's [rate]: the node takes the premium off the sats, so the same
/// fiat buys fewer of them. Null while the rate is unknown.
double? priceWithPremium({required double? rate, required int premium}) =>
    rate == null || rate <= 0 || premium >= 100
        ? null
        : rate / (1 - premium / 100);

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
///
/// A comma in a name is written as a space. An order carries its methods
/// comma-separated, so a name with one would leave as two methods, neither
/// of them on the list, and as a filter it would match no offer at all.
List<String> _distinctMethods(Iterable<String> methods) {
  final seen = <String>{};
  return [
    for (final method in methods.map(
      (m) => m.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
    ))
      if (method.isNotEmpty && seen.add(method.toLowerCase())) method,
  ];
}

/// The methods a seller chooses from: the community's own list — [official],
/// from its signed card — exactly, or the built-in one while it has none.
List<String> sellPaymentMethods(List<String>? official) {
  final methods = _distinctMethods(official ?? const []);
  return methods.isEmpty ? simpleFallbackPaymentMethods : methods;
}

/// How many methods of the book's own the Buy tab offers as filters, beyond
/// the community's list. The book is free text any seller writes, from any
/// client: without a limit one order listing fifty methods is fifty rows.
const maxBookPaymentMethods = 12;

/// The methods the offers on the book carry that the community's list
/// ([sellPaymentMethods]) does not: the ones most offers share first, then
/// alphabetically, and no more than [maxBookPaymentMethods] of them — plus
/// any beyond that limit the user has [ticked].
///
/// The Buy tab offers them as filters next to the community's own, so that
/// a method the list does not know yet — the operator has not added it, or
/// a seller used another client — can still be filtered by. No offer
/// depends on it to be seen: with nothing ticked the tab shows every one.
///
/// A ticked one stays listed while any offer carries it, whatever its rank:
/// dropped for being the thirteenth, it would stop filtering — and could no
/// longer be unticked — with its offers still on the book.
List<String> offerOnlyPaymentMethods({
  required List<String>? official,
  required Iterable<OrderItem> offers,
  Set<String> ticked = const {},
}) {
  final known = {
    for (final method in sellPaymentMethods(official)) paymentMethodKey(method),
  };
  final spelling = <String, String>{};
  final count = <String, int>{};
  for (final offer in offers) {
    // An order counts once for a method, however it repeats it.
    final seen = <String>{};
    for (final method in offer.paymentMethod.split(',')) {
      final label = method.trim();
      final key = paymentMethodKey(label);
      if (label.isEmpty || known.contains(key) || !seen.add(key)) continue;
      spelling.putIfAbsent(key, () => label);
      count[key] = (count[key] ?? 0) + 1;
    }
  }
  final fromBook = count.keys.toList()
    ..sort((a, b) {
      final byUse = count[b]!.compareTo(count[a]!);
      return byUse != 0 ? byUse : a.compareTo(b);
    });
  return [
    for (final (rank, key) in fromBook.indexed)
      if (rank < maxBookPaymentMethods || ticked.contains(key)) spelling[key]!,
  ];
}

/// How a payment method is told from another: without regard to case or
/// outer spaces. It is how the book's own filter compares them
/// (`OrderItem.paymentTokens`), and what lets a list that comes back
/// writing `efectivo` still hold the user's `Efectivo`.
String paymentMethodKey(String method) => method.trim().toLowerCase();

/// The entries of [methods] the user has ticked, in the order and the
/// spelling of [methods].
///
/// [ticked] holds [paymentMethodKey]s. It can name a method that has left
/// the list since — the operator dropped it, its last offer was taken: that
/// one is not here, and comes back if the list takes it up again before the
/// user changes their ticks ([listedTicks]). A method the user never ticked
/// is never here, so nothing is chosen in their place.
List<String> tickedMethods(List<String> methods, Set<String> ticked) => [
  for (final method in methods)
    if (ticked.contains(paymentMethodKey(method))) method,
];

/// Of [ticked], the ticks on [methods]: what a change the user makes starts
/// from.
///
/// A tick whose method has left the list is kept while the user leaves
/// their ticks alone, so that it counts again if the list takes the method
/// back ([tickedMethods]). But they cannot see it, and so cannot take it
/// off; the first change they make is made to what they do see, and drops
/// it.
Set<String> listedTicks(List<String> methods, Set<String> ticked) =>
    ticked.intersection({for (final method in methods) paymentMethodKey(method)});

/// Whether [order] can be paid by at least one of [methods]; any order when
/// [methods] is empty ("any method").
bool isPaidByAny(OrderItem order, Iterable<String> methods) =>
    methods.isEmpty ||
    methods.any((m) => order.paymentTokens.contains(paymentMethodKey(m)));

/// How many of [offers] each method can pay, by [paymentMethodKey].
Map<String, int> offersByMethod(Iterable<OrderItem> offers) {
  final count = <String, int>{};
  for (final offer in offers) {
    // A set: an order counts once for a method, however it repeats it.
    for (final key in offer.paymentTokens) {
      if (key.isNotEmpty) count[key] = (count[key] ?? 0) + 1;
    }
  }
  return count;
}

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
