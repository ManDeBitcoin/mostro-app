import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/core/trade_node.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/widgets/node_avatar.dart';
import 'package:mostro/shared/widgets/mostro_qr.dart';

/// A QR that pays the node of an order, with that node's face in its centre
/// (#851): someone who trades on more than one node sees which one they pay.
/// The node is the order's, not the active one; an order that does not know
/// it is the active node's ([tradeNodeOf]).
class OrderNodeQr extends ConsumerWidget {
  const OrderNodeQr({
    super.key,
    required this.data,
    required this.nodePubkey,
    this.semanticsLabel,
  });

  final String data;

  /// The order's `nodePubkey`, empty when unknown.
  final String nodePubkey;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pubkey = tradeNodeOf(
      tradeNode: nodePubkey,
      activeNode: ref.watch(activeMostroPubkeyProvider),
    );
    final entry = nodeEntryOf(
      pubkey,
      ref.watch(mostroNodesProvider).valueOrNull ?? const [],
    );
    return MostroQr(
      data: data,
      semanticsLabel: semanticsLabel,
      logo:
          (side) => NodeAvatar(
            entry: entry,
            size: side,
            // The node selector's proportion: 13 sp on 32 dp.
            initialSize: side * 0.4,
            // The QR is white in both themes.
            palette: NodeSelectorPalette.light,
          ),
    );
  }
}
