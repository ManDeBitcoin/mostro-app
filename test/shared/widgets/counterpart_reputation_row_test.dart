import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/shared/widgets/counterpart_reputation_row.dart';

/// Noon, 2026-01-01 UTC: the row's age is read against this.
final _now = DateTime.utc(2026, 1, 1, 12);

/// The one-row counterpart reputation of the trade screen (8b, 8c): the
/// grade on the avatar, the role, and the trades and age in one line. A
/// counterpart nobody has rated shows `New` rather than a fake 0.0.
void main() {
  final en = AppLocalizationsEn();

  Future<void> pump(
    WidgetTester tester, {
    required double rating,
    required int reviews,
    required DateTime since,
    required bool counterpartIsBuyer,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    await withClock(
      Clock.fixed(_now),
      () => tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
          home: Scaffold(
            body: CounterpartReputationRow(
              rating: rating,
              reviews: reviews,
              since: since,
              counterpartIsBuyer: counterpartIsBuyer,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a rated buyer: grade, role and the summary line', (
    tester,
  ) async {
    await pump(
      tester,
      rating: 4.8,
      reviews: 2,
      since: _now.subtract(const Duration(days: 1)),
      counterpartIsBuyer: true,
    );

    expect(find.text('4.8'), findsOneWidget);
    expect(find.text(en.tradeRoleBuyer), findsOneWidget);
    expect(find.text(en.reputationNew), findsNothing);
    expect(find.text('2 ratings · since Dec 2025'), findsOneWidget);
  });

  // The order book shows the same user at 4,97 (DS-L10N-5).
  testWidgets('the grade keeps its second decimal, as the order book does', (
    tester,
  ) async {
    await pump(
      tester,
      rating: 4.97,
      reviews: 687,
      since: DateTime.utc(2022, 5, 19),
      counterpartIsBuyer: true,
      locale: const Locale('es'),
    );

    expect(find.text('4,97'), findsOneWidget);
    expect(find.text('5.0'), findsNothing);
    expect(find.text('687 calificaciones · desde may 2022'), findsOneWidget);
  });

  testWidgets('groups a large ratings count for the locale', (tester) async {
    await pump(
      tester,
      rating: 4.97,
      reviews: 1323,
      since: DateTime.utc(2022, 5, 19),
      counterpartIsBuyer: true,
    );

    expect(find.text('1,323 ratings · since May 2022'), findsOneWidget);
  });

  // DS-A11Y-4: the invoice screens pad the row by AppSpacing.lg, so on a
  // 320 dp phone it is 288 wide. At 2× text a two-decimal grade (`4,97`) is
  // wider than the 34 dp circle that holds it.
  testWidgets('a two-decimal grade fits its circle at 2x text on 320 dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 - 2 * AppSpacing.lg, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      rating: 4.97,
      reviews: 1323,
      since: DateTime.utc(2022, 5, 19),
      counterpartIsBuyer: true,
      locale: const Locale('de'),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    // Laid out at its full width (not wrapped or clipped to the circle)...
    final paragraph = tester.renderObject<RenderParagraph>(find.text('4,97'));
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
    );
    // ...and drawn inside it.
    final grade = tester.getRect(find.text('4,97'));
    final circle = tester.getRect(
      find
          .ancestor(of: find.text('4,97'), matching: find.byType(Container))
          .first,
    );
    expect(circle.contains(grade.topLeft), isTrue, reason: '$grade in $circle');
    expect(
      circle.contains(grade.bottomRight - const Offset(0.01, 0.01)),
      isTrue,
      reason: '$grade in $circle',
    );
  });

  testWidgets('a seller nobody rated reads New instead of a grade', (
    tester,
  ) async {
    await pump(
      tester,
      rating: 0,
      reviews: 0,
      since: _now.subtract(const Duration(days: 12)),
      counterpartIsBuyer: false,
    );

    expect(find.text(en.reputationNew), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(find.text(en.tradeRoleSeller), findsOneWidget);
    expect(find.text('no ratings · since Dec 2025'), findsOneWidget);
  });

  test('highlightFigures styles every run of digits and nothing else', () {
    const strong = TextStyle(fontWeight: FontWeight.w500);
    final spans = highlightFigures('2 trades · 1,234 days', strong);

    expect(spans.map((s) => (s as TextSpan).text), [
      '2',
      ' trades · ',
      '1,234',
      ' days',
    ]);
    expect((spans[0] as TextSpan).style, strong);
    expect((spans[1] as TextSpan).style, isNull);
    expect((spans[2] as TextSpan).style, strong);
  });
}
