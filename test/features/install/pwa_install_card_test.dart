import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/install/providers/pwa_install_provider.dart';
import 'package:mostro/features/install/widgets/pwa_install_card.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_de.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_pwa_install_bridge.dart';
import '../../support/provider_harness.dart';

final _en = AppLocalizationsEn();

/// The card on [platform], over [bridge], as the order book shows it.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakePwaInstallBridge bridge, {
  TargetPlatform platform = TargetPlatform.android,
  Locale locale = const Locale('en'),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  final container = createContainer(
    overrides: [
      pwaInstallBridgeProvider.overrideWithValue(bridge),
      pwaInstallPlatformProvider.overrideWithValue(platform),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme:
            brightness == Brightness.dark
                ? buildDarkTheme()
                : buildLightTheme(),
        locale: locale,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: PwaInstallCard()),
        ),
      ),
    ),
  );
  await container.read(pwaInstallProvider.notifier).loaded;
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PwaInstallCard (#778)', () {
    testWidgets('offers the install with a way out', (tester) async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);

      // Act
      await _pump(tester, bridge);

      // Assert
      expect(find.text(_en.pwaInstallTitle), findsOneWidget);
      expect(find.text(_en.pwaInstallBody), findsOneWidget);
      expect(find.text(_en.pwaInstallAction), findsOneWidget);
      expect(find.text(_en.pwaInstallNotNow), findsOneWidget);
    });

    testWidgets('is absent when there is nothing to offer', (tester) async {
      // Arrange — Firefox on Android: no install event.
      final bridge = FakePwaInstallBridge();

      // Act
      await _pump(tester, bridge);

      // Assert
      expect(find.text(_en.pwaInstallTitle), findsNothing);
    });

    testWidgets('Not now hides it for good', (tester) async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);
      await _pump(tester, bridge);

      // Act
      await tester.tap(find.text(_en.pwaInstallNotNow));
      await tester.pumpAndSettle();

      // Assert — nothing was installed, and the answer is on disk.
      expect(find.text(_en.pwaInstallTitle), findsNothing);
      expect(bridge.prompts, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPwaInstallAnsweredKey), isTrue);
    });

    testWidgets('Install on Android opens the browser dialog', (tester) async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);
      await _pump(tester, bridge);

      // Act
      await tester.tap(find.text(_en.pwaInstallAction));
      await tester.pumpAndSettle();

      // Assert
      expect(bridge.prompts, 1);
      expect(find.text(_en.pwaInstallTitle), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPwaInstallAnsweredKey), isTrue);
    });

    testWidgets('Install on iOS shows how to add it to the home screen', (
      tester,
    ) async {
      // Arrange
      final bridge = FakePwaInstallBridge();
      await _pump(tester, bridge, platform: TargetPlatform.iOS);

      // Act
      await tester.tap(find.text(_en.pwaInstallAction));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(_en.pwaInstallStepsTitle), findsOneWidget);
      expect(find.text(_en.pwaInstallStepShare), findsOneWidget);
      expect(find.text(_en.pwaInstallStepAdd), findsOneWidget);
      expect(bridge.prompts, 0);

      // And the sheet closes on its answer.
      await tester.tap(find.text(_en.pwaInstallStepsDone));
      await tester.pumpAndSettle();
      expect(find.text(_en.pwaInstallStepsTitle), findsNothing);
    });

    // DS-A11Y-4: German, 320 dp wide, text at 2×, both themes.
    for (final brightness in Brightness.values) {
      testWidgets('fits 320 dp in German at 2× text ($brightness)', (
        tester,
      ) async {
        // Arrange
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final de = AppLocalizationsDe();

        // Act
        await _pump(
          tester,
          FakePwaInstallBridge(),
          platform: TargetPlatform.iOS,
          locale: const Locale('de'),
          textScale: 2,
          brightness: brightness,
        );
        final cardError = tester.takeException();
        await tester.tap(find.text(de.pwaInstallAction));
        await tester.pumpAndSettle();

        // Assert
        expect(cardError, isNull);
        expect(tester.takeException(), isNull);
        expect(find.text(de.pwaInstallStepAdd), findsOneWidget);
      });
    }
  });
}
