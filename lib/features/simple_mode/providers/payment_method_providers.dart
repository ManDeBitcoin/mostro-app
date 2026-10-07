import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';

/// The currency Simple Mode trades in ([simpleCurrency]).
final simpleCurrencyProvider = Provider.autoDispose<String>(
  (ref) => simpleCurrency(
    card: ref.watch(
      activeCommunityProfileProvider.select((s) => s.valueOrNull?.currency),
    ),
    accepted: ref.watch(
      mostroNodeProvider.select((s) => s.valueOrNull?.fiatCurrenciesAccepted),
    ),
  ),
);

/// The community's own payment methods, from its card; null while it has
/// published none.
final _officialMethodsProvider = Provider.autoDispose<List<String>?>(
  (ref) => ref.watch(
    activeCommunityProfileProvider.select((s) => s.valueOrNull?.paymentMethods),
  ),
);

/// The sell orders the Buy tab offers ([isOfferedInSimpleMode]).
final simpleSellOffersProvider = Provider.autoDispose<List<OrderItem>>((ref) {
  final currency = ref.watch(simpleCurrencyProvider);
  final book = ref.watch(orderBookProvider).valueOrNull ?? const <OrderItem>[];
  return [
    for (final order in book)
      if (isOfferedInSimpleMode(order, kind: 'sell', currency: currency)) order,
  ];
});

/// What a seller picks from, under its headings: the community's list.
///
/// A provider and not a value handed to the picker, because the list moves
/// while the picker is open — the card arrives after startup, the operator
/// edits it — and the picker has to show what the screen under it shows.
final sellMethodGroupsProvider = Provider.autoDispose<List<PaymentMethodGroup>>(
  (ref) => groupPaymentMethods(
    sellPaymentMethods(ref.watch(_officialMethodsProvider)),
  ),
);

/// What the Buy tab filters by, under its headings: the seller's list, then
/// whatever else the offers carry ([offerOnlyPaymentMethods]).
final buyMethodGroupsProvider = Provider.autoDispose<List<PaymentMethodGroup>>((
  ref,
) {
  final official = ref.watch(_officialMethodsProvider);
  return groupPaymentMethods(
    sellPaymentMethods(official),
    onOffers: offerOnlyPaymentMethods(
      official: official,
      offers: ref.watch(simpleSellOffersProvider),
      ticked: ref.watch(buyTickedMethodsProvider),
    ),
  );
});

/// How many offers each method can pay ([offersByMethod]), for the Buy
/// tab's picker.
final buyOffersByMethodProvider = Provider.autoDispose<Map<String, int>>(
  (ref) => offersByMethod(ref.watch(simpleSellOffersProvider)),
);

/// What the seller has ticked, as [paymentMethodKey]s. Empty until they
/// tick: no method is chosen for them, and none is published in their name.
///
/// Kept while Simple Mode is on screen, and no longer. It says how whoever
/// holds the device gets paid — a preference, like the order-book filters,
/// not something an identity produced — so it stays through a change of
/// identity made from inside Simple Mode, and `resetIdentityScopedState`
/// leaves it alone.
final sellTickedMethodsProvider = StateProvider.autoDispose<Set<String>>(
  (_) => const {},
);

/// What the Buy tab filters by, as [paymentMethodKey]s. Empty is every
/// method. A preference of whoever holds the device, as
/// [sellTickedMethodsProvider] is.
final buyTickedMethodsProvider = StateProvider.autoDispose<Set<String>>(
  (_) => const {},
);
