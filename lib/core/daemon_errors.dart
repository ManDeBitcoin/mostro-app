import 'package:mostro/l10n/app_localizations.dart';

/// Whether [error] is the daemon's `NotAllowedByStatus`: the order is not in
/// the state the request assumed. The Rust core still words this CantDo as
/// prose; the marker is matched either way.
bool isStatusRejection(Object error) {
  final raw = error.toString();
  return raw.contains('NotAllowedByStatus') ||
      raw.contains('not allowed in the current order status');
}

/// Central mapping from the stable error markers the Rust core emits to
/// localized, actionable messages.
///
/// Every daemon-bound action can now fail with a node-capability marker —
/// the compatibility gate runs on all wraps, not only create/take — and some
/// Rust wrappers prepend their own context (`ProtocolError: ...`,
/// `RateUserDispatchFailed: ...`) while interpolating the inner error, so the
/// marker is matched by substring anywhere in the message.
///
/// Returns [fallback] when the error carries no known marker, so each screen
/// keeps its action-specific generic failure text.
///
/// [onTake] is for the one reason whose meaning depends on the request: the
/// daemon's `InvalidPubkey` answers a take of the taker's own order, and any
/// other request made by the party it does not belong to.
String localizedDaemonError(
  AppLocalizations l10n,
  Object error, {
  required String fallback,
  bool onTake = false,
}) {
  final raw = error.toString();
  // The node speaks a wire protocol this v2-native client does not: it would
  // never read the request, so only an app or node update fixes it.
  if (raw.contains('UnsupportedNodeProtocol')) {
    return l10n.nodeProtocolUnsupported;
  }
  // The node's capability fetch has not completed (startup or node switch):
  // the send failed closed and a retry a moment later usually succeeds.
  if (raw.contains('NodeCapabilitiesUnknown')) {
    return l10n.nodeCapabilitiesUnknown;
  }
  // The same wait, met one step earlier: a first-contact message (a new
  // order, a take, a rating) needs the node's proof-of-work difficulty
  // before it can be mined, and that fetch has not completed either.
  if (raw.contains('PowUnknown')) return l10n.nodeCapabilitiesUnknown;
  // The node is in maintenance mode (mostro-core 0.14.6 `MaintenanceMode`):
  // it refuses new orders and takes until it comes back. Waiting is the only
  // remedy.
  if (raw.contains('MaintenanceMode')) {
    return l10n.mostroMaintenanceMode;
  }
  // The local trade-key counter is behind the node's. Create and take resync
  // it and retry once (mostro::trade_index), so this is a second refusal.
  if (raw.contains('InvalidTradeIndex')) {
    return l10n.invalidTradeIndexError;
  }
  // The daemon refused the buyer invoice: wrong amount, too short an expiry
  // for its payout window, or not an invoice at all. The Rust core words the
  // CantDo as "invalid Lightning invoice"; the marker is matched either way.
  if (raw.contains('InvalidInvoice') ||
      raw.contains('invalid Lightning invoice')) {
    return l10n.invoiceRejected;
  }
  // A second add-invoice while an earlier one still waits for the daemon:
  // refused before it was sent, so the first keeps its reply.
  if (raw.contains('InvoiceSubmitInFlight')) {
    return l10n.invoiceSubmitInFlight;
  }
  // Payout claim submission (docs/ANTI_ABUSE_BOND.md §6.4).
  if (raw.contains('InvoiceAmountMismatch')) {
    return l10n.bondClaimErrorAmount;
  }
  if (raw.contains('BondClaimExpired')) {
    return l10n.bondClaimErrorExpired;
  }
  if (raw.contains('BondClaimRejected')) {
    return l10n.bondClaimErrorRejected;
  }
  if (raw.contains('ClaimNotClaimable') || raw.contains('ClaimNotFound')) {
    return l10n.bondClaimErrorNotClaimable;
  }
  if (raw.contains('TradeKeyMissing')) {
    return l10n.bondClaimErrorNoKey;
  }
  // A maker's cancel lost to its own bond, which locked first: the order is
  // published and is cancelled from its screen (docs/ANTI_ABUSE_BOND.md §6.2).
  if (raw.contains('BondAlreadyLocked')) {
    return l10n.bondAlreadyLocked;
  }
  // An invoice sent and not answered yet: the node may still accept it
  // (#615). Checked before NoDaemonResponse, which it is not.
  if (raw.contains('InvoiceAwaitingDaemon')) {
    return l10n.invoiceAwaitingNode;
  }
  // The daemon never answered within the reply window.
  if (raw.contains('NoDaemonResponse')) {
    return l10n.sessionTimeoutMessage;
  }
  // No relay accepted the event: every relay refused it, timed out or was
  // unreachable (one that timed out may still have forwarded it, so the daemon
  // is not guaranteed to have missed it). Not a timeout: the remedy is the
  // relay list, and a shared message sent users hunting for a network problem
  // their device did not have.
  if (raw.contains('NoRelayAccepted')) {
    return l10n.noRelayAcceptedMessage;
  }
  // The seller's payment details (`send_payment_details`) leave only while
  // the escrow is locked, and only once the buyer's key is on this device —
  // it arrives with the message that announces the lock, so waiting is the
  // remedy for the second.
  if (raw.contains('PaymentDetailsEscrowNotLocked')) {
    return l10n.simplePayDetailsNotLocked;
  }
  if (raw.contains('PaymentDetailsPeerUnknown')) {
    return l10n.simplePayDetailsNoPeerYet;
  }
  // A range order carries no fixed sats: it is priced at market when taken.
  if (raw.contains('RangeOrderWithSats')) {
    return l10n.rangeOrderWithSats;
  }
  // No durable storage: no trade key can be derived (issue #249).
  if (raw.contains('StorageUnavailable')) {
    return l10n.storageUnavailable;
  }
  // The trade has not reached the state where the daemon accepts a dispute.
  if (raw.contains('TradeNotDisputable')) {
    return l10n.tradeNotDisputable;
  }
  // A dispute for this trade already exists, or one is still in flight: the
  // open is a duplicate either way, and retrying it changes nothing.
  if (raw.contains('DisputeAlreadyOpen')) {
    return l10n.disputeAlreadyOpen;
  }
  // Pre-send checks of a new order or a take
  // (`mostro::actions::validate_new_order`): what the daemon would refuse,
  // or the wire would silently truncate.
  if (raw.contains('FixedSatsWithPremium')) {
    return l10n.orderFixedSatsWithPremium;
  }
  if (raw.contains('FiatAmountNotWhole')) return l10n.orderAmountMustBeWhole;
  if (raw.contains('PremiumNotWhole')) return l10n.orderPremiumMustBeWhole;
  // The node has published no recent info event: it is offline, and the
  // request was not sent.
  if (raw.contains('NodeNotAnnouncing')) return l10n.nodeNotAnnouncing;
  // Someone else took the order first.
  if (raw.contains('OrderAlreadyTaken')) return l10n.orderAlreadyTaken;
  // The order left the local book between the tap and the take (its maker
  // cancelled it, or it expired).
  if (raw.contains('OrderNotFound')) return l10n.orderNotFoundMessage;
  // Takes the core refuses before sending anything.
  if (raw.contains('CannotTakeOwnOrder')) return l10n.orderCannotTakeOwn;
  if (raw.contains('FiatAmountRequired')) return l10n.orderAmountMustBeWhole;
  // The bare marker only: `OutOfRangeSatsAmount` and `OutOfRangeFiatAmount`
  // are the daemon's, about the node's limits, and are worded below.
  if (_takeOutOfRange.hasMatch(raw)) return l10n.orderTakeAmountOutOfRange;
  return _localizedRefusal(l10n, raw, onTake: onTake) ?? fallback;
}

