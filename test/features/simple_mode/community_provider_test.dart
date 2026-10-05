import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;

CommunityProfile _card(List<String> methods) => CommunityProfile(
  version: 1,
  name: 'BitMaxis',
  pubkey: 'node',
  relays: const [],
  currency: 'USD',
  paymentMethods: methods,
  feeBps: 80,
  bondPercent: 5,
  signature: 'sig',
);

// `testWidgets` for its clock: `tester.pump(duration)` is what makes the
// notifier's timer fire. A timer left running fails the test before any
// tear-down runs, so each test disposes its notifier itself.
void main() {
  group('ActiveCommunityNotifier', () {
    testWidgets('picks up a card that arrives after startup', (tester) async {
      // The core has read no card yet when the screens first ask.
      CommunityProfile? stored;
      final notifier = ActiveCommunityNotifier(read: () async => stored);
      await tester.pump();
      expect(notifier.state, const AsyncData<CommunityProfile?>(null));

      // The node's card lands; nothing announces it.
      stored = _card(['Transferencia', 'DeUna']);
      await tester.pump(ActiveCommunityNotifier.reloadEvery);
      await tester.pump();

      expect(notifier.state.valueOrNull?.paymentMethods, [
        'Transferencia',
        'DeUna',
      ]);

      // And the operator adds a method while the app is open.
      stored = _card(['Transferencia', 'DeUna', 'Banco Pichincha']);
      await tester.pump(ActiveCommunityNotifier.reloadEvery);
      await tester.pump();

      expect(notifier.state.valueOrNull?.paymentMethods, hasLength(3));
      notifier.dispose();
    });

    testWidgets('an unchanged card is not a new state', (tester) async {
      var reads = 0;
      final notifier = ActiveCommunityNotifier(
        read: () async {
          reads++;
          return _card(['Transferencia']);
        },
      );
      await tester.pump();
      final first = notifier.state;
      var changes = 0;
      final remove = notifier.addListener(
        (_) => changes++,
        fireImmediately: false,
      );

      for (var i = 0; i < 3; i++) {
        await tester.pump(ActiveCommunityNotifier.reloadEvery);
        await tester.pump();
      }

      // Read again each time, and each time the same: every watcher of the
      // profile would otherwise rebuild on a timer.
      expect(reads, 4);
      expect(changes, 0);
      expect(identical(notifier.state, first), isTrue);
      remove();
      notifier.dispose();
    });

    testWidgets('a read that fails keeps the card already on screen', (
      tester,
    ) async {
      var fail = false;
      final notifier = ActiveCommunityNotifier(
        read: () async =>
            fail ? throw StateError('store busy') : _card(['Transferencia']),
      );
      await tester.pump();

      fail = true;
      await tester.pump(ActiveCommunityNotifier.reloadEvery);
      await tester.pump();

      expect(notifier.state.valueOrNull?.paymentMethods, ['Transferencia']);
      expect(notifier.state.hasError, isFalse);
      notifier.dispose();
    });

    testWidgets('a read that keeps failing is not a new state each time', (
      tester,
    ) async {
      final notifier = ActiveCommunityNotifier(
        read: () async => throw StateError('store unreadable'),
      );
      await tester.pump();
      expect(notifier.state.hasError, isTrue);
      final first = notifier.state;
      var changes = 0;
      final remove = notifier.addListener(
        (_) => changes++,
        fireImmediately: false,
      );

      for (var i = 0; i < 3; i++) {
        await tester.pump(ActiveCommunityNotifier.reloadEvery);
        await tester.pump();
      }

      // Three screens watch this: each new error would rebuild them all.
      expect(changes, 0);
      expect(identical(notifier.state, first), isTrue);
      remove();
      notifier.dispose();
    });

    testWidgets('stops reading once disposed', (tester) async {
      var reads = 0;
      final notifier = ActiveCommunityNotifier(
        read: () async {
          reads++;
          return null;
        },
      );
      await tester.pump();
      notifier.dispose();

      await tester.pump(ActiveCommunityNotifier.reloadEvery * 5);

      // The test itself would fail on a timer still pending.
      expect(reads, 1);
    });
  });
}
