import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/widgets/simple_trade_timeline.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  testWidgets('SimpleTradeTimeline renders human milestones for active buyer',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        home: Scaffold(
          body: SimpleTradeTimeline(
            status: OrderStatus.active,
            isBuyer: true,
            isDisputed: false,
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
}
