import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/whole_amount_input.dart';

/// What the field holds after [text] replaces [before] in one edit.
String _edit(String text, {String before = ''}) => wholeAmountInputFormatter
    .formatEditUpdate(
      TextEditingValue(text: before),
      TextEditingValue(text: text),
    )
    .text;

void main() {
  group('wholeAmountInputFormatter', () {
    test('lets digits through', () {
      expect(_edit('150'), '150');
      expect(_edit('007'), '007');
    });

    test('keeps a typed separator where it was typed', () {
      // A digits-only filter made 1050 and 509 of these.
      expect(_edit('10.50'), '10.50');
      expect(_edit('50,9'), '50,9');
      expect(_edit('1.000'), '1.000');
      expect(_edit('150.', before: '150'), '150.');
    });

    test('drops everything else', () {
      // `int.tryParse` reads a sign and a hex prefix: neither may arrive.
      expect(_edit('-5a 0'), '50');
      expect(_edit('+150'), '150');
      expect(_edit('0x96'), '096');
      expect(_edit('1e3'), '13');
      expect(_edit('1 000'), '1000');
    });
  });
}
