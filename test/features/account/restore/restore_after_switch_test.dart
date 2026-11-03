import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/restore/restore_after_switch.dart';
import 'package:mostro/features/account/restore/restore_run.dart';
import 'package:mostro/features/account/restore/restore_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

/// #813: a node switch restores the account on the new node, in the sheet
/// of Account → Refresh, except in privacy mode or when that is unknown.
void main() {
  late int recoveries;

  Future<void> switchNode(
    WidgetTester tester, {
    required Future<bool> Function() privacyMode,
  }) async {
    recoveries = 0;
    final steps = StreamController<RestoreProgress>.broadcast();
    addTearDown(steps.close);
    final answer = Completer<int>();
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restoreSummaryProvider.overrideWith(
            (ref) => const RestoreSummary(inProgress: 0, needsAction: 0),
          ),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed:
                          () => restoreAfterNodeSwitch(
                            context,
                            privacyMode: privacyMode,
                            run:
                                () => RestoreRun(
                                  progress: () async => steps.stream,
                                  recover: () {
                                    recoveries++;
                                    return answer.future;
                                  },
                                ),
                          ),
                      child: const Text('switched'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('switched'));
    // The running stage spins, so the tree never settles.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('opens the restore sheet and restores', (tester) async {
    await switchNode(tester, privacyMode: () async => false);

    expect(find.byType(RestoreSheet), findsOneWidget);
    expect(recoveries, 1);
  });

  testWidgets('restores nothing in privacy mode', (tester) async {
    await switchNode(tester, privacyMode: () async => true);

    expect(find.byType(RestoreSheet), findsNothing);
    expect(recoveries, 0);
  });

  testWidgets('restores nothing when privacy mode cannot be told', (
    tester,
  ) async {
    await switchNode(
      tester,
      privacyMode: () async => throw Exception('no identity'),
    );

    expect(find.byType(RestoreSheet), findsNothing);
    expect(recoveries, 0);
  });
}
