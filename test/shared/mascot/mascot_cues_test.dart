import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/mascot/mascot_cues.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/provider_harness.dart';

final DateTime _now = DateTime(2026, 6, 1, 12);

TradeUpdate _update(
  OrderStatus status, {
  TradeUpdateReason? reason,
  DateTime? at,
}) => TradeUpdate(
  orderId: 'order-1',
  status: status,
  reason: reason,
  occurredAt: (at ?? _now).millisecondsSinceEpoch ~/ 1000,
);

void main() {
  group('moodForTradeUpdate', () {
    test('gives each step of a trade its face', () {
      expect(
        moodForTradeUpdate(_update(OrderStatus.active)),
        MostroMood.escrowLocked,
      );
      expect(
        moodForTradeUpdate(_update(OrderStatus.fiatSent)),
        MostroMood.fiatSent,
      );
      expect(
        moodForTradeUpdate(_update(OrderStatus.dispute)),
        MostroMood.disputed,
      );
      for (final done in const [
        OrderStatus.success,
        OrderStatus.settledByAdmin,
        OrderStatus.completedByAdmin,
      ]) {
        expect(
          moodForTradeUpdate(_update(done)),
          MostroMood.celebrating,
          reason: done.name,
        );
      }
    });

    test('cries over every way a trade can end without a trade', () {
      for (final ended in const [
        OrderStatus.canceled,
        OrderStatus.cooperativelyCanceled,
        OrderStatus.canceledByAdmin,
        OrderStatus.expired,
      ]) {
        expect(
          moodForTradeUpdate(_update(ended)),
          MostroMood.canceled,
          reason: ended.name,
        );
      }
    });

    test('a cancel request is not a step: the status it carries is old', () {
      // Rust emits the request with the status the screens already show, so
      // reading it as a step would lock the escrow a second time.
      for (final reason in const [
        TradeUpdateReason.cooperativeCancelRequestedByMe,
        TradeUpdateReason.cooperativeCancelRequestedByPeer,
      ]) {
        expect(
          moodForTradeUpdate(_update(OrderStatus.active, reason: reason)),
          isNull,
          reason: reason.name,
        );
      }
    });

    test('a status Rust only re-states is not news', () {
      // A restore and a reputation re-read are dated now, so the reason is
      // all that tells them from a step (#770).
      for (final status in const [
        OrderStatus.success,
        OrderStatus.canceled,
        OrderStatus.dispute,
        OrderStatus.active,
      ]) {
        expect(
          moodForTradeUpdate(
            _update(status, reason: TradeUpdateReason.replayed),
          ),
          isNull,
          reason: status.name,
        );
      }
    });

    test('the waiting steps leave Mostro as it is', () {
      for (final status in const [
        OrderStatus.pending,
        OrderStatus.waitingBuyerInvoice,
        OrderStatus.waitingPayment,
        OrderStatus.waitingTakerBond,
        OrderStatus.waitingMakerBond,
        OrderStatus.settledHoldInvoice,
        OrderStatus.inProgress,
      ]) {
        expect(
          moodForTradeUpdate(_update(status)),
          isNull,
          reason: status.name,
        );
      }
    });
  });

  group('MascotCueNotifier', () {
    late StreamController<TradeUpdate> updates;
    late ProviderContainer container;

    setUp(() {
      updates = StreamController<TradeUpdate>();
      addTearDown(updates.close);
      container = createContainer(
        overrides: [tradeUpdatesProvider.overrideWith((ref) => updates.stream)],
      );
    });

    MascotCueNotifier cues() => container.read(mascotCueProvider.notifier);

    test('holds nothing until something happens', () {
      withClock(Clock.fixed(_now), () {
        expect(container.read(mascotCueProvider), isNull);
        expect(cues().take(), isNull);
      });
    });

    test('hands a cue over once', () {
      withClock(Clock.fixed(_now), () {
        cues().orderPublished();

        expect(cues().take(), MostroMood.published);
        expect(cues().take(), isNull);
      });
    });

    test('drops a cue nobody saw in time', () {
      cues().cue(MostroMood.fiatSent, at: _now);

      withClock(Clock.fixed(_now.add(const Duration(minutes: 3))), () {
        expect(cues().take(), isNull);
        expect(container.read(mascotCueProvider), isNull);
      });
    });

    test('a weaker cue does not push out a dispute still waiting', () {
      withClock(Clock.fixed(_now), () {
        cues().cue(MostroMood.disputed);
        cues().cue(MostroMood.fiatSent);

        expect(cues().take(), MostroMood.disputed);
      });
    });

    test('a newer cue of the same weight replaces the one waiting', () {
      withClock(Clock.fixed(_now), () {
        cues().cue(MostroMood.escrowLocked);
        cues().cue(MostroMood.fiatSent);

        expect(cues().take(), MostroMood.fiatSent);
      });
    });

    test('anything replaces a dispute nobody saw in time', () {
      cues().cue(MostroMood.disputed, at: _now);

      withClock(Clock.fixed(_now.add(const Duration(minutes: 3))), () {
        cues().cue(MostroMood.fiatSent);
        expect(cues().take(), MostroMood.fiatSent);
      });
    });

    test('five stars is love, any other score a thank-you', () {
      withClock(Clock.fixed(_now), () {
        cues().rated(5);
        expect(cues().take(), MostroMood.loved);

        cues().rated(3);
        expect(cues().take(), MostroMood.thankful);
      });
    });

    test('facepalms when the node says no, not when the network fails', () {
      withClock(Clock.fixed(_now), () {
        cues().daemonRefused('NoDaemonResponse');
        expect(cues().take(), isNull);

        cues().daemonRefused('CantDo:IsNotYourOrder');
        expect(cues().take(), MostroMood.refused);
      });
    });

    test('turns a fresh trade step into a cue', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        updates.add(_update(OrderStatus.active));
        await Future<void>.delayed(Duration.zero);

        expect(cues().take(), MostroMood.escrowLocked);
      });
    });

    test('a step a restore replays from history is not news', () async {
      await withClock(Clock.fixed(_now), () async {
        container.listen(mascotCueProvider, (_, _) {});

        updates.add(
          _update(
            OrderStatus.dispute,
            at: _now.subtract(const Duration(days: 3)),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cues().take(), isNull);
      });
    });
  });
}
