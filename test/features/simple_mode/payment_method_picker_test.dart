import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/simple_mode/models/payment_details_rules.dart';
import 'package:mostro/features/simple_mode/models/payment_method_groups.dart';
import 'package:mostro/features/simple_mode/providers/community_provider.dart';
import 'package:mostro/features/simple_mode/providers/payment_method_providers.dart';
import 'package:mostro/features/simple_mode/screens/simple_buy_screen.dart';
import 'package:mostro/features/simple_mode/screens/simple_sell_screen.dart';
import 'package:mostro/features/simple_mode/widgets/payment_method_field.dart';
import 'package:mostro/features/simple_mode/widgets/simple_buy_confirm_sheet.dart';
import 'package:mostro/features/simple_mode/widgets/simple_sell_confirm_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;

import '../../support/load_app_fonts.dart';

/// The methods on the BitMaxis community's card, in the card's order, as
/// read from the node's relays on 2026-10-07.
const _bitmaxis = [
  'Banco Guayaquil',
  'Banco Pichincha',
  'USDT',
  'Banco del Pacífico',
  'Produbanco',
  'Banco Internacional',
  'Banco Bolivariano',
  'Banco del Austro',
  'Cooperativa JEP',
  'Deuna',
  'peiGo',
  'Payphone',
  'Efectivo (USD)',
  'Retiro sin tarjeta en cajero automático (ATM)',
];

/// What the picker lists; a test changes it to stand in for the card or the
/// book changing under an open picker.
final _groups = StateProvider<List<PaymentMethodGroup>>(
  (ref) => groupPaymentMethods(_bitmaxis),
);

final _ticked = StateProvider.autoDispose<Set<String>>((ref) => const {});

final _offers = Provider<Map<String, int>>(
  (ref) => const {'banco pichincha': 2, 'deuna': 1, 'usdt': 0},
);

Widget _app(
  Widget home, {
  List<Override> overrides = const [],
  bool light = false,
  double textScale = 1,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: light ? buildLightTheme() : buildDarkTheme(),
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // The reader's own text size, as the system hands it down.
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
    home: home,
  ),
);

/// A phone's screen, in logical pixels.
void _phone(WidgetTester tester, {double width = 360, double height = 760}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpField(WidgetTester tester, {bool offers = false}) async {
  // Tall enough for the whole list: what a test taps is on screen. How the
  // picker behaves on a screen it does not fit is checked on its own.
  _phone(tester, height: 1600);
  await tester.pumpWidget(
    _app(
      Scaffold(
        // In a scroll view, as on the tabs: the field is as tall as what it
        // holds.
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: PaymentMethodField(
            groups: _groups,
            ticked: _ticked,
            placeholder: 'Elige uno o varios',
            hint: 'Marca los que te sirvan.',
            offers: offers ? _offers : null,
          ),
        ),
      ),
    ),
  );
}

/// The field with nothing around it, for the tests that set their own
/// screen.
Widget _fieldAlone() => _app(
  Scaffold(
    // A keyboard that covers is the sheet's to deal with, not this page's.
    resizeToAvoidBottomInset: false,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: PaymentMethodField(
        groups: _groups,
        ticked: _ticked,
        placeholder: 'Elige uno o varios',
        hint: 'Marca los que te sirvan.',
      ),
    ),
  ),
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PaymentMethodField)));

/// Opens the picker by the field's heading, the way in.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chevron_right_rounded));
  await tester.pumpAndSettle();
}

/// The row of [method] in the open picker. The field under it writes a
/// ticked method too, so the picker's is the last in the tree.
Finder _row(String method) => find.text(method).last;

/// Whether the text [finder] finds ran out of lines before it ran out of
/// words.
bool _isCutShort(WidgetTester tester, Finder finder) =>
    tester
        .renderObject<RenderParagraph>(
          find.descendant(of: finder, matching: find.byType(RichText)),
        )
        .didExceedMaxLines;

/// The list of the open picker: what scrolls under its search box.
Finder get _list => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.byType(SingleChildScrollView),
);

/// The cross that empties the picker's search box.
Finder get _clearSearch => find.descendant(
  of: find.byType(TextField),
  matching: find.byIcon(Icons.close),
);

