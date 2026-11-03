import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/trade_node.dart';

void main() {
  const active = 'aa11';

  test('a trade of another node is on another node', () {
    expect(isOnOtherNode(tradeNode: 'bb22', activeNode: active), isTrue);
  });

  test('the active node is the same node in either case', () {
    expect(isOnOtherNode(tradeNode: 'AA11', activeNode: active), isFalse);
  });

  test('a row that does not know its node counts as the active one', () {
    // As Rust treats it (#810): refusing it would strand the trade.
    expect(isOnOtherNode(tradeNode: '', activeNode: active), isFalse);
  });

  test('what the user browses is the active node\'s, in either case', () {
    expect(isOnActiveNode(tradeNode: 'AA11', activeNode: active), isTrue);
    expect(isOnActiveNode(tradeNode: 'bb22', activeNode: active), isFalse);
  });

  test('a row that does not know its node is no node\'s to browse', () {
    // Unlike for actions: hidden until a restore names its node (#813).
    expect(isOnActiveNode(tradeNode: '', activeNode: active), isFalse);
  });

  test("a trade's node is the one its row names", () {
    expect(tradeNodeOf(tradeNode: 'bb22', activeNode: active), 'bb22');
  });

  test('a row that does not know its node lives on the active one', () {
    expect(tradeNodeOf(tradeNode: '', activeNode: active), active);
  });
}
