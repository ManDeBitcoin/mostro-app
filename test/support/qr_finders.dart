import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/widgets/mostro_qr.dart';

/// Asserts that the one [MostroQr] on screen is as wide as the column it
/// stands in — a card's inside, a dialog's content — the way a wallet shows
/// a long invoice or token: a small code is a hard scan.
void expectQrTakesItsWidth(WidgetTester tester) {
  final qr = find.byType(MostroQr);
  expect(qr, findsOneWidget);
  final column = find.ancestor(of: qr, matching: find.byType(Column)).first;
  final room = tester.getSize(column).width;
  expect(tester.getSize(qr), Size.square(room));
}