/// The picker's link that unticks everything.
TextButton _clearLink(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Quitar todos'));

CommunityProfile _card(List<String> methods) => CommunityProfile(
  version: 1,
  name: 'BitMaxis - Ecuador',
  pubkey: 'node',
  relays: const [],
  currency: 'USD',
  paymentMethods: methods,
  feeBps: 80,
  bondPercent: 5,
  signature: 'sig',
);

OrderItem _sell(String id, String method) => OrderItem(
  id: id,
  kind: 'sell',
  fiatAmount: 50,
  fiatCode: 'USD',
  paymentMethod: method,
  premium: 0,
  creatorPubkey: 'seller-$id',
  createdAt: DateTime.utc(2026),
  rating: 4.8,
  tradeCount: 128,
  daysActive: 365,
);

void main() {
  // The real fonts: what fits a phone is half of what is checked here, and
  // the test font draws every glyph as a square.
  setUpAll(loadAppFonts);

  group('PaymentMethodPickerSheet', () {
    testWidgets('lists every method under its heading, none ticked', (
      tester,
    ) async {
      await _pumpField(tester);
      expect(find.text('Elige uno o varios'), findsOneWidget);

      await _open(tester);

      expect(find.text('Métodos de pago'), findsOneWidget);
      expect(find.text('Marca los que te sirvan.'), findsOneWidget);
      // In the order of the headings, each one's methods in the card's.
      final shown = [
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Text),
          ),
        ))
          text.data ?? text.textSpan!.toPlainText(),
      ];
      expect(shown, [
        'Métodos de pago',
        // The search box, by what it says while it is empty.
        'Buscar métodos',
        'Marca los que te sirvan.',
        'BANCOS',
        'Todos',
        'Banco Guayaquil',
        'Banco Pichincha',
        'Banco del Pacífico',
        'Produbanco',
        'Banco Internacional',
        'Banco Bolivariano',
        'Banco del Austro',
        'COOPERATIVAS',
        'Cooperativa JEP',
        'BILLETERAS Y APPS',
        'Todos',
        'Deuna',
        'peiGo',
        'Payphone',
        'EFECTIVO',
        'Todos',
        'Efectivo (USD)',
        'Retiro sin tarjeta en cajero automático (ATM)',
        'CRIPTO',
        'USDT',
        'Quitar todos',
        'Listo',
      ]);
      expect(_container(tester).read(_ticked), isEmpty);
      // Nothing to clear yet: the link is in its place, and off.
      expect(_clearLink(tester).onPressed, isNull);
    });

    testWidgets('keeps its rows where they are when the first is ticked', (
      tester,
    ) async {
      // A list too short to fill the sheet: sized to what it holds, the
      // sheet would grow with whatever a tick adds, and move its rows up.
      await _pumpField(tester);
      _container(tester).read(_groups.notifier).state = groupPaymentMethods([
        'Banco Pichincha',
        'Deuna',
        'Efectivo (USD)',
      ]);
      await tester.pump();
      await _open(tester);
      final before = tester.getTopLeft(_row('Deuna'));

      await tester.tap(_row('Banco Pichincha'));
      await tester.pumpAndSettle();

      // The clear link is on now, and nothing moved: a second tap aimed at
      // a row still lands on it.
      expect(_clearLink(tester).onPressed, isNotNull);
      expect(tester.getTopLeft(_row('Deuna')), before);
    });

    testWidgets('a tick applies as it is made, and comes off the same way', (
      tester,
    ) async {
      await _pumpField(tester);
      await _open(tester);

      await tester.tap(_row('Banco Pichincha'));
      await tester.pump();
      // Written where the screen underneath reads it, with no button
      // pressed: there is no draft to confirm or to lose.
      expect(_container(tester).read(_ticked), {'banco pichincha'});
      expect(find.text('BANCOS  1 de 7'), findsOneWidget);
      expect(find.text('Listo · 1 elegido'), findsOneWidget);
      expect(find.text('1 elegido'), findsOneWidget);

      await tester.tap(_row('Banco Pichincha'));
      await tester.pump();
      expect(_container(tester).read(_ticked), isEmpty);
      expect(find.text('BANCOS'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('two taps inside one frame both count', (tester) async {
      await _pumpField(tester);
      await _open(tester);

      // No frame between them: each starts from what is ticked when it
      // lands. Starting from what the last frame drew, the second tap
      // would write a set without the first.
      await tester.tap(_row('Banco Guayaquil'));
      await tester.tap(_row('Banco Pichincha'));
      await tester.tap(_row('Deuna'));
      await tester.pump();

      expect(_container(tester).read(_ticked), {
        'banco guayaquil',
        'banco pichincha',
        'deuna',
      });
      expect(find.text('Listo · 3 elegidos'), findsOneWidget);
    });

    testWidgets('a heading ticks all of its methods, and unticks them', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpField(tester);
      await _open(tester);
      // One of another heading, to see that it is left alone.
      await tester.tap(_row('Banco Pichincha'));
      await tester.pump();

      await tester.tap(
        find.bySemanticsLabel('Marcar todos en Billeteras y apps'),
      );
      await tester.pump();
      expect(_container(tester).read(_ticked), {
        'banco pichincha',
        'deuna',
        'peigo',
        'payphone',
      });
      expect(find.text('BILLETERAS Y APPS  3 de 3'), findsOneWidget);

      // All ticked, the same control takes them off — and only them.
      expect(find.text('Ninguno'), findsOneWidget);
      await tester.tap(
        find.bySemanticsLabel('Desmarcar todos en Billeteras y apps'),
      );
      await tester.pump();
      expect(_container(tester).read(_ticked), {'banco pichincha'});
      expect(find.text('BILLETERAS Y APPS'), findsOneWidget);
      expect(find.text('Ninguno'), findsNothing);
      handle.dispose();
    });

    testWidgets('names the heading its control acts on, for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpField(tester);
      await _open(tester);

      expect(find.bySemanticsLabel('Marcar todos en Bancos'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Marcar todos en Billeteras y apps'),
        findsOneWidget,
      );
      // A heading with one method has nothing to tick at once.
      expect(
        find.bySemanticsLabel('Marcar todos en Cooperativas'),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('tells a screen reader what is ticked, and where', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpField(tester);
      await _open(tester);

      // A row is a checkbox, off.
      expect(
        tester.getSemantics(_row('Deuna')),
        isSemantics(
          label: 'Deuna',
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );
      // A heading is read as it is written, not as the capitals it is
      // drawn in.
      expect(find.bySemanticsLabel('Billeteras y apps'), findsOneWidget);
      expect(find.bySemanticsLabel('BILLETERAS Y APPS'), findsNothing);

      await tester.tap(_row('Deuna'));
      await tester.pump();

      expect(
        tester.getSemantics(_row('Deuna')),
        isSemantics(label: 'Deuna', isChecked: true),
      );
      expect(
        find.bySemanticsLabel('Billeteras y apps, 1 de 3'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a change is made to the ticks the user can see', (
      tester,
    ) async {
      await _pumpField(tester);
      // One on the list, and one whose method has left it: nothing shows
      // the second, so nothing could take it off.
      _container(tester).read(_ticked.notifier).state = {'deuna', 'zelle'};
      await tester.pump();
      await _open(tester);
      expect(find.text('Listo · 1 elegido'), findsOneWidget);

      await tester.tap(_row('USDT'));
      await tester.pump();

      // What they ticked is added to what they saw ticked. The unseen one
      // is gone, and does not come back with its method.
      expect(_container(tester).read(_ticked), {'deuna', 'usdt'});
      _container(tester).read(_groups.notifier).state = groupPaymentMethods([
        ..._bitmaxis,
        'Zelle',
      ]);
      await tester.pump();
      expect(find.text('Listo · 2 elegidos'), findsOneWidget);
    });

    testWidgets('keeps an unseen tick until the user changes theirs', (
      tester,
    ) async {
      await _pumpField(tester);
      _container(tester).read(_ticked.notifier).state = {'deuna', 'zelle'};
      await tester.pump();
      expect(find.text('1 elegido'), findsOneWidget);

      // The list takes the method back before the user touched anything:
      // it is still their choice.
      _container(tester).read(_groups.notifier).state = groupPaymentMethods([
        ..._bitmaxis,
        'Zelle',
      ]);
      await tester.pump();
      expect(find.text('2 elegidos'), findsOneWidget);
      expect(find.text('Zelle'), findsOneWidget);
    });

    testWidgets('holds a name of any length to three lines', (tester) async {
      await _pumpField(tester);
      // What a seller can type into an order, and the Buy tab then lists.
      final endless = List.filled(400, 'metodo').join(' ');
      _container(tester).read(_groups.notifier).state = groupPaymentMethods(
        ['Banco Pichincha'],
        onOffers: [endless],
      );
      await tester.pump();
      await _open(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_row(endless)).height, lessThan(80));
      // And the row under it is still on the screen.
      expect(find.text('Listo').hitTestable(), findsOneWidget);
    });

    testWidgets('clear all takes off every tick, seen or not', (tester) async {
      await _pumpField(tester);
      // One on the list, and one whose method has left it.
      _container(tester).read(_ticked.notifier).state = {'deuna', 'zelle'};
      await tester.pump();
      await _open(tester);
      expect(find.text('Listo · 1 elegido'), findsOneWidget);

      await tester.tap(find.text('Quitar todos'));
      await tester.pump();

      // Both: the hidden one would otherwise come back ticked with its
      // method.
      expect(_container(tester).read(_ticked), isEmpty);
      // And with nothing ticked there is nothing to clear.
      expect(_clearLink(tester).onPressed, isNull);
    });

    testWidgets('says how many offers take a method, where any does', (
      tester,
    ) async {
      await _pumpField(tester, offers: true);
      await _open(tester);

      expect(find.text('2 ofertas'), findsOneWidget);
      expect(find.text('1 oferta'), findsOneWidget);
      // None for a method, and a count of zero, say nothing.
      expect(find.text('Sin ofertas'), findsNothing);
      expect(find.textContaining('ofertas'), findsOneWidget);
    });

    testWidgets('follows the list while it is open', (tester) async {
      await _pumpField(tester);
      await _open(tester);
      await tester.tap(_row('Deuna'));
      await tester.tap(_row('USDT'));
      await tester.pump();
      expect(find.text('Listo · 2 elegidos'), findsOneWidget);

      // The operator drops Deuna and adds a bank, under the open picker.
      _container(tester).read(_groups.notifier).state = groupPaymentMethods([
        for (final method in _bitmaxis)
          if (method != 'Deuna') method,
        'Banco Machala',
      ]);
      await tester.pump();

      expect(find.text('Deuna'), findsNothing);
      expect(_row('Banco Machala'), findsOneWidget);
      // What is left ticked is what is still listed; nothing took the
      // place of the method that went.
      expect(find.text('Listo · 1 elegido'), findsOneWidget);
      expect(find.text('BILLETERAS Y APPS'), findsOneWidget);
      expect(find.text('CRIPTO  1 de 1'), findsOneWidget);
    });

    testWidgets('closes by its button, keeping what was ticked', (
      tester,
    ) async {
      await _pumpField(tester);
      await _open(tester);
      await tester.tap(_row('Produbanco'));
      await tester.pump();

      await tester.tap(find.text('Listo · 1 elegido'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('1 elegido'), findsOneWidget);
      expect(find.text('Produbanco'), findsOneWidget);
    });
  });

  group('PaymentMethodPickerSheet, the search box', () {
    Future<void> type(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
    }

    testWidgets('narrows the list to what is typed', (tester) async {
      await _pumpField(tester);
      await _open(tester);

      // Whatever the case, and without the accent the name is written with.
      await type(tester, 'PACIFICO');

      expect(_row('Banco del Pacífico'), findsOneWidget);
      for (final other in ['Banco Pichincha', 'Deuna', 'USDT']) {
        expect(find.text(other), findsNothing, reason: other);
      }
      // Only the heading that still has a method under it.
      expect(find.text('BANCOS'), findsOneWidget);
      expect(find.text('CRIPTO'), findsNothing);
      // And the line that explains ticking gives its room to what was
      // found.
      expect(find.text('Marca los que te sirvan.'), findsNothing);
    });

    testWidgets('shows a heading as a name while it shows part of it', (
      tester,
    ) async {
      await _pumpField(tester);
      await _open(tester);
      await tester.tap(_row('Banco Pichincha'));
      await tester.pump();
      expect(find.text('BANCOS  1 de 7'), findsOneWidget);
      expect(find.text('Todos'), findsNWidgets(3));

      // Three of the seven banks, one of them ticked.
      await type(tester, 'banco p');

      expect(_row('Banco Pichincha'), findsOneWidget);
      expect(_row('Banco del Pacífico'), findsOneWidget);
      expect(_row('Produbanco'), findsOneWidget);
      // How many are ticked, and the control that ticks them all, are about
      // the whole heading: over three of seven they would say "1 de 3", and
      // tick three.
      expect(find.text('BANCOS'), findsOneWidget);
      expect(find.textContaining('1 de'), findsNothing);
      expect(find.text('Todos'), findsNothing);
      expect(find.text('Ninguno'), findsNothing);
    });

    testWidgets('finds a method by the heading it is under', (tester) async {
      await _pumpField(tester);
      await _open(tester);

      await type(tester, 'billeteras');

      for (final wallet in ['Deuna', 'peiGo', 'Payphone']) {
        expect(_row(wallet), findsOneWidget, reason: wallet);
      }
      expect(find.text('Banco Pichincha'), findsNothing);
    });

    testWidgets('says so when nothing is found, and clears back', (
      tester,
    ) async {
      await _pumpField(tester);
      await _open(tester);

      await type(tester, '  nequi ');
      expect(find.text('Ningún método coincide con «nequi».'), findsOneWidget);
      expect(find.text('BANCOS'), findsNothing);

      // The cross is there once something is typed, and gives the whole
      // list back.
      await tester.tap(_clearSearch);
      await tester.pump();
      expect(find.textContaining('Ningún método'), findsNothing);
      expect(_row('Banco Pichincha'), findsOneWidget);
      expect(_row('USDT'), findsOneWidget);
      expect(find.text('Marca los que te sirvan.'), findsOneWidget);
      expect(_clearSearch, findsNothing);
    });

    testWidgets('keeps the ticks it hides', (tester) async {
      await _pumpField(tester);
      await _open(tester);
      await tester.tap(_row('Deuna'));
      await tester.pump();

      // Deuna is out of sight, and still ticked: the button counts it, and
      // a tick made on what was found is added to it.
      await type(tester, 'pichincha');
      expect(find.text('Deuna'), findsOneWidget, reason: 'the chip under it');
      expect(find.text('Listo · 1 elegido'), findsOneWidget);
      await tester.tap(_row('Banco Pichincha'));
      await tester.pump();

      expect(_container(tester).read(_ticked), {'deuna', 'banco pichincha'});
      expect(find.text('Listo · 2 elegidos'), findsOneWidget);

      // "Clear all" is all of them, the hidden one too.
      await tester.tap(find.text('Quitar todos'));
      await tester.pump();
      expect(_container(tester).read(_ticked), isEmpty);
    });

    testWidgets('has one height, whatever is found', (tester) async {
      await _pumpField(tester);
      await _open(tester);
      final sheet = tester.getRect(find.byType(BottomSheet));
      final box = tester.getRect(find.byType(TextField));

      // Sized to its content, the sheet would shrink to one row and carry
      // the box being typed in down the screen.
      for (final query in ['pichincha', 'nequi', '', 'banco']) {
        await type(tester, query);
        expect(tester.getRect(find.byType(BottomSheet)), sheet, reason: query);
        expect(tester.getRect(find.byType(TextField)), box, reason: query);
      }
      // Most of the screen, not all of it: what is left above says it is a
      // sheet, and closes it when tapped.
      expect(sheet.top, greaterThan(60));
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('stays where it is while the list scrolls under it', (
      tester,
    ) async {
      // A phone the list does not fit.
      _phone(tester, height: 640);
      await tester.pumpWidget(_fieldAlone());
      await _open(tester);
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(TextField));

      await tester.drag(_list, const Offset(0, -2000));
      await tester.pumpAndSettle();

      // The end of the list is on screen, and the title and the box are
      // where they were.
      expect(_row('USDT').hitTestable(), findsOneWidget);
      expect(_row('Banco Guayaquil').hitTestable(), findsNothing);
      expect(find.text('Métodos de pago').hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byType(TextField)), box);

      // Nor does it move when what it finds is short enough to need no
      // scrolling at all.
      await type(tester, 'usdt');
      expect(_row('USDT').hitTestable(), findsOneWidget);
      expect(find.text('Banco Bolivariano'), findsNothing);
      expect(tester.getRect(find.byType(TextField)), box);
    });

    testWidgets('gives its room to the list in a short window', (tester) async {
      // A phone on its side, or a small browser window: no keyboard, and
      // little height to begin with.
      _phone(tester, height: 340);
      await tester.pumpWidget(_fieldAlone());
      await _open(tester);

      expect(tester.takeException(), isNull);
      // The title and the clear link are left out; the button is not.
      expect(find.text('Métodos de pago'), findsNothing);
      expect(find.text('Quitar todos'), findsNothing);
      expect(find.text('Listo').hitTestable(), findsOneWidget);
      // So the box is in reach, with rows to read under it.
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(_row('Banco Guayaquil').hitTestable(), findsOneWidget);
      expect(_row('Banco Pichincha').hitTestable(), findsOneWidget);
    });

    testWidgets('keeps its button in the shortest window', (tester) async {
      // A phone's browser on its side. With no keyboard up, nothing would
      // bring a button back that was left out.
      _phone(tester, width: 640, height: 280);
      await tester.pumpWidget(_fieldAlone());
      await _open(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Listo').hitTestable(), findsOneWidget);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('gives its room to the list while a keyboard is up', (
      tester,
    ) async {
      // An ordinary phone. The keyboard leaves more than half of it in
      // sight, and takes the foot of the sheet all the same.
      _phone(tester, height: 800);
      await tester.pumpWidget(_fieldAlone());
      await _open(tester);
      expect(find.text('Métodos de pago'), findsOneWidget);
      expect(find.text('Quitar todos'), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 290);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Métodos de pago'), findsNothing);
      expect(find.text('Quitar todos'), findsNothing);
      // The button, the box and three rows, all above the keyboard.
      for (final finder in [
        find.text('Listo'),
        find.byType(TextField),
        _row('Banco Guayaquil'),
        _row('Banco Pichincha'),
        _row('Banco del Pacífico'),
      ]) {
        expect(finder.hitTestable(), findsOneWidget);
        expect(tester.getBottomLeft(finder).dy, lessThanOrEqualTo(800 - 290));
      }

      // And all of it is back when the keyboard goes.
      tester.view.resetViewInsets();
      await tester.pump();
      expect(find.text('Métodos de pago'), findsOneWidget);
      expect(find.text('Quitar todos'), findsOneWidget);
    });

    testWidgets('keeps the box it was typing in when the keyboard comes', (
      tester,
    ) async {
      // A phone's browser: some 560 of its 640 are the page's, and the
      // keyboard takes 290 of those in one step. Title and button both go
      // in that one frame, from either side of the box.
      _phone(tester, height: 560);
      await tester.pumpWidget(_fieldAlone());
      await _open(tester);
      await tester.drag(_list, const Offset(0, -120));
      await tester.pumpAndSettle();
      final scrolled = tester.getTopLeft(_row('Produbanco'));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final box = tester.state<EditableTextState>(find.byType(EditableText));
      expect(box.widget.focusNode.hasFocus, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 290);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();

      // Only a strip is in sight: the title and the button are gone.
      expect(tester.takeException(), isNull);
      expect(find.text('Métodos de pago'), findsNothing);
      expect(find.text('Listo'), findsNothing);
      // The box is the same box, and still has the focus. Built anew it
      // would have none: the keyboard would leave, the sheet would go back
      // to what it was, and no letter could ever be typed.
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(box),
      );
      expect(box.widget.focusNode.hasFocus, isTrue);
      // And the list is the same list, where the user left it — nearer the
      // top of the screen by the title that went, and no further scrolled.
      expect(tester.getTopLeft(_row('Produbanco')).dy, lessThan(scrolled.dy));
      expect(_row('Banco Guayaquil').hitTestable(), findsNothing);

      await type(tester, 'produ');
      expect(_row('Produbanco').hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(_row('Produbanco')).dy,
        lessThanOrEqualTo(560 - 290),
      );
    });

    testWidgets('keeps the box and a row above a keyboard that covers', (
      tester,
    ) async {
      // A small phone with its keyboard already up: what is left in sight
      // is a strip.
      _phone(tester, height: 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(_fieldAlone());
      await _open(tester);

      expect(tester.takeException(), isNull);
      // The button goes too: the strip is for the box and what it finds,
      // and both are above the keyboard.
      expect(find.text('Listo'), findsNothing);
      for (final finder in [find.byType(TextField), _row('Banco Guayaquil')]) {
        expect(finder.hitTestable(), findsOneWidget);
        expect(tester.getBottomLeft(finder).dy, lessThanOrEqualTo(568 - 300));
      }

      // So is the end of the list, once scrolled to: the sheet stops where
      // the keyboard starts, and does not run on underneath it.
      await tester.drag(_list, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(_row('USDT').hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(_row('USDT')).dy,
        lessThanOrEqualTo(568 - 300),
      );
    });

    testWidgets('holds on a phone on its side with the keyboard up', (
      tester,
    ) async {
      // A tall keyboard for a screen this short: a hundred and ten pixels
      // are left, and the sheet takes all of them.
      _phone(tester, width: 640, height: 360);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(_fieldAlone());
      await _open(tester);

      // Nothing runs off it, and the box can be typed in and seen.
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        lessThanOrEqualTo(360 - 250),
      );
    });

    testWidgets('says what it is for, and when it finds nothing', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpField(tester);
      await _open(tester);

      // Named for a screen reader, once, while it is empty…
      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(label: 'Buscar métodos', isTextField: true),
      );
      // …and with something typed, when the hint that said so on screen is
      // gone.
      await type(tester, 'nequi');
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(label: 'Buscar métodos', isTextField: true, value: 'nequi'),
      );
      // And the word that the list is empty is announced when it comes.
      expect(
        tester.getSemantics(find.textContaining('Ningún método')),
        isSemantics(isLiveRegion: true),
      );
      handle.dispose();
    });

    testWidgets('takes a query no longer than a name can be', (tester) async {
      await _pumpField(tester);
      await _open(tester);

      // What is typed is said back when nothing matches it.
      await type(tester, List.filled(40, 'metodo').join(' '));

      final typed =
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(typed.length, 60);
      expect(tester.takeException(), isNull);
    });
  });

  group('PaymentMethodField', () {
    testWidgets('unticks a method by its chip, without opening the picker', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpField(tester);
      // Two on the list, and one whose method has left it.
      _container(tester).read(_ticked.notifier).state = {
        'deuna',
        'usdt',
        'zelle',
      };
      await tester.pump();
      expect(find.text('2 elegidos'), findsOneWidget);

      // The whole chip takes the tap, and is tall enough to be hit.
      final chip = find.bySemanticsLabel('Quitar Deuna');
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(40));
      await tester.tapAt(tester.getTopLeft(chip) + const Offset(14, 8));
      await tester.pump();

      expect(find.byType(BottomSheet), findsNothing);
      // The method tapped, and the tick the user could not see.
      expect(_container(tester).read(_ticked), {'usdt'});
      expect(find.text('Deuna'), findsNothing);
      expect(find.text('USDT'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('opens the picker from its heading only', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpField(tester);
      _container(tester).read(_ticked.notifier).state = {'usdt'};
      await tester.pump();

      // Beside the chip there is nothing to tap: a finger that missed the
      // chip used to open the picker instead.
      final chips = find.byType(Wrap);
      await tester.tapAt(tester.getBottomRight(chips) - const Offset(6, 6));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(_container(tester).read(_ticked), {'usdt'});

      // The heading is the way in, and says so to a screen reader.
      expect(
        tester.getSemantics(find.text('1 elegido')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('1 elegido'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      handle.dispose();
    });

    testWidgets('fits large text and the light theme', (tester) async {
      _phone(tester, height: 1600);
      await tester.pumpWidget(
        _app(
          light: true,
          // What a reader with the system's largest text gets.
          textScale: 2,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: PaymentMethodField(
                groups: _groups,
                ticked: _ticked,
                placeholder: 'Elige uno o varios',
                hint: 'Marca los que te sirvan.',
                offers: _offers,
              ),
            ),
          ),
        ),
      );
      _container(tester).read(_ticked.notifier).state = {
        for (final method in _bitmaxis) method.toLowerCase(),
      };
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('14 elegidos'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Listo · 14 elegidos').hitTestable(), findsOneWidget);
    });

    testWidgets("holds the community's whole list on a small phone", (
      tester,
    ) async {
      _phone(tester, width: 320, height: 568);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: PaymentMethodField(
                groups: _groups,
                ticked: _ticked,
                placeholder: 'Elige uno o varios',
                hint: 'Marca los que te sirvan.',
                offers: _offers,
              ),
            ),
          ),
        ),
      );
      // Every method ticked: the longest name is wider than the field.
      _container(tester).read(_ticked.notifier).state = {
        for (final method in _bitmaxis) method.toLowerCase(),
      };
      await tester.pump();
      expect(find.text('14 elegidos'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // And the picker over it: taller than the screen, so it scrolls,
      // with its button always in reach.
      await tester.tap(find.text('14 elegidos'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Listo · 14 elegidos'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      // Its last row is reached by scrolling, not cut off.
      await tester.tap(find.text('14 elegidos'));
      await tester.pumpAndSettle();
      expect(_row('USDT').hitTestable(), findsNothing);
      await tester.drag(_list, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(_row('USDT'));
      await tester.pump();
      expect(find.text('Listo · 13 elegidos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('several methods on a phone', () {
    // An offer that takes most of the community's list, from a seller with
    // a long record: the widest every line of its card gets.
    final book = [
      _sell('a', _bitmaxis.take(9).join(', ')),
      _sell('b', 'Banco Pichincha'),
    ];

    List<Override> overrides() => [
      activeCommunityProfileProvider.overrideWith(
        (ref) => ActiveCommunityNotifier(read: () async => _card(_bitmaxis)),
      ),
      orderBookProvider.overrideWith((ref) => Stream.value(book)),
      mostroNodeProvider.overrideWith((ref) async => null),
    ];

    testWidgets("the Buy tab writes out an offer's methods", (tester) async {
      _phone(tester, height: 1600);
      await tester.pumpWidget(
        _app(const Scaffold(body: SimpleBuyScreen()), overrides: overrides()),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Whole, on lines of their own: beside the button there was room for
      // the first of them and an ellipsis.
      final methods = find.textContaining('Pago: Banco Guayaquil');
      expect(
        tester.widget<Text>(methods).data,
        'Pago: ${_bitmaxis.take(9).join(', ')}',
      );
      expect(
        tester.getSize(methods).height,
        greaterThan(40),
        reason: 'more than one line',
      );
      expect(_isCutShort(tester, methods), isFalse);
    });

    testWidgets("an offer's card holds the community's whole list", (
      tester,
    ) async {
      // The narrowest phone, and an offer that takes every method.
      _phone(tester, width: 320, height: 1600);
      await tester.pumpWidget(
        _app(
          const Scaffold(body: SimpleBuyScreen()),
          overrides: [
            activeCommunityProfileProvider.overrideWith(
              (ref) =>
                  ActiveCommunityNotifier(read: () async => _card(_bitmaxis)),
            ),
            orderBookProvider.overrideWith(
              (ref) => Stream.value([_sell('all', _bitmaxis.join(', '))]),
            ),
            mostroNodeProvider.overrideWith((ref) async => null),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        _isCutShort(tester, find.textContaining('Pago: Banco Guayaquil')),
        isFalse,
      );
    });

    testWidgets("an offer's card is not as long as its seller writes it", (
      tester,
    ) async {
      _phone(tester, height: 1600);
      final endless = List.filled(400, 'metodo').join(' ');
      await tester.pumpWidget(
        _app(
          const Scaffold(body: SimpleBuyScreen()),
          overrides: [
            orderBookProvider.overrideWith(
              (ref) => Stream.value([_sell('long', endless)]),
            ),
            mostroNodeProvider.overrideWith((ref) async => null),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      final methods = find.textContaining('Pago: metodo');
      expect(_isCutShort(tester, methods), isTrue);
      expect(tester.getSize(methods).height, lessThan(200));
    });

    testWidgets('the Sell tab holds every method ticked', (tester) async {
      _phone(tester, height: 1700);
      await tester.pumpWidget(
        _app(
          const Scaffold(body: SimpleSellScreen()),
          overrides: [
            ...overrides(),
            sellTickedMethodsProvider.overrideWith(
              (ref) => {for (final method in _bitmaxis) method.toLowerCase()},
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('14 elegidos'), findsOneWidget);
    });

    testWidgets('the sale summary fits them, and scrolls to its button', (
      tester,
    ) async {
      _phone(tester, height: 568);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SimpleSellConfirmSheet(
                fiatAmount: 100,
                fiatCode: 'USD',
                paymentMethods: _bitmaxis,
                paymentDetails: [
                  PaymentDetailsEntry(
                    method: 'Banco Pichincha',
                    details:
                        'Cuenta de ahorros 2201234567 a nombre de Juan Pérez, '
                        'cédula 1712345678',
                  ),
                ],
                premium: 2,
                estimatedSats: 115700,
              ),
            ),
          ),
          overrides: overrides(),
        ),
      );
      await tester.pump();
      await tester.pump();

      // A value that could not wrap ran off the sheet's edge; a sheet that
      // could not scroll ran off its bottom.
      expect(tester.takeException(), isNull);
      expect(find.text(_bitmaxis.join('\n')), findsOneWidget);
      await tester.ensureVisible(find.text('CONFIRMAR Y PUBLICAR'));
      await tester.pump();
      expect(find.text('CONFIRMAR Y PUBLICAR').hitTestable(), findsOneWidget);
    });

    testWidgets('the purchase summary fits them, and scrolls to its button', (
      tester,
    ) async {
      _phone(tester, height: 568);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SimpleBuyConfirmSheet(
                order: _sell('a', _bitmaxis.join(', ')),
                fiatAmount: 50,
                fiatCode: 'USD',
                estimatedSats: 59027,
              ),
            ),
          ),
          overrides: overrides(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      // One to a line, under a label that says there are several.
      expect(find.text('Métodos de pago'), findsOneWidget);
      expect(find.text(_bitmaxis.join('\n')), findsOneWidget);
      await tester.ensureVisible(find.text('CONFIRMAR Y COMPRAR'));
      await tester.pump();
      expect(find.text('CONFIRMAR Y COMPRAR').hitTestable(), findsOneWidget);
    });

    testWidgets('a summary of one method says so', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SimpleBuyConfirmSheet(
                order: _sell('b', 'Banco Pichincha'),
                fiatAmount: 50,
                fiatCode: 'USD',
                estimatedSats: 59027,
              ),
            ),
          ),
          overrides: overrides(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Método de pago'), findsOneWidget);
      expect(find.text('Métodos de pago'), findsNothing);
      expect(find.text('Banco Pichincha'), findsOneWidget);
    });
  });
}
