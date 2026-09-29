import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/l10n/simple_l10n.dart';

void main() {
  const supported = ['en', 'es', 'fr', 'de', 'it', 'nl'];

  for (final lang in supported) {
    testWidgets('SimpleL10n provides all strings in $lang', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(lang),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Verify all 5 navigation strings exist and are non-empty
      expect(SimpleL10n.navBuy(capturedContext), isNotEmpty);
      expect(SimpleL10n.navSell(capturedContext), isNotEmpty);
      expect(SimpleL10n.navTrades(capturedContext), isNotEmpty);
      expect(SimpleL10n.navProfile(capturedContext), isNotEmpty);
      expect(SimpleL10n.navHelp(capturedContext), isNotEmpty);

      // Verify mode switching strings
      expect(SimpleL10n.simpleMode(capturedContext), isNotEmpty);
      expect(SimpleL10n.advancedMode(capturedContext), isNotEmpty);
      expect(SimpleL10n.switchToSimple(capturedContext), isNotEmpty);
      expect(SimpleL10n.switchToAdvanced(capturedContext), isNotEmpty);
      expect(SimpleL10n.advancedModeDesc(capturedContext), isNotEmpty);

      // Verify community strings
      expect(SimpleL10n.communityVerified(capturedContext), isNotEmpty);
      expect(SimpleL10n.generalMarket(capturedContext), isNotEmpty);
      expect(SimpleL10n.scanCommunityQr(capturedContext), isNotEmpty);

      // Verify buy & sell flows
      expect(SimpleL10n.howMuchBuy(capturedContext), isNotEmpty);
      expect(SimpleL10n.selectPaymentMethod(capturedContext), isNotEmpty);
      expect(SimpleL10n.viewOffers(capturedContext), isNotEmpty);
      expect(SimpleL10n.temporaryGuarantee(capturedContext), isNotEmpty);
      expect(SimpleL10n.howMuchSell(capturedContext), isNotEmpty);
      expect(SimpleL10n.selectReceiveMethod(capturedContext), isNotEmpty);
      expect(SimpleL10n.publishOffer(capturedContext), isNotEmpty);

      // Verify help strings
      expect(SimpleL10n.helpTitle(capturedContext), isNotEmpty);
      expect(SimpleL10n.haveProblem(capturedContext), isNotEmpty);
      expect(SimpleL10n.requestHelp(capturedContext), isNotEmpty);
      expect(SimpleL10n.faq1Q(capturedContext), isNotEmpty);
      expect(SimpleL10n.faq1A(capturedContext), isNotEmpty);
      expect(SimpleL10n.faq2Q(capturedContext), isNotEmpty);
      expect(SimpleL10n.faq2A(capturedContext), isNotEmpty);
    });
  }
}