/// The core's `OutOfRange`: a range take for an amount outside the order's
/// own limits.
final _takeOutOfRange = RegExp(r'OutOfRange(?![A-Za-z])');

/// The daemon's reason when the core passed a refusal (CantDo) through as
/// `Order rejected by Mostro: <Reason>` — its wording for every reason it
/// has no marker or prose of its own for.
final _refusalReason = RegExp(r'rejected by Mostro: (\w+)');

/// The message for a daemon refusal, or null when [raw] is not one (the
/// caller's fallback then stands). Reasons are matched on the extracted
/// name, not by substring: `InvalidPubkey` and `NotFound` are also what
/// unrelated local errors are called.
///
/// A refusal is never shown as the core passed it through. A reason with no
/// wording of its own gets the general one, naming the daemon's code so
/// whoever is asked for help can look it up.
String? _localizedRefusal(
  AppLocalizations l10n,
  String raw, {
  required bool onTake,
}) {
  // The reasons the core still words as English prose, or returns as a bare
  // marker.
  if (isStatusRejection(raw)) return l10n.orderRejectedByStatus;
  if (raw.contains('out of the allowed range')) {
    return l10n.orderRejectedOutOfRange;
  }
  if (raw.contains('Order rejected: invalid amount')) {
    return l10n.orderRejectedInvalidAmount;
  }
  if (raw.contains('this order does not belong to you')) {
    return l10n.orderRejectedNotYours;
  }
  return switch (_refusalReason.firstMatch(raw)?.group(1)) {
    // Not worded as "fixed sats with a premium": that one is refused before
    // sending (`FixedSatsWithPremium`), so whatever arrives here is some
    // other parameter the node disliked.
    'InvalidParameters' => l10n.orderRejectedInvalidParameters,
    'InvalidAmount' => l10n.orderRejectedInvalidAmount,
    'InvalidFiatCurrency' => l10n.orderRejectedFiatCurrency,
    'OutOfRangeSatsAmount' ||
    'OutOfRangeFiatAmount' => l10n.orderRejectedOutOfRange,
    'PriceTooStale' => l10n.orderRejectedPriceStale,
    'PendingOrderExists' => l10n.orderRejectedPendingOrder,
    // Someone else took it first, or it does not exist on this node.
    'InvalidOrderStatus' || 'NotFound' => l10n.orderNotFoundMessage,
    'IsNotYourOrder' => l10n.orderRejectedNotYours,
    // Taking your own order — one the core did not know was the user's,
    // or it would have refused first (`CannotTakeOwnOrder`) — or acting as
    // the party you are not.
    'InvalidPubkey' =>
      onTake ? l10n.orderCannotTakeOwn : l10n.orderRejectedNotYourAction,
    'InvalidPeer' => l10n.orderRejectedOtherParty,
    null => null,
    // The daemon gave no reason, or one this build cannot name: still a
    // refusal, and not something trying again will change.
    'unknown' || 'Unknown' => l10n.orderRejectedNoReason,
    final reason => l10n.orderRejectedOther(reason),
  };
}
