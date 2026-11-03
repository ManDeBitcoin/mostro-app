import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/features/settings/providers/node_picture_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

/// [color] with its alpha scaled by [dim] — how decorative surfaces fade on a
/// dimmed card while the text on them stays fully opaque.
Color dimmed(Color color, double dim) =>
    dim >= 1 ? color : color.withValues(alpha: color.a * dim);

/// A node's face: the picture of its kind 0 profile, or its initial on a tint
/// derived from its name when it has none or the picture does not load. The
/// node selector shows it beside each node and a QR that pays a node in its
/// centre (#851), so the user knows the node by the same face in both.
///
/// The picture is the one the device keeps ([nodePictureProvider]), stored
/// when the profile was fetched. It is loaded from its URL only while none
/// is stored from the URL the profile names now.
class NodeAvatar extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final stored = ref.watch(nodePictureProvider(entry.pubkey.toLowerCase()));
    final kept = stored.valueOrNull;
    final ImageProvider image;
    if (kept != null && kept.url == picture) {
      image = nodePictureImage(kept.bytes);
    } else if (stored.isLoading && !stored.hasValue) {
      // The device answers within a frame or two: no download meanwhile.
      return SizedBox.square(dimension: size);
    } else {
      image = ResizeImage(NetworkImage(picture), width: nodePictureCacheWidth);
    }
    return ClipOval(
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A picture replaced by its stored copy shows no gap.
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
