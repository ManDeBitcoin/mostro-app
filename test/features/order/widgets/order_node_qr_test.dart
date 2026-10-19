import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/features/order/widgets/order_node_qr.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/widgets/node_avatar.dart';
import 'package:mostro/shared/widgets/mostro_qr.dart';
import 'package:mostro/src/rust/api/types.dart';

const _active =
    'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111';
const _other =
    'bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222';
const _invoice =
    'lnbc2520n1pjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygs'
    'pp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxx'
    'mmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq8rkx3yf5tcsyz3d73gafnh';

MostroNodeEntry _node(String pubkey, String name, {String? picture}) =>
    MostroNodeEntry(
      pubkey: pubkey,
      region: null,
      isTrusted: true,
      isActive: pubkey == _active,
      name: name,
      picture: picture,
      about: null,
      website: null,
    );

class _Nodes extends MostroNodesNotifier {
  _Nodes(this.nodes);

  final List<MostroNodeEntry> nodes;

  @override
  Future<List<MostroNodeEntry>> build() async => nodes;

  @override
  Future<void> refreshMetadata() async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required String nodePubkey,
  required List<MostroNodeEntry> nodes,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mostroNodesProvider.overrideWith(() => _Nodes(nodes)),
        mostroPubkeyProvider.overrideWith((ref) => _active),
      ],
      child: MaterialApp(
        theme: theme,
        home: Center(
          child: OrderNodeQr(data: _invoice, nodePubkey: nodePubkey),
        ),
      ),
    ),
  );
  // The registry answers.
  await tester.pump();
}

/// The QR that pays an order shows its node (#851).
void main() {
  final registry = [_node(_active, 'Mostro'), _node(_other, 'Bitcoin Bolivia')];

  testWidgets("the centre is the order's node, not the active one", (
    tester,
  ) async {
    await _pump(tester, nodePubkey: _other, nodes: registry);
    expect(tester.widget<MostroQr>(find.byType(MostroQr)).logo, isNotNull);
    expect(
      tester.widget<NodeAvatar>(find.byType(NodeAvatar)).entry.pubkey,
      _other,
    );
    expect(find.text('B'), findsOneWidget);
    expect(find.text('M'), findsNothing);
  });

  testWidgets('an order that does not know its node shows the active one', (
    tester,
  ) async {
    await _pump(tester, nodePubkey: '', nodes: registry);
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('a node with a picture shows its picture', (tester) async {
    const picture = 'https://example.com/bolivia.png';
    await _pump(
      tester,
      nodePubkey: _other,
      nodes: [_node(_other, 'Bitcoin Bolivia', picture: picture)],
    );
    final image = tester.widget<Image>(find.byType(Image)).image;
    expect(image, isA<ResizeImage>());
    final source = (image as ResizeImage).imageProvider;
    expect((source as NetworkImage).url, picture);
  });

  testWidgets('a node the registry does not hold: its pubkey names it', (
    tester,
  ) async {
    await _pump(tester, nodePubkey: _other, nodes: const []);
    expect(find.byType(NodeAvatar), findsOneWidget);
    // `bbbb2222…bbbb2222`, as the node selector would name it.
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('the initial keeps the light tint on the dark theme', (
    tester,
  ) async {
    // The QR is white in both themes: a dark-theme tint would wash out.
    await _pump(
      tester,
      nodePubkey: _other,
      nodes: registry,
      theme: buildDarkTheme(),
    );
    final circle = tester.widget<Container>(
      find.descendant(
        of: find.byType(NodeAvatar),
        matching: find.byType(Container),
      ),
    );
    final fill = (circle.decoration! as BoxDecoration).color;
    expect(
      fill,
      anyOf(
        NodeSelectorPalette.light.avatarLimeBg,
        NodeSelectorPalette.light.avatarYellowBg,
      ),
    );
  });
}
