import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

/// PR #252 review (ermeme, supplemental): `UnsupportedNodeProtocol` is
/// reachable from every daemon action, not only create/take, and some Rust
/// wrappers prepend their own context while interpolating the inner error.
/// The central mapper must recognize the marker anywhere in the message so
/// invoice, cancel, fiat-sent, release, dispute, and rating flows all show
/// actionable node-selection guidance instead of a raw marker or an
/// unrelated generic failure.
void main() {
  final l10n = AppLocalizationsEn();

  test('maps the payout claim markers', () {
    expect(
      localizedDaemonError(l10n, 'InvoiceAmountMismatch', fallback: 'x'),
      l10n.bondClaimErrorAmount,
    );
    expect(
      localizedDaemonError(l10n, 'BondClaimExpired', fallback: 'x'),
      l10n.bondClaimErrorExpired,
    );
    expect(
      localizedDaemonError(l10n, 'BondClaimRejected', fallback: 'x'),
      l10n.bondClaimErrorRejected,
    );
    expect(
      localizedDaemonError(l10n, 'ClaimNotClaimable', fallback: 'x'),
      l10n.bondClaimErrorNotClaimable,
    );
    expect(
      localizedDaemonError(l10n, 'ClaimNotFound', fallback: 'x'),
      l10n.bondClaimErrorNotClaimable,
    );
    expect(
      localizedDaemonError(l10n, 'TradeKeyMissing', fallback: 'x'),
      l10n.bondClaimErrorNoKey,
    );
  });

  test('maps the range-with-sats marker of create_order', () {
    expect(
      localizedDaemonError(l10n, 'RangeOrderWithSats', fallback: 'x'),
      l10n.rangeOrderWithSats,
    );
  });

  test('maps the maker bond cancel marker', () {
    expect(
      localizedDaemonError(l10n, 'BondAlreadyLocked', fallback: 'x'),
      l10n.bondAlreadyLocked,
    );
  });

  test('maps the bare unsupported-protocol marker', () {
    expect(
      localizedDaemonError(l10n, 'UnsupportedNodeProtocol:1', fallback: 'x'),
      l10n.nodeProtocolUnsupported,
    );
  });

  test('finds the marker inside the dispute ProtocolError wrapper', () {
    expect(
      localizedDaemonError(
        l10n,
        'ProtocolError: could not build Dispute message: '
        'UnsupportedNodeProtocol:1',
        fallback: 'x',
      ),
      l10n.nodeProtocolUnsupported,
    );
  });

  test('finds the marker inside the rating RateUserDispatchFailed wrapper', () {
    expect(
      localizedDaemonError(
        l10n,
        'RateUserDispatchFailed: UnsupportedNodeProtocol:1',
        fallback: 'x',
      ),
      l10n.nodeProtocolUnsupported,
    );
  });

  test('maps the fail-closed capability-fetch marker', () {
    expect(
      localizedDaemonError(
        l10n,
        'NodeCapabilitiesUnknown: capabilities for node abc not fetched yet',
        fallback: 'x',
      ),
      l10n.nodeCapabilitiesUnknown,
    );
  });

  /// PR #275 review (Catrya): both `DisputeAlreadyOpen` refusals — the record
  /// that already exists and the single-flight guard this PR adds — reach the
  /// UI as the same marker and must not fall through to the generic failure.
  test('maps both DisputeAlreadyOpen refusals', () {
    expect(
      localizedDaemonError(
        l10n,
        'DisputeAlreadyOpen: dispute already exists for trade abc',
        fallback: 'x',
      ),
      l10n.disputeAlreadyOpen,
    );
    expect(
      localizedDaemonError(
        l10n,
        'DisputeAlreadyOpen: an open_dispute for trade abc is already in flight',
        fallback: 'x',
      ),
      l10n.disputeAlreadyOpen,
    );
  });

  /// The order paths resync the trade-key counter and retry once on
  /// `CantDo(InvalidTradeIndex)`; only a second refusal reaches the UI, as the
  /// bare marker — never as the old "Order rejected by Mostro: …" prose.
  test('maps the InvalidTradeIndex marker to the out-of-sync guidance', () {
    expect(
      localizedDaemonError(l10n, 'InvalidTradeIndex', fallback: 'x'),
      l10n.invalidTradeIndexError,
    );
  });

  /// mostro-core 0.14.6 adds `CantDoReason::MaintenanceMode`: the node is
  /// draining and refuses new orders and takes. Rust emits the bare marker;
  /// some wrappers prepend their own context, so match it by substring like
  /// every other marker.
  test('maps the MaintenanceMode marker to the maintenance guidance', () {
    expect(
      localizedDaemonError(l10n, 'MaintenanceMode', fallback: 'x'),
      l10n.mostroMaintenanceMode,
    );
    expect(
      localizedDaemonError(
        l10n,
        'ProtocolError: could not take order: MaintenanceMode',
        fallback: 'x',
      ),
      l10n.mostroMaintenanceMode,
    );
  });

  test('maps a refused duplicate invoice submission', () {
    expect(
      localizedDaemonError(
        l10n,
        'AnyhowException(InvoiceSubmitInFlight)',
        fallback: 'x',
      ),
      l10n.invoiceSubmitInFlight,
    );
  });

  /// What create and take show when the node refuses: the core passes every
  /// reason it has no wording for through as `Order rejected by Mostro: X`,
  /// and that raw text used to reach the screen.
  test('words the daemon refusals a trading client meets', () {
    String refusal(String reason) => localizedDaemonError(
      l10n,
      'AnyhowException(Order rejected by Mostro: $reason)',
      fallback: 'x',
    );

    expect(refusal('InvalidParameters'), l10n.orderRejectedInvalidParameters);
    expect(refusal('InvalidAmount'), l10n.orderRejectedInvalidAmount);
    expect(refusal('InvalidFiatCurrency'), l10n.orderRejectedFiatCurrency);
    expect(refusal('OutOfRangeSatsAmount'), l10n.orderRejectedOutOfRange);
    expect(refusal('OutOfRangeFiatAmount'), l10n.orderRejectedOutOfRange);
    expect(refusal('PriceTooStale'), l10n.orderRejectedPriceStale);
    expect(refusal('PendingOrderExists'), l10n.orderRejectedPendingOrder);
    expect(refusal('InvalidOrderStatus'), l10n.orderNotFoundMessage);
    expect(refusal('NotFound'), l10n.orderNotFoundMessage);
    expect(refusal('NotAllowedByStatus'), l10n.orderRejectedByStatus);
    expect(refusal('IsNotYourOrder'), l10n.orderRejectedNotYours);
    expect(refusal('InvalidPubkey'), l10n.orderRejectedNotYourAction);
    expect(refusal('InvalidPeer'), l10n.orderRejectedOtherParty);
  });

  /// The raw `Order rejected by Mostro: X` is never what the user reads, and
  /// neither is a screen's own fallback when that fallback is the raw text:
  /// three screens used to pass it.
  test('a refusal with no wording of its own is still worded, with its code', () {
    String refusal(String reason) => localizedDaemonError(
      l10n,
      'AnyhowException(Order rejected by Mostro: $reason)',
      fallback: 'x',
    );

    // Reasons mostrod 0.19.2 sends that no screen has a sentence for, and
    // one a newer daemon might add.
    for (final reason in [
      'InvalidOrderKind',
      'InvalidPaymentRequest',
      'InvalidRating',
      'InvalidTextMessage',
      'InvalidSignature',
      'SomethingNew',
    ]) {
      final text = refusal(reason);
      expect(text, l10n.orderRejectedOther(reason), reason: reason);
      expect(text, contains(reason), reason: reason);
      expect(text, isNot(contains('rejected by Mostro')), reason: reason);
    }
    // No reason at all, or one this build cannot name: still a refusal,
    // and not worded as something to try again.
    expect(refusal('unknown'), l10n.orderRejectedNoReason);
    expect(refusal('Unknown'), l10n.orderRejectedNoReason);
  });

  test("the daemon's InvalidPubkey reads by the request it answers", () {
    const refusal = 'AnyhowException(Order rejected by Mostro: InvalidPubkey)';
    // On a take it is the taker's own order, one the core did not know was
    // theirs; anywhere else, a request from the party it does not belong to.
    expect(
      localizedDaemonError(l10n, refusal, fallback: 'x', onTake: true),
      l10n.orderCannotTakeOwn,
    );
    expect(
      localizedDaemonError(l10n, refusal, fallback: 'x'),
      l10n.orderRejectedNotYourAction,
    );
  });

  test('words the takes the core refuses before sending', () {
    String local(String marker) => localizedDaemonError(
      l10n,
      'AnyhowException($marker)',
      fallback: 'x',
    );

    expect(local('CannotTakeOwnOrder'), l10n.orderCannotTakeOwn);
    expect(local('FiatAmountRequired'), l10n.orderAmountMustBeWhole);
    // The order's own range — not the node's limits, which are the
    // daemon's `OutOfRange…Amount` reasons.
    expect(local('OutOfRange'), l10n.orderTakeAmountOutOfRange);
    expect(
      local('Order rejected by Mostro: OutOfRangeSatsAmount'),
      l10n.orderRejectedOutOfRange,
    );
    expect(
      local('Order rejected: fiat amount is out of the allowed range.'),
      l10n.orderRejectedOutOfRange,
    );
  });

  test('words the refusals the core still phrases in English', () {
    String prose(String text) =>
        localizedDaemonError(l10n, 'AnyhowException($text)', fallback: 'x');

    expect(
      prose('Order rejected: sats amount is out of the allowed range.'),
      l10n.orderRejectedOutOfRange,
    );
    expect(
      prose('Order rejected: fiat amount is out of the allowed range.'),
      l10n.orderRejectedOutOfRange,
    );
    expect(
      prose('Order rejected: invalid amount.'),
      l10n.orderRejectedInvalidAmount,
    );
    expect(
      prose('Order rejected: this order does not belong to you.'),
      l10n.orderRejectedNotYours,
    );
    expect(
      prose('Action rejected: not allowed in the current order status.'),
      l10n.orderRejectedByStatus,
    );
    // A cancel the node refuses arrives as the bare marker.
    expect(prose('NotAllowedByStatus'), l10n.orderRejectedByStatus);
  });

  test('a refusal name inside an unrelated error is not a refusal', () {
    // Local errors reuse these names; only the daemon's own wording counts.
    expect(
      localizedDaemonError(l10n, 'InvalidPubkey: odd length', fallback: 'x'),
      'x',
    );
    expect(
      localizedDaemonError(l10n, 'ClaimNotFound', fallback: 'x'),
      l10n.bondClaimErrorNotClaimable,
    );
  });

  test('a first-contact send before the difficulty is known reads as "still checking"', () {
    // What a rating meets when the node's capabilities are not in yet.
    expect(
      localizedDaemonError(
        l10n,
        'RateUserDispatchFailed: PowUnknown: capabilities for node ab12 not '
        'fetched yet — refusing to mine a first-contact event',
        fallback: 'x',
      ),
      l10n.nodeCapabilitiesUnknown,
    );
  });

  test('maps the pre-send checks of a new order or a take', () {
    expect(
      localizedDaemonError(l10n, 'FixedSatsWithPremium', fallback: 'x'),
      l10n.orderFixedSatsWithPremium,
    );
    expect(
      localizedDaemonError(l10n, 'FiatAmountNotWhole', fallback: 'x'),
      l10n.orderAmountMustBeWhole,
    );
    expect(
      localizedDaemonError(l10n, 'PremiumNotWhole', fallback: 'x'),
      l10n.orderPremiumMustBeWhole,
    );
    expect(
      localizedDaemonError(l10n, 'NodeNotAnnouncing', fallback: 'x'),
      l10n.nodeNotAnnouncing,
    );
    expect(
      localizedDaemonError(l10n, 'OrderAlreadyTaken', fallback: 'x'),
      l10n.orderAlreadyTaken,
    );
    // The local "no such order in the book" of a take.
    expect(
      localizedDaemonError(l10n, 'OrderNotFound', fallback: 'x'),
      l10n.orderNotFoundMessage,
    );
  });

  test('maps timeout and storage markers, and falls back otherwise', () {
    expect(
      localizedDaemonError(l10n, 'NoDaemonResponse', fallback: 'x'),
      l10n.sessionTimeoutMessage,
    );
    expect(
      localizedDaemonError(l10n, 'NoRelayAccepted', fallback: 'x'),
      l10n.noRelayAcceptedMessage,
    );
    expect(
      l10n.noRelayAcceptedMessage,
      isNot(l10n.sessionTimeoutMessage),
      reason: 'an event that never left the device is not a daemon timeout',
    );
    expect(
      localizedDaemonError(l10n, 'StorageUnavailable: no db', fallback: 'x'),
      l10n.storageUnavailable,
    );
    expect(
      localizedDaemonError(l10n, 'CantDo: something else', fallback: 'generic'),
      'generic',
    );
  });
}
