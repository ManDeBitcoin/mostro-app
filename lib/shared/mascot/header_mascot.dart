import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/mascot/mostro_mascot.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus, TradeUpdate;

/// The Mostro in every tab's app bar: tap it and it reacts, and it picks up
/// the mood of the app around it.
///
/// v1 hid an easter egg in the order book's logo, so this is where v2 keeps
/// its own, now in all three tabs so the bar does not change as the user
/// moves between them (#770). The ambient moods are deliberately cheap: the
/// tab hands in whether it is [waiting], and the trade stream is already
/// alive for the bottom bar's badge, so neither costs a subscription of its
/// own.
class HeaderMascot extends ConsumerStatefulWidget {
  const HeaderMascot({super.key, this.waiting = false});

  /// Height of the artwork in the app bar.
  static const double height = 26;

  /// Whether the tab is waiting on something the user is watching (the
  /// order book's first load). Kept up long enough, Mostro shuffles.
  final bool waiting;

  @override
  ConsumerState<HeaderMascot> createState() => _HeaderMascotState();
}

class _HeaderMascotState extends ConsumerState<HeaderMascot> {
  /// How long a tab may wait before Mostro starts shuffling.
  static const Duration _patienceRunsOut = Duration(seconds: 6);

  /// How long the party lasts after a trade completes.
  static const Duration _celebration = Duration(milliseconds: 1400);

  static const Set<OrderStatus> _completed = {
    OrderStatus.success,
    OrderStatus.settledByAdmin,
    OrderStatus.completedByAdmin,
  };

  Timer? _patience;
  Timer? _party;
  bool _impatient = false;
  bool _celebrating = false;

  @override
  void dispose() {
    _patience?.cancel();
    _party?.cancel();
    super.dispose();
  }

  /// Starts the clock while the tab waits and stops it when the wait ends.
  /// Never calls `setState` itself: it runs from `build`, and the timer's
  /// callback does not.
  void _syncPatience(bool waiting) {
    if (waiting) {
      _patience ??= Timer(_patienceRunsOut, () {
        if (mounted) setState(() => _impatient = true);
      });
      return;
    }
    _patience?.cancel();
    _patience = null;
    if (!_impatient) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _impatient = false);
    });
  }

  void _onTradeUpdate(
    AsyncValue<TradeUpdate>? _,
    AsyncValue<TradeUpdate> next,
  ) {
    final update = next.valueOrNull;
    if (update == null || !_completed.contains(update.status)) return;
    // A restore replays trades that ended long ago; only news is a party.
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      platformInt64ToInt(update.occurredAt) * 1000,
    );
    if (!isFreshEvent(occurredAt: occurredAt, now: clock.now())) return;
    _party?.cancel();
    setState(() => _celebrating = true);
    _party = Timer(_celebration, () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncPatience(widget.waiting);
    ref.listen(tradeUpdatesProvider, _onTradeUpdate);

    final mood = switch ((_celebrating, _impatient)) {
      (true, _) => MostroMood.celebrating,
      (_, true) => MostroMood.impatient,
      _ => MostroMood.neutral,
    };

    return MostroMascot(
      height: HeaderMascot.height,
      mood: mood,
      interactive: true,
    );
  }
}
