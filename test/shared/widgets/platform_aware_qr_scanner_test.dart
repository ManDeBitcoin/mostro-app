import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';

void main() {
  testWidgets('PlatformAwareQrScanner renders camera and overlay initially',
      (tester) async {
    String? detectedValue;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlatformAwareQrScanner(
            onDetected: (value) => detectedValue = value,
          ),
        ),
      ),
    );

    expect(find.byType(PlatformAwareQrScanner), findsOneWidget);
    // Overlay instruction pill is present
    expect(find.text('Scan QR Code'), findsOneWidget);
    // Paste/manual button is present
    expect(find.text('Paste'), findsOneWidget);

    // Switch to manual mode
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    // Verify manual mode UI is rendered
    expect(find.text('Paste QR Code Content'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);

    // Enter text and submit
    await tester.enterText(find.byType(TextField), 'test_qr_code_123');
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(detectedValue, equals('test_qr_code_123'));
  });
}
