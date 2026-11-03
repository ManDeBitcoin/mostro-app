import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/nodes.dart' as nodes_api;
import 'package:mostro/src/rust/api/types.dart';

/// A node's kind 0 picture as the device keeps it, with the URL it came from,
/// or null when none is stored (`rust/src/node_pictures.rs`). Rust downloads
/// it when the profile is fetched — at startup, once the relays are up — and
/// again only when the profile names another URL, so a QR that pays the node
/// shows its face without a download. Keyed by the node's lowercase pubkey;
/// `MostroNodesNotifier` invalidates a node whose stored picture changed.
///
/// Resolves once the picture is decoded into the image cache under the key
/// [nodePictureImage] gives it: a QR opened after that paints the picture in
/// its first frame. Bytes that look like an image but do not decode —
/// truncated, corrupt, or a format this platform lacks — resolve to null and
/// are forgotten: the avatar loads the URL, and the next sync downloads the
/// picture again instead of keeping the broken copy for good.
///
/// Kept for the process: a node's picture is the device's, no identity's.
final nodePictureProvider = FutureProvider.family<MostroNodePicture?, String>((
  ref,
  pubkey,
) async {
  final picture = await nodes_api.getMostroNodePicture(pubkey: pubkey);
  if (picture == null) return null;
  if (await _decode(nodePictureImage(picture.bytes))) return picture;
  try {
    await nodes_api.forgetMostroNodePicture(pubkey: pubkey);
  } catch (e) {
    debugPrint('[nodePicture] could not forget an undecodable picture: $e');
  }
  return null;
});

/// One decode width for every size: the node selector and a QR's centre
/// share the image cache's entry. Sharp up to 64 dp at 3x: the centre of a
/// QR as wide as `MostroQr.maxSide`.
const nodePictureCacheWidth = 192;

/// The image of a stored picture's [bytes]. The cache keys it by the
/// identity of [bytes], so every reader passes the provider's own list.
ImageProvider nodePictureImage(Uint8List bytes) =>
    ResizeImage(MemoryImage(bytes), width: nodePictureCacheWidth);

/// Decode [image] into the image cache: `precacheImage` without a
/// `BuildContext`. Whether it decoded.
Future<bool> _decode(ImageProvider image) {
  final done = Completer<bool>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(true);
      // Not before the frame ends, as in `precacheImage`: the last listener
      // gone, the cache would let go of an image a widget is about to take.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        info.dispose();
        stream.removeListener(listener);
      });
    },
    onError: (_, __) {
      if (!done.isCompleted) done.complete(false);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}
