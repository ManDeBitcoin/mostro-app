import 'package:clock/clock.dart';
import 'package:intl/intl.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

// How long a user has been on Mostro, computed when it is shown.
//
// The daemon publishes `since`, the Unix timestamp of the user's first trade
// truncated to its UTC day start, next to the deprecated day count (`days` /
// `operating_days`). A count computed when the daemon publishes goes stale
// on any event that sits on relays; a date does not. Daemons that predate
// `since` send only the count, which stays the fallback.

/// Converts a bridge `since` field (`PlatformInt64?`, Unix seconds) to a UTC
/// [DateTime], or `null` when the daemon sent none.
DateTime? reputationSince(Object? seconds) =>
    seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
          platformInt64ToInt(seconds) * 1000,
          isUtc: true,
        );

/// The day of the user's first trade, which every screen shows as their age
/// on Mostro (DS-L10N-5): [since] when the daemon sent it, otherwise
/// [fallbackDays] before now.
DateTime firstTradeDay(DateTime? since, {required int fallbackDays}) =>
    since ?? clock.now().toUtc().subtract(Duration(days: fallbackDays));

/// `since Mar 2023`: a user's age on Mostro as every screen shows it
/// (DS-L10N-5). A date does not go stale and reads without arithmetic, where
/// a day count (`1,323 days`) did neither.
String reputationSinceText(AppLocalizations l10n, DateTime firstTrade) =>
    l10n.reputationSince(DateFormat.yMMM(l10n.localeName).format(firstTrade));

/// The counterparty's first trade from the Peer DM snapshot.
extension TradeInfoPeerAge on TradeInfo {
  /// The counterparty's first trade: `peerSince`, else `peerDays` back.
  DateTime get peerFirstTrade =>
      firstTradeDay(reputationSince(peerSince), fallbackDays: peerDays ?? 0);
}
