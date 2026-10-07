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

  testWidgets('SimpleTradeTimeline does not call an untaken order accepted', (
    tester,
  ) async {
    Future<void> pump(OrderStatus status, {bool showBond = false}) =>
        tester.pumpWidget(
          MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SimpleTradeTimeline(
                status: status,
                isBuyer: true,
                showBond: showBond,
              ),
            ),
          ),
        );
    // The step in progress is the one drawn in bold.
    FontWeight? weight(String title) =>
        tester.widget<Text>(find.text(title)).style?.fontWeight;
    const waiting = 'Oferta publicada. Esperando a que alguien la tome';

    // On the book and nobody has taken it: that is the step under way, and
    // the escrow — which no seller exists yet to fund — is not.
    await pump(OrderStatus.pending);
    expect(find.text('Oferta aceptada'), findsNothing);
    expect(weight(waiting), FontWeight.bold);
    expect(weight('Bitcoin protegido en custodia'), isNot(FontWeight.bold));
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

    // A maker's deposit comes before the order is published: paid, it is
    // the step done, above the wait.
    await pump(OrderStatus.pending, showBond: true);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Garantía temporal bloqueada')).dy,
      lessThan(tester.getTopLeft(find.text(waiting)).dy),
    );
    expect(weight(waiting), FontWeight.bold);

    // Unpaid, it is the step under way and the order is not on the book.
    await pump(OrderStatus.waitingMakerBond, showBond: true);
    expect(find.text('Oferta aceptada'), findsNothing);
    expect(weight('Garantía temporal bloqueada'), FontWeight.bold);
    expect(weight(waiting), isNot(FontWeight.bold));

    // Taken, it reads as before.
    await pump(OrderStatus.waitingBuyerInvoice);
    expect(find.text('Oferta aceptada'), findsOneWidget);
    expect(find.text(waiting), findsNothing);
  });

  testWidgets('SimpleTradeTimeline makes room for a title of several lines', (
    tester,
  ) async {
    // A phone's width, where the test font — every glyph a square — breaks
    // the untaken order's title over more lines than any language will.
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SimpleTradeTimeline(
              status: OrderStatus.pending,
              isBuyer: true,
            ),
          ),
        ),
      ),
    );

    final title = find.text('Oferta publicada. Esperando a que alguien la tome');
    final next = find.text('Bitcoin protegido en custodia');
    // It did wrap: the rows used to be a fixed height, and the second line
    // ran into the step under it.
    expect(tester.getSize(title).height, greaterThan(30));
    expect(
      tester.getTopLeft(next).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
    );
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
