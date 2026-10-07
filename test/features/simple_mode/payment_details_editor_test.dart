import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/features/simple_mode/models/simple_order_rules.dart';
import 'package:mostro/features/simple_mode/providers/payment_details_providers.dart';
import 'package:mostro/features/simple_mode/widgets/payment_details_editor.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/fake_payment_details.dart';

Finder _field(String method) =>
    find.byKey(ValueKey('payment-details-field-${paymentMethodKey(method)}'));

Finder _tick(String method) =>
    find.byKey(ValueKey('payment-details-tick-${paymentMethodKey(method)}'));

String _text(WidgetTester tester, String method) =>
    tester.widget<TextField>(_field(method)).controller!.text;

/// What the editor last reported, and the methods it is asked for — both
/// changed from a test.
class _Host {
  _Host(List<String> methods) : methods = ValueNotifier(methods);

  final ValueNotifier<List<String>> methods;
  List<PaymentDetailsEntry> reported = const [];
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakePaymentDetailsGateway gateway,
  _Host host, {
  bool selectable = false,
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [paymentDetailsGatewayProvider.overrideWithValue(gateway)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: host.methods,
              builder:
                  (context, methods, _) => PaymentDetailsEditor(
                    methods: methods,
                    selectable: selectable,
                    onChanged: (entries) => host.reported = entries,
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  // The fields, then what the device keeps for them.
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  testWidgets('opens each field with what the device keeps for its method', (
    tester,
  ) async {
    final gateway = FakePaymentDetailsGateway(
      kept: {'banco pichincha': 'Ahorros 2201234567 · Ana P.'},
    );
    final host = _Host(['Banco Pichincha', 'De Una']);
    await _pump(tester, gateway, host);

    // Found whatever the spelling it was kept under.
    expect(_text(tester, 'Banco Pichincha'), 'Ahorros 2201234567 · Ana P.');
    expect(_text(tester, 'De Una'), isEmpty);
    expect(host.reported, const [
      PaymentDetailsEntry(
        method: 'Banco Pichincha',
        details: 'Ahorros 2201234567 · Ana P.',
      ),
      PaymentDetailsEntry(method: 'De Una', details: ''),
    ]);
    // Reading what is kept keeps nothing anew.
    expect(gateway.saves, isEmpty);
  });

  testWidgets('keeps what is typed once the field goes quiet', (tester) async {
    final gateway = FakePaymentDetailsGateway();
    final host = _Host(['De Una']);
    await _pump(tester, gateway, host);

    await tester.enterText(_field('De Una'), '099 123');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(_field('De Una'), '099 123 4567');
    // Reported at once, kept only after the pause: not once per keystroke.
    expect(host.reported.single.details, '099 123 4567');
    expect(gateway.saves, isEmpty);

    await tester.pump(kPaymentDetailsSaveDelay);
    expect(gateway.saves, [(method: 'De Una', details: '099 123 4567')]);
  });

  testWidgets('keeps what is pending when the field goes away', (tester) async {
    final gateway = FakePaymentDetailsGateway();
    final host = _Host(['De Una', 'Efectivo']);
    await _pump(tester, gateway, host);

    // The method leaves the list a moment after the last keystroke.
    await tester.enterText(_field('De Una'), '099 123 4567');
    host.methods.value = ['Efectivo'];
    await tester.pump();
    expect(_field('De Una'), findsNothing);
    expect(gateway.saves, [(method: 'De Una', details: '099 123 4567')]);
    expect(host.reported, const [
      PaymentDetailsEntry(method: 'Efectivo', details: ''),
    ]);

    // And the screen itself goes away.
    await tester.enterText(_field('Efectivo'), 'En persona, Quito norte');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(gateway.saves.last, (
      method: 'Efectivo',
      details: 'En persona, Quito norte',
    ));

    // The pause that would have kept them finds nothing left to keep.
    await tester.pump(kPaymentDetailsSaveDelay);
    expect(gateway.saves, hasLength(2));
  });

  testWidgets('a method that comes back finds what was typed for it', (
    tester,
  ) async {
    final gateway = FakePaymentDetailsGateway();
    final host = _Host(['De Una', 'Efectivo']);
    await _pump(tester, gateway, host);

    await tester.enterText(_field('De Una'), '099 123 4567');
    host.methods.value = ['Efectivo'];
    await tester.pump();
    // Back, and written the way the list now writes it.
    host.methods.value = ['Efectivo', 'DE UNA'];
    await tester.pump();
    await tester.pump();

    expect(_text(tester, 'DE UNA'), '099 123 4567');
  });

  testWidgets('what the device keeps does not overwrite what is being typed', (
    tester,
  ) async {
    final gateway = FakePaymentDetailsGateway(kept: {'De Una': '099 000 0000'});
    final host = _Host(['De Una']);
    // The read is still on its way when the seller starts typing.
    gateway.holdReads = Completer<void>();
    await _pump(tester, gateway, host);
    await tester.enterText(_field('De Una'), '098 765 4321');

    gateway.holdReads!.complete();
    await tester.pump();
    await tester.pump();

    expect(_text(tester, 'De Una'), '098 765 4321');
  });

  testWidgets('a tick leaves a method out of what is reported to send', (
    tester,
  ) async {
    final gateway = FakePaymentDetailsGateway(
      kept: {'Banco Pichincha': 'Ahorros 2201234567', 'De Una': '099 123 4567'},
    );
    final host = _Host(['Banco Pichincha', 'De Una']);
    await _pump(tester, gateway, host, selectable: true);

    expect(host.reported.every((entry) => entry.included), isTrue);

    await tester.tap(_tick('Banco Pichincha'));
    await tester.pump();

    expect(paymentDetailsToSend(host.reported), const [
      PaymentDetailsEntry(method: 'De Una', details: '099 123 4567'),
    ]);
    // Unticking is about this message, not about what the device keeps.
    expect(gateway.saves, isEmpty);
    expect(gateway.kept['banco pichincha'], 'Ahorros 2201234567');
  });

  testWidgets('shows no tick where there is nothing to choose', (tester) async {
    final gateway = FakePaymentDetailsGateway();
    final host = _Host(['De Una']);
    await _pump(tester, gateway, host);

    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('a method listed twice is one field', (tester) async {
    final gateway = FakePaymentDetailsGateway();
    final host = _Host(['De Una', 'de una ', 'Efectivo']);
    await _pump(tester, gateway, host);

    expect(find.byType(TextField), findsNWidgets(2));
    expect(host.reported.map((entry) => entry.method), ['De Una', 'Efectivo']);
  });

  testWidgets(
    "the previous identity's details leave the screen and are not kept again",
    (tester) async {
      final gateway = FakePaymentDetailsGateway(
        kept: {'De Una': '099 123 4567'},
      );
      final host = _Host(['De Una']);
      final container = await _pump(tester, gateway, host);
      expect(_text(tester, 'De Una'), '099 123 4567');

      // A keystroke is still waiting to be kept when the identity is
      // replaced: Rust erased the store, then the Dart half runs.
      await tester.enterText(_field('De Una'), '099 123 4567 · Ana P.');
      gateway.kept.clear();
      container.invalidate(paymentDetailsOwnerProvider);
      await tester.pump();
      await tester.pump();

      expect(_text(tester, 'De Una'), isEmpty);
      expect(host.reported, const [
        PaymentDetailsEntry(method: 'De Una', details: ''),
      ]);
      // The pending text would have landed in the next identity's store.
      await tester.pump(kPaymentDetailsSaveDelay);
      expect(gateway.saves, isEmpty);
      expect(gateway.kept, isEmpty);
    },
  );
}
