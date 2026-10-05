import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/widgets/underline_amount_field.dart';

String _format(ThousandsInputFormatter f, String typed) =>
    f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: typed)).text;

void main() {
  const es = ThousandsInputFormatter(groupSeparator: '.', decimalSeparator: ',');
  const en = ThousandsInputFormatter(groupSeparator: ',', decimalSeparator: '.');
  const ints = ThousandsInputFormatter(
    groupSeparator: '.',
    decimalSeparator: ',',
    allowDecimals: false,
  );

  group('ThousandsInputFormatter', () {
    test('groups the integer part with the locale separator', () {
      expect(_format(es, '25000'), '25.000');
      expect(_format(en, '1234567'), '1,234,567');
    });

    test('regroups text that already carries separators', () {
      expect(_format(es, '2.50.0'), '2.500');
      expect(_format(en, '1,2345'), '12,345');
    });

    test('only the locale decimal separator is a decimal', () {
      expect(_format(es, '1000,5'), '1.000,5');
      expect(_format(en, '1000.5'), '1,000.5');
      // The other locale's decimal mark is this locale's group mark: a pasted
      // grouped figure keeps its magnitude.
      expect(_format(es, '25.000'), '25.000');
      expect(_format(en, '25,000'), '25,000');
    });

    test('keeps one decimal separator and at most two decimals', () {
      expect(_format(es, '1,2,3'), '1,23');
      expect(_format(en, '1.23456'), '1.23');
    });

    test('drops letters and leading zeros', () {
      expect(_format(en, 'a1b2'), '12');
      expect(_format(en, '007'), '7');
      expect(_format(en, '0'), '0');
    });

    test('drops the fraction when decimals are not allowed', () {
      expect(_format(ints, '5000,5'), '5.000');
      expect(_format(ints, '5000,'), '5.000');
    });

    test('a leading decimal separator gets a zero', () {
      expect(_format(es, ',5'), '0,5');
      expect(_format(en, '.5'), '0.5');
      expect(_format(en, '.'), '0.');
    });

    test('moves the caret to the end of the regrouped text', () {
      final value = es.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '25000'),
      );
      expect(value.selection.baseOffset, 6);
    });
  });

  group('ThousandsInputFormatter keeping typed separators', () {
    const es = ThousandsInputFormatter(
      groupSeparator: '.',
      decimalSeparator: ',',
      keepTypedSeparators: true,
    );
    const en = ThousandsInputFormatter(
      groupSeparator: ',',
      decimalSeparator: '.',
      keepTypedSeparators: true,
    );
    const fr = ThousandsInputFormatter(
      groupSeparator: '\u202f',
      decimalSeparator: ',',
      keepTypedSeparators: true,
    );

    test('groups a number typed digit by digit, as before', () {
      expect(_type(es, '1000'), '1.000');
      expect(_type(es, '10005'), '10.005');
      expect(_type(en, '1234567'), '1,234,567');
      expect(_type(fr, '25000'), '25\u202f000');
    });

    test('keeps a typed group separator that groups nothing', () {
      // Without the flag the dot goes and the cents stay: 1.050.
      expect(_type(es, '10.50'), '10.50');
      expect(_type(es, '100.5'), '100.5');
      expect(_type(en, '10,50'), '10,50');
      expect(
        _type(
          const ThousandsInputFormatter(
            groupSeparator: '.',
            decimalSeparator: ',',
          ),
          '10.50',
        ),
        '1.050',
      );
    });

    test('keeps a typed decimal separator and every digit after it', () {
      expect(_type(es, '10,50'), '10,50');
      // Not trimmed to two decimals: `1,00` would read as one.
      expect(_type(es, '1,000'), '1,000');
      expect(_type(en, '1.000'), '1.000');
      expect(_type(en, '100.5'), '100.5');
      expect(_type(es, ',5'), ',5');
    });

    test('keeps either mark where the locale groups with neither', () {
      expect(_type(fr, '10.50'), '10.50');
      expect(_type(fr, '10,50'), '10,50');
    });

    test('a number typed with its own grouping is that number', () {
      expect(_type(es, '1.000'), '1.000');
      expect(_type(es, '1.000.000'), '1.000.000');
      expect(_type(en, '25,000'), '25,000');
      // On the way there the text is as typed, not regrouped.
      expect(_type(es, '1.0'), '1.0');
      expect(_type(es, '1.00'), '1.00');
    });

    test('a figure pasted into an empty field keeps its magnitude', () {
      expect(_format(es, '25.000'), '25.000');
      expect(_format(es, '25000'), '25.000');
      expect(_format(es, '10.50'), '10.50');
      expect(_format(es, '1.000,50'), '1.000,50');
    });

    test('a figure pasted over a grouped one stays as pasted', () {
      // No more dots than the figure it replaces — and none of them the old
      // one. Counted instead of looked at, `10.50` became `1.050` again.
      expect(_replace(es, '1.000', 0, 5, '10.50'), '10.50');
      expect(_replace(es, '10.000', 0, 6, '1500.50'), '1500.50');
      expect(_replace(en, '1,000', 0, 5, '10,50'), '10,50');
      // The same edit with no selection to go by (a programmatic replace).
      expect(_edit(es, _keys(es, TextEditingValue.empty, '1000'), '10.50').text, '10.50');
      // A grouped figure pasted over another is still that figure.
      expect(_replace(es, '1.000', 0, 5, '25.000'), '25.000');
      expect(_replace(es, '1.000', 0, 5, '2500'), '2.500');
    });

    test('a separator typed over a selection that held one is the typed one', () {
      // `25.000`, `.000` selected, a dot typed: the old dot went with the
      // selection. Read as stale grouping it was dropped, and `50` typed
      // next made 2.550.
      expect(_replace(es, '25.000', 2, 6, '25.'), '25.');
      final value = es.formatEditUpdate(
        const TextEditingValue(
          text: '25.000',
          selection: TextSelection(baseOffset: 2, extentOffset: 6),
        ),
        const TextEditingValue(
          text: '25.',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(_keys(es, value, '50').text, '25.50');
    });

    test('a separator behind a leading zero groups nothing', () {
      // `0.500` read as grouping lost its zero and its dot: 500.
      expect(_type(es, '0.500'), '0.500');
      expect(_type(en, '0,500'), '0,500');
    });

    test('once a text reads as grouped, its separators are the field\'s', () {
      // `10.500` is ten thousand five hundred in `es`, typed dot and all —
      // so a digit deleted from it regroups, as it would after `10500`.
      final value = _keys(es, TextEditingValue.empty, '10.500');
      expect(value.text, '10.500');
      expect(_edit(es, value, '10.50').text, '1.050');
    });

    test('goes back to grouping once the separator is deleted', () {
      var value = _keys(es, TextEditingValue.empty, '10.5');
      expect(value.text, '10.5');
      value = _edit(es, value, '10.');
      expect(value.text, '10.');
      value = _edit(es, value, '10');
      expect(value.text, '10');
      value = _keys(es, value, '00');
      expect(value.text, '1.000');
    });

    test('a digit deleted from a grouped figure regroups it', () {
      final value = _edit(es, _keys(es, TextEditingValue.empty, '10005'), '10.00');
      expect(value.text, '1.000');
    });

    test('drops what is neither a digit nor a separator', () {
      expect(_type(es, 'a1b 2'), '12');
      expect(_type(es, '-10.5'), '10.5');
    });

    test('keeps the caret where the user is typing', () {
      // `10.5`, caret after the dot, then a digit typed there.
      final typed = es.formatEditUpdate(
        const TextEditingValue(
          text: '10.5',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextEditingValue(
          text: '10.75',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(typed.text, '10.75');
      expect(typed.selection.baseOffset, 4);
      // Dropped characters before the caret move it back with the text.
      final cleaned = es.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'a10.5',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(cleaned.text, '10.5');
      expect(cleaned.selection.baseOffset, 3);
    });
  });
}

/// What the field holds after [start]..[end] of [before] is replaced so
/// that it reads [text] — a paste, or a key typed over a selection.
String _replace(
  ThousandsInputFormatter f,
  String before,
  int start,
  int end,
  String text,
) => f
    .formatEditUpdate(
      TextEditingValue(
        text: before,
        selection: TextSelection(baseOffset: start, extentOffset: end),
      ),
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    )
    .text;

/// [text] set in one edit over [from], the caret at its end.
TextEditingValue _edit(
  ThousandsInputFormatter f,
  TextEditingValue from,
  String text,
) => f.formatEditUpdate(
  from,
  TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ),
);

/// [keys] typed one at a time at the end of [from].
TextEditingValue _keys(
  ThousandsInputFormatter f,
  TextEditingValue from,
  String keys,
) {
  var value = from;
  for (final key in keys.split('')) {
    value = _edit(f, value, value.text + key);
  }
  return value;
}

/// What the field holds after [keys] are typed into it, one at a time.
String _type(ThousandsInputFormatter f, String keys) =>
    _keys(f, TextEditingValue.empty, keys).text;
