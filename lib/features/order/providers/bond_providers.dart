import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/src/rust/api/bond.dart' as bond_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart'
    show BondClaim, BondClaimUpdate, TradeInfo;

/// Whether the pay-bond screen's "why Mostro asks for a deposit" accordion
/// is open.
///
/// Closed whenever the screen is arrived at: someone sent there has a
/// deposit to pay, and with the accordion open the screen shows the
/// explanation in place of the invoice's QR. It used to open the first
/// time and then come back as last left, so the first thing a new user saw
/// of the step was a text with nothing to pay. Open is a choice made on
/// the screen and gone with it (`autoDispose`), not a preference.
class BondExplainerNotifier extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final bondExplainerOpenProvider =
    NotifierProvider.autoDispose<BondExplainerNotifier, bool>(
      BondExplainerNotifier.new,
    );

/// The same-take re-request behind a seam (docs/ANTI_ABUSE_BOND.md §9): a
/// row restored without its bolt11 asks the daemon for it again.
final requestBondInvoiceAgainProvider = Provider<
  Future<TradeInfo> Function(String orderId)
>((ref) => (orderId) => orders_api.requestBondInvoiceAgain(orderId: orderId));

/// The way out of a bond window behind a seam: the daemon cancel, for a
/// taker and — since mostro#996 — for a maker, whose cancel waits for the
/// daemon's answer (docs/ANTI_ABUSE_BOND.md §6.2).
final cancelBondWindowProvider =
    Provider<Future<void> Function(String orderId)>(
      (ref) => (orderId) => orders_api.cancelOrder(orderId: orderId),
    );

/// A maker's explicit "remove from this device" behind a seam, offered only
/// once the node refused the cancel (`MakerCancelRefused`,
/// docs/ANTI_ABUSE_BOND.md §6.2).
final abandonBondedOrderProvider =
    Provider<Future<void> Function(String orderId)>(
      (ref) => (orderId) => bond_api.abandonBondedOrder(orderId: orderId),
    );

/// The core's on-demand expiry of one bond window (what its periodic sweep
/// would do next): called when the pay-bond countdown ends so the row does
/// not linger as "pay deposit" in the lists.
final closeExpiredBondWindowProvider =
    Provider<Future<bool> Function(String orderId)>(
      (ref) => (orderId) => bond_api.closeExpiredBondWindow(orderId: orderId),
    );

/// The core's estimate of the bond the active node would ask for an order of
/// [sats] (`max(pct × amount, floor)`, docs/ANTI_ABUSE_BOND.md §3.4), or null
/// when the node's policy is unknown or not enabled. A warning figure only:
/// the daemon sends the exact bolt11.
final bondEstimateProvider = FutureProvider.autoDispose.family<int?, int>((
  ref,
  sats,
) async {
  final estimate = await bond_api.estimateBondSats(
    orderAmountSats: BigInt.from(sats),
  );
  return estimate?.toInt();
});

// ── Payout claims (docs/ANTI_ABUSE_BOND.md §6.4) ─────────────────────────────

/// Claim phase changes pushed by the core (new claim, submission, ack,
/// payout, expiry). Screens filter by `orderId`.
final bondClaimUpdatesProvider = StreamProvider.autoDispose<BondClaimUpdate>((
  ref,
) async* {
  final stream = await bond_api.onBondClaimUpdated();
  while (true) {
    yield await stream.next();
  }
});

/// The claim for one order, re-read on every claim update for it.
final bondClaimProvider = FutureProvider.autoDispose.family<BondClaim?, String>(
  (ref, orderId) async {
    ref.listen(bondClaimUpdatesProvider, (_, next) {
      if (next.valueOrNull?.orderId == orderId) ref.invalidateSelf();
    });
    final claim = await bond_api.getBondClaim(orderId: orderId);
    _reReadAtNextDeadline(ref, [if (claim != null) claim]);
    return claim;
  },
);

/// Re-run the provider when the nearest pending claim passes its window:
/// nothing else rebuilds a settled trade screen or list at that moment.
void _reReadAtNextDeadline(Ref ref, List<BondClaim> claims) {
  final delay = nextClaimDeadlineDelay(
    claims,
    clock.now().millisecondsSinceEpoch ~/ 1000,
  );
  if (delay == null) return;
  final timer = Timer(delay, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

/// Every claim, most recently changed first.
final bondClaimsProvider = FutureProvider.autoDispose<List<BondClaim>>((
  ref,
) async {
  ref.listen(bondClaimUpdatesProvider, (_, _) => ref.invalidateSelf());
  final claims = await bond_api.listBondClaims();
  _reReadAtNextDeadline(ref, claims);
  return claims;
});

/// The submission behind a seam: publish the bolt11 for a claim's share to
/// the node that issued it.
final submitBondPayoutInvoiceProvider =
    Provider<Future<void> Function(String orderId, String invoice)>(
      (ref) =>
          (orderId, invoice) => bond_api.submitBondPayoutInvoice(
            orderId: orderId,
            invoice: invoice,
          ),
    );
