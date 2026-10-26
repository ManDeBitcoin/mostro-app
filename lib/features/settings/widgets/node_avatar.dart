import 'package:flutter/material.dart';

import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/src/rust/api/types.dart';

/// [color] with its alpha scaled by [dim] — how decorative surfaces fade on a
/// dimmed card while the text on them stays fully opaque.
Color dimmed(Color color, double dim) =>
    dim >= 1 ? color : color.withValues(alpha: color.a * dim);

/// A node's face: the picture of its kind 0 profile, or its initial on a tint
/// derived from its name when it has none or the picture does not load. The
/// node selector shows it beside each node and a QR that pays a node in its
/// centre (#851), so the user knows the node by the same face in both.
class NodeAvatar extends StatelessWidget {
  const NodeAvatar({
    super.key,
    required this.entry,
    this.size = 32,
    this.initialSize = 13,
    this.dim = 1,
    this.palette,
  });

  final MostroNodeEntry entry;

  /// Diameter.
  final double size;

  /// Font size of the initial.
  final double initialSize;

  /// How much of the tint shows: less on a dimmed card ([dimmed]).
  final double dim;

  /// The tint's palette, the theme's by default. A QR is white in both
  /// themes, so its centre takes [NodeSelectorPalette.light].
  final NodeSelectorPalette? palette;

  /// One decode width for every size: the node selector and a QR's centre
  /// share the image cache's entry, so the picture is fetched once, not once
  /// per screen. Sharp up to 64 dp at 3x: the centre of a QR as wide as
  /// `MostroQr.maxSide`.
  static const int _cacheWidth = 192;

  @override
  Widget build(BuildContext context) {
    final pal = palette ?? NodeSelectorPalette.of(context);
    final name = nodeDisplayName(entry);
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    // Tint derived from the name, never a generated identicon.
    final lime = name.codeUnits.fold<int>(0, (a, b) => a + b).isEven;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dimmed(lime ? pal.avatarLimeBg : pal.avatarYellowBg, dim),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: initialSize,
          fontWeight: FontWeight.w700,
          color: lime ? pal.avatarLimeInk : pal.avatarYellowInk,
        ),
      ),
    );
    final picture = entry.picture;
    if (picture == null) return fallback;
    return ClipOval(
      child: Image.network(
        picture,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: _cacheWidth,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
