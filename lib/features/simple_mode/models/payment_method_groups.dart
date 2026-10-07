/// How Simple Mode files payment methods under the headings of its picker.
/// No Flutter here, so each rule is unit-testable; the picker only renders
/// what these return.
library;

/// A heading of the payment-method picker.
enum PaymentMethodCategory {
  banks,
  cooperatives,
  wallets,
  cash,
  crypto,

  /// A method no rule recognises.
  other,

  /// On the Buy tab only: methods the offers carry that the community's list
  /// does not. A method is never filed here by [paymentMethodCategory].
  onOffers,
}

/// What [paymentMethodCategory] looks for, in the order it looks: the first
/// rule a name matches files it. Names are compared in lower case and
/// without accents ([_plain]).
///
/// The order is part of the rule. `Cash App` is an app before it is cash,
/// and a wallet is one even when it names the bank that runs it. A deposit
/// in cash at a bank's counter is paid in cash. A name that says `banco` is
/// a bank's, whatever else it says — `Banco Coopnacional` is no cooperative
/// — while the words a cooperative's transfer shares with a bank's
/// (`transferencia`) only count once the name has turned out not to be one.
///
/// A rule would rather miss than misfile: `Lemon Cash` is nobody's cash, so
/// `cash` counts only where a name starts with it, and what no rule is sure
/// of goes under [PaymentMethodCategory.other].
final _rules = <(PaymentMethodCategory, RegExp)>[
  (
    PaymentMethodCategory.crypto,
    RegExp(
      r'\b(usdt|usdc|dai|busd|tether|stablecoins?|cripto\w*|crypto\w*|'
      r'bitcoin|btc|binance)\b',
    ),
  ),
  (
    PaymentMethodCategory.wallets,
    RegExp(
      r'\b(deuna|peigo|payphone|paypal|zelle|venmo|cash ?app|wise|revolut|'
      r'payoneer|strike|skrill|airtm|zinli|bimo|billeteras?|wallets?|'
      r'pago movil)\b|^de una\b|^movil$',
    ),
  ),
  (
    PaymentMethodCategory.cash,
    RegExp(r'\b(efectivo|cajeros?|atm|en persona|presencial)\b|^cash\b'),
  ),
  (PaymentMethodCategory.banks, RegExp(r'banco|bank')),
  (
    PaymentMethodCategory.cooperatives,
    RegExp(r'\b(coop\w*|coac|jep|jardin azuayo)\b'),
  ),
  (
    PaymentMethodCategory.banks,
    RegExp(
      r'\b(banca|transferencias?|transfers?|depositos?|bancari[ao]s?|'
      r'interbancari[ao]s?|wire|ach|swift|spi|sepa|pichincha|guayaquil|'
      r'pacifico|bolivariano|austro|machala|ruminahui|banecuador)\b',
    ),
  ),
];

const _accented = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _unaccented = 'aaaaaeeeeiiiiooooouuuunc';

/// [text] as a rule reads it: in lower case, without accents — written as
/// one character or as a letter and a combining mark — with `_` as the
/// space it stands for, and without outer spaces. `Móvil`, `movil` and
/// ` MÓVIL ` are one name, and `USDT_TRC20` holds the word `usdt`.
String _plain(String text) {
  final plain = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    // A combining mark: the accent of the letter before it.
    if (rune >= 0x300 && rune <= 0x36f) continue;
    final char = String.fromCharCode(rune);
    final at = _accented.indexOf(char);
    plain.write(
      at >= 0
          ? _unaccented[at]
          : char == '_'
          ? ' '
          : char,
    );
  }
  return plain.toString().trim();
}

/// The heading [method] goes under, read from its name alone.
///
/// The community's card carries the names of its methods and nothing about
/// them, so the name is all there is to go by. A name no rule knows is filed
/// under [PaymentMethodCategory.other]: still offered, only not sorted.
PaymentMethodCategory paymentMethodCategory(String method) {
  final name = _plain(method);
  for (final (category, rule) in _rules) {
    if (rule.hasMatch(name)) return category;
  }
  return PaymentMethodCategory.other;
}

/// One heading of the picker and the methods under it.
class PaymentMethodGroup {
  const PaymentMethodGroup(this.category, this.methods);

  final PaymentMethodCategory category;

  /// In the order their list gave them.
  final List<String> methods;

  @override
  bool operator ==(Object other) =>
      other is PaymentMethodGroup &&
      other.category == category &&
      _sameList(other.methods, methods);

  @override
  int get hashCode => Object.hash(category, Object.hashAll(methods));

  @override
  String toString() => '$category: $methods';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [listed] under its headings: the headings in the order of
/// [PaymentMethodCategory], each one's methods in the order of [listed], and
/// no heading without a method. [onOffers], when there are any, close the
/// list under a heading of their own.
List<PaymentMethodGroup> groupPaymentMethods(
  List<String> listed, {
  List<String> onOffers = const [],
}) {
  final filed = <PaymentMethodCategory, List<String>>{};
  for (final method in listed) {
    filed.putIfAbsent(paymentMethodCategory(method), () => []).add(method);
  }
  return [
    for (final category in PaymentMethodCategory.values)
      if (filed[category] case final methods?)
        PaymentMethodGroup(category, methods),
    if (onOffers.isNotEmpty)
      PaymentMethodGroup(PaymentMethodCategory.onOffers, onOffers),
  ];
}

/// Whether [query] finds the method named [method], listed under a heading
/// the user reads as [heading].
///
/// Every word of the query has to be in the name or in the heading, in any
/// order and read as a rule reads a name ([_plain]): `pichin`, `PACIFICO` and
/// `banco pac` find their banks, and `billeteras` finds every wallet though
/// none is called one. A blank query finds everything.
bool paymentMethodMatches(
  String query, {
  required String method,
  String heading = '',
}) {
  final listed = '${_plain(method)} ${_plain(heading)}';
  return _plain(
    query,
  ).split(RegExp(r'\s+')).every((word) => listed.contains(word));
}

/// Whether [query] asks for anything: whether something is left of it once
/// it is read as a rule reads a name ([_plain]). Spaces do not, and neither
/// does a `_`, which is read as one.
bool isPaymentMethodSearch(String query) => _plain(query).isNotEmpty;

/// [groups] with only the methods [query] finds ([paymentMethodMatches]),
/// and no heading left without one; [groups] itself for a query that asks
/// for nothing ([isPaymentMethodSearch]). [headingOf] is what a heading is
/// called in the user's language.
List<PaymentMethodGroup> searchPaymentMethods(
  List<PaymentMethodGroup> groups,
  String query,
  String Function(PaymentMethodCategory category) headingOf,
) {
  if (!isPaymentMethodSearch(query)) return groups;
  final found = <PaymentMethodGroup>[];
  for (final group in groups) {
    final heading = headingOf(group.category);
    final methods = [
      for (final method in group.methods)
        if (paymentMethodMatches(query, method: method, heading: heading))
          method,
    ];
    if (methods.isNotEmpty) {
      found.add(PaymentMethodGroup(group.category, methods));
    }
  }
  return found;
}

/// Every method of [groups], in the order the picker shows them.
List<String> methodsOf(List<PaymentMethodGroup> groups) => [
  for (final group in groups) ...group.methods,
];
