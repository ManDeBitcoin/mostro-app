import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/reputation_age.dart';

import '../../support/fake_trades.dart';

/// 2023-11-14 00:00:00 UTC, a day start as the daemon publishes `since`.
const _since = 1699920000;
final _sinceDate = DateTime.utc(2023, 11, 14);

/// 64 days and a half after [_sinceDate].
final _now = DateTime.utc(2024, 1, 17, 12);

void main() {
  group('reputationSince', () {
    test('converts Unix seconds to a UTC date', () {
      // Act
      final since = reputationSince(_since);

      // Assert
      expect(since, _sinceDate);
      expect(since!.isUtc, isTrue);
    });

    test('accepts the BigInt the bridge hands over on web', () {
      expect(reputationSince(BigInt.from(_since)), _sinceDate);
    });

    test('returns null when the daemon sent no since', () {
      expect(reputationSince(null), isNull);
    });
  });

  group('firstTradeDay', () {
    test('is the daemon\'s since, whatever the stale day count says', () {
      final day = withClock(
        Clock.fixed(_now),
        () => firstTradeDay(_sinceDate, fallbackDays: 10),
      );

      expect(day, _sinceDate);
    });

    test('counts the day count back from now when since is absent', () {
      final day = withClock(
        Clock.fixed(_now),
        () => firstTradeDay(null, fallbackDays: 10),
      );

      expect(day, _now.subtract(const Duration(days: 10)));
    });
  });

  group('reputationSinceText', () {
    // The app's Localizations load each locale's date data; a bare test
    // does it by hand.
    setUpAll(initializeDateFormatting);

    test('reads as the month of the first trade, for the locale', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final es = await AppLocalizations.delegate.load(const Locale('es'));

      expect(reputationSinceText(en, _sinceDate), 'since Nov 2023');
      expect(reputationSinceText(es, _sinceDate), 'desde nov 2023');
    });
  });

  group('TradeInfo.peerFirstTrade', () {
    test('prefers peerSince over the stale peerDays', () {
      final trade = fakeTrade(peerDays: 10, peerSince: _since);

      final day = withClock(Clock.fixed(_now), () => trade.peerFirstTrade);

      expect(day, _sinceDate);
    });

    test('falls back to peerDays from a daemon without since', () {
      final trade = fakeTrade(peerDays: 10);

      final day = withClock(Clock.fixed(_now), () => trade.peerFirstTrade);

      expect(day, _now.subtract(const Duration(days: 10)));
    });

    test('is today when the trade carries no reputation at all', () {
      final day = withClock(
        Clock.fixed(_now),
        () => fakeTrade().peerFirstTrade,
      );

      expect(day, _now);
    });
  });
}
