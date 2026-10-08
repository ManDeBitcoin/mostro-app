import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/mascot/mostro_mascot.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';
import 'package:mostro/shared/widgets/tab_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/provider_harness.dart';

/// No anniversary, so no season badge joins the mascot.
final DateTime _plainDay = DateTime(2026, 6, 1, 12);

Future<StreamController<TradeUpdate>> _pump(
  WidgetTester tester, {
  bool waiting = false,
}) async {
  final updates = StreamController<TradeUpdate>();
  addTearDown(updates.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: createContainer(
        overrides: [
          tradeUpdatesProvider.overrideWith((ref) => updates.stream),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
          backupReminderProvider.overrideWith(
            (ref) => BackupReminderNotifier(initialValue: false),
          ),
        ],
      ),
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TabAppBar(onMenuTap: () {}, waiting: waiting)),
      ),
    ),
  );
  await tester.pump();
  return updates;
}

MostroMascot _mascot(WidgetTester tester) => tester.widget<MostroMascot>(
  find.descendant(
    of: find.byType(TabAppBar),
    matching: find.byType(MostroMascot),
  ),
);

void main() {
  group('TabAppBar', () {
    testWidgets('centres the mascot, not the app name in text', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester);

        expect(_mascot(tester).interactive, isTrue);
        expect(find.text('Mostro'), findsNothing);
      });
    });

    testWidgets('still announces the app name, with nothing to tap', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final semantics = tester.ensureSemantics();
        await _pump(tester);

        final name = find.bySemanticsLabel('Mostro');
        expect(name, findsOneWidget);
        expect(
          tester.getSemantics(name),
          isNot(isSemantics(hasTapAction: true)),
        );

        semantics.dispose();
      });
    });

    testWidgets('menu and bell glyphs are 22 dp in every tab', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester);

        final menu = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.menu_rounded),
        );
        expect(menu.iconSize, 22);
        expect(
          tester
              .widget<NotificationBell>(find.byType(NotificationBell))
              .iconSize,
          22,
        );
      });
    });

    testWidgets('the mascot shuffles while the tab waits too long', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, waiting: true);
        expect(_mascot(tester).mood, MostroMood.neutral);

        await tester.pump(const Duration(seconds: 7));
        expect(_mascot(tester).mood, MostroMood.impatient);
      });
    });

    testWidgets('the mascot celebrates a completed trade', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final updates = await _pump(tester);

        updates.add(
          TradeUpdate(
            orderId: 'order-1',
            status: OrderStatus.success,
            occurredAt: _plainDay.millisecondsSinceEpoch ~/ 1000,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_mascot(tester).mood, MostroMood.celebrating);

        // The party is over once the celebration has played.
        await tester.pump(const Duration(seconds: 2));
        expect(_mascot(tester).mood, MostroMood.neutral);
      });
    });
  });
}
