import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart'
    show OrderStatus, TradeUpdate, TradeUpdateReason;

/// Something that happened, for the header mascot to react to.
class MascotCue {
  const MascotCue(this.mood, this.at);

  final MostroMood mood;

  /// When it happened: what decides whether it is still news when the
  /// mascot comes into view ([isFreshEvent]).
  final DateTime at;
}

/// Updates whose status is not a step.
const Set<TradeUpdateReason> _notASteps = {
  // A cooperative cancel request leaves the status as it was, and Rust emits
  // it with that status.
  TradeUpdateReason.cooperativeCancelRequestedByMe,
  TradeUpdateReason.cooperativeCancelRequestedByPeer,
  // A restore or a re-read, dated now: old news that only the reason gives
  // away.
  TradeUpdateReason.replayed,
};

/// The mood a trade step earns, or null when the step is not one Mostro
/// reacts to.
///
/// Read from `TradeUpdate` alone, which carries what the daemon said. Never
/// from the order book: its Kind 38383 `s` tag is not a trade's status
/// (#203).
MostroMood? moodForTradeUpdate(TradeUpdate update) {
  if (_notASteps.contains(update.reason)) return null;
  return switch (update.status) {
    OrderStatus.active => MostroMood.escrowLocked,
    OrderStatus.fiatSent => MostroMood.fiatSent,
    OrderStatus.dispute => MostroMood.disputed,
    OrderStatus.success ||
    OrderStatus.settledByAdmin ||
    OrderStatus.completedByAdmin => MostroMood.celebrating,
    OrderStatus.canceled ||
    OrderStatus.cooperativelyCanceled ||
    OrderStatus.canceledByAdmin ||
    OrderStatus.expired => MostroMood.canceled,
    _ => null,
  };
}

/// The next thing the header mascot should react to, held until a mascot is
/// on screen to show it (#770 part 3).
///
/// Every tab is its own route, and most of what Mostro reacts to happens
/// while one is not showing: a trade steps forward while its screen is open,
/// an order is published from the form. So a cue waits here, one at a time,
/// and the mascot takes it as it comes into view, if it is still news.
///
/// Kept alive for the trade stream it listens to, which a tab coming and
/// going would otherwise drop. Identity-scoped: `resetIdentityScopedState`
/// invalidates it, so the next user does not see the last one's trade.
class MascotCueNotifier extends Notifier<MascotCue?> {
  @override
  MascotCue? build() {
    ref.listen(tradeUpdatesProvider, (_, next) {
      final update = next.valueOrNull;
      if (update == null) return;
      final mood = moodForTradeUpdate(update);
      if (mood == null) return;
      final at = DateTime.fromMillisecondsSinceEpoch(
        platformInt64ToInt(update.occurredAt) * 1000,
      );
      // A restore replays trades that moved long ago (#474): that is not
      // news, and a pending cue of the present must not give way to it.
      if (!isFreshEvent(occurredAt: at, now: clock.now())) return;
      cue(mood, at: at);
    });
    return null;
  }

  /// Queues [mood], which happened [at] (now when omitted). It replaces the
  /// cue already waiting unless that one is stronger and still news
  /// ([pickMood]).
  void cue(MostroMood mood, {DateTime? at}) {
    final waiting = _fresh();
    if (waiting != null && pickMood([waiting.mood, mood]) != mood) return;
    state = MascotCue(mood, at ?? clock.now());
  }

  /// The node confirmed a new order.
  void orderPublished() => cue(MostroMood.published);

  /// The user rated the counterparty [score] stars.
  void rated(int score) => cue(moodForRating(score));

  /// An action failed with [error]; only the node saying no is a cue.
  void daemonRefused(Object error) {
    if (isDaemonRefusal(error)) cue(MostroMood.refused);
  }

  /// The waiting cue's mood, handed over once, or null when there is none
  /// or it is no longer news.
  MostroMood? take() {
    final waiting = _fresh();
    if (state != null) state = null;
    return waiting?.mood;
  }

  MascotCue? _fresh() {
    final waiting = state;
    if (waiting == null) return null;
    return isFreshEvent(occurredAt: waiting.at, now: clock.now())
        ? waiting
        : null;
  }
}

final mascotCueProvider = NotifierProvider<MascotCueNotifier, MascotCue?>(
  MascotCueNotifier.new,
);
