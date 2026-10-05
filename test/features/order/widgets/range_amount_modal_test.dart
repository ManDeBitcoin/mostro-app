import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/range_amount_modal.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// What the dialog resolved to: [_unset] until it closes, then the amount
/// (or null for a cancel).
const _unset = -1.0;

/// Opens the dialog for a 100–200 USD range order and returns a reader for
/// what it resolved to.
Future<double? Function()> _open(WidgetTester tester) async {
  double? result = _unset;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showRangeAmountModal(
                context: context,
                min: 100,
                max: 200,
                currencyCode: 'USD',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

FilledButton _submit(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Submit'));

const _whole = 'Enter a whole amount: digits only, no decimals or separators.';

void main() {
  group('range amount dialog', () {
    testWidgets('takes a whole amount inside the range', (tester) async {
      final result = await _open(tester);
      expect(_submit(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();
      expect(find.text(_whole), findsNothing);
      expect(_submit(tester).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();
      expect(result(), 150);
    });

    testWidgets('keeps a typed separator on screen and says why it will not do', (
      tester,
    ) async {
      final result = await _open(tester);

      // A digits-only field dropped the separator and kept the rest: `15.0`
      // became 150 — inside this range, with Submit enabled.
      for (final typed in ['15.0', '150.5', '150,5']) {
        await tester.enterText(find.byType(TextField), typed);
        await tester.pump();
        expect(find.text(typed), findsOneWidget, reason: typed);
        expect(find.text(_whole), findsOneWidget, reason: typed);
        expect(_submit(tester).onPressed, isNull, reason: typed);
      }

      // Tapping the dead button takes nothing: the dialog is still open.
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();
      expect(result(), _unset);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('lets through digits and the two separators, nothing else', (
      tester,
    ) async {
      await _open(tester);

      // No sign, no hex, no letters: `int.tryParse` would read `0x96` as 150.
      await tester.enterText(find.byType(TextField), '+0x96 a');
      await tester.pump();
      expect(find.text('096'), findsOneWidget);
      expect(_submit(tester).onPressed, isNull);
    });

    testWidgets('says nothing about an empty field', (tester) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), '150.5');
      await tester.pump();
      expect(find.text(_whole), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text(_whole), findsNothing);
      expect(_submit(tester).onPressed, isNull);
    });

    testWidgets('still refuses a whole amount outside the range', (
      tester,
    ) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), '250');
      await tester.pump();
      expect(find.text('Amount must be between 100 and 200'), findsOneWidget);
      expect(find.text(_whole), findsNothing);
      expect(_submit(tester).onPressed, isNull);
    });
  });
}
