import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/widgets/simple_trade_timeline.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  testWidgets('SimpleTradeTimeline renders human milestones for active buyer',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SimpleTradeTimeline(
            status: OrderStatus.active,
            isBuyer: true,
            isDisputed: false,
            showBond: true,
          ),
        ),
      ),
    );

    // Milestones displayed
    expect(find.text('Oferta aceptada'), findsOneWidget);
    expect(find.text('Garantía temporal bloqueada'), findsOneWidget);
    expect(find.text('Bitcoin protegido en custodia'), findsOneWidget);
    expect(find.text('Envía el dinero fiat'), findsOneWidget);

    // No technical Nostr terms
    expect(find.text('waiting-buyer-invoice'), findsNothing);
    expect(find.text('waiting-server-payment'), findsNothing);
    expect(find.text('fiat-sent'), findsNothing);
  });

  testWidgets('SimpleTradeTimeline renders mediation steps when disputed',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SimpleTradeTimeline(
            status: OrderStatus.dispute,
            isBuyer: false,
            isDisputed: true,
          ),
        ),
      ),
    );

    expect(find.text('En mediación comunitaria'), findsOneWidget);
    expect(find.text('Caso recibido'), findsOneWidget);
    expect(find.text('Mediador de la comunidad asignado'), findsOneWidget);
    expect(find.text('Esperando resolución del mediador'), findsOneWidget);
  });

  testWidgets('SimpleTradeTimeline leaves the deposit step out without a bond',
      (tester) async {
    // On a node with bonds off the step used to show as already done.
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SimpleTradeTimeline(
            status: OrderStatus.active,
            isBuyer: true,
          ),
        ),
      ),
    );

    expect(find.text('Garantía temporal bloqueada'), findsNothing);
    expect(find.text('Bitcoin protegido en custodia'), findsOneWidget);
  });

  testWidgets('SimpleTradeTimeline does not count in-progress as secured',
      (tester) async {
    Future<int> doneSteps(OrderStatus status) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SimpleTradeTimeline(status: status, isBuyer: true),
          ),
        ),
      );
      return tester
          .widgetList(find.byIcon(Icons.check_circle_rounded))
          .length;
    }

    // The public book says `in-progress` from the take until the trade
    // ends: only "accepted" is known, the escrow is not.
    final taken = await doneSteps(OrderStatus.inProgress);
    final funded = await doneSteps(OrderStatus.active);
    expect(funded, greaterThan(taken));
  });
}
