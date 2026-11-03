/// Whether a trade whose row names [tradeNode] lives on a node other than
/// [activeNode] (#811). A row that does not know its node (empty) counts as
/// the active node's, as Rust treats it (#810).
bool isOnOtherNode({required String tradeNode, required String activeNode}) =>
    tradeNode.isNotEmpty && tradeNode.toLowerCase() != activeNode.toLowerCase();

/// Whether a trade whose row names [tradeNode] belongs with what the user
/// browses on [activeNode] (#813): My Trades, Chats and their counters. A
/// row that does not know its node (empty) is no node's here, unlike for
/// actions ([isOnOtherNode]): it shows nowhere until a restore names it.
bool isOnActiveNode({required String tradeNode, required String activeNode}) =>
    tradeNode.isNotEmpty && tradeNode.toLowerCase() == activeNode.toLowerCase();

/// The node a trade lives on: the one its row names, or [activeNode] when
/// the row does not know (empty), as [isOnOtherNode] reads it.
String tradeNodeOf({required String tradeNode, required String activeNode}) =>
    tradeNode.isEmpty ? activeNode : tradeNode;
