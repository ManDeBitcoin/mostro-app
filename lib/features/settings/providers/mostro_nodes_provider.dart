import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/settings/providers/node_picture_provider.dart';
import 'package:mostro/src/rust/api/nodes.dart' as nodes_api;
import 'package:mostro/src/rust/api/settings.dart' as settings_api;
import 'package:mostro/src/rust/api/types.dart';

// ── Active node pubkey ────────────────────────────────────────────────────────

/// Active Mostro node pubkey — seeded at bootstrap from the Rust bridge and
/// synced back to it on every selection, so outgoing events are routed to the
/// selected node.
final mostroPubkeyProvider = StateProvider<String>(
  (ref) => defaultMostroPubkey,
);

/// Truncate a pubkey to `first8…last8` for display.
String truncatePubkey(String pubkey) {
  if (pubkey.length <= 16) return pubkey;
  return '${pubkey.substring(0, 8)}…${pubkey.substring(pubkey.length - 8)}';
}

// ── Node registry ─────────────────────────────────────────────────────────────

/// The Mostro node registry: compiled-in trusted communities plus user-added
/// nodes, each merged with cached kind 0 metadata (name, picture, about).
///
/// The list itself lives in Rust (`api/nodes.rs`); this notifier only mirrors
/// it and forwards mutations.
final mostroNodesProvider =
    AsyncNotifierProvider<MostroNodesNotifier, List<MostroNodeEntry>>(
      MostroNodesNotifier.new,
    );

/// Fetch the nodes' kind 0 profiles, and the pictures they name, once
/// [connected] settles: the startup warm-up, which waits for the relay
/// handshakes. The picture a QR shows is then on the device before the first
/// QR asks for it, instead of being downloaded as that QR opens.
///
/// A registry built before then fetched while no relay was connected and may
/// have come back empty, so it fetches again; one built now fetches as it
/// builds.
Future<void> refreshNodeProfilesOnceConnected(
  ProviderContainer container,
  Future<void> connected,
) async {
  await connected;
  if (container.exists(mostroNodesProvider)) {
    await container
        .read(mostroNodesProvider.notifier)
        .refreshMetadataAfterPending();
  } else {
    await container.read(mostroNodesProvider.future);
  }
}

class MostroNodesNotifier extends AsyncNotifier<List<MostroNodeEntry>> {
  bool _refreshing = false;

  /// The refresh in flight, if any.
  Future<void>? _inFlight;

  @override
  Future<List<MostroNodeEntry>> build() async {
    final list = await nodes_api.listMostroNodes();
    // Serve the cached registry immediately; fresh kind 0 metadata lands via
    // the background refresh below.
    refreshMetadata();
    return list;
  }

  /// Re-fetch kind 0 metadata for all known nodes. Best-effort: on relay
  /// timeout or bridge error the current list simply stays as it is.
  ///
  /// Coalesced: opening the selector triggers a refresh while the one from
  /// [build] (via the Settings screen) may still be in flight — the second
  /// call is dropped instead of issuing a duplicate relay query.
  ///
  /// The pictures the profiles name are downloaded after it, in the
  /// background: neither the coalescing nor a caller waits on them.
  Future<void> refreshMetadata() async {
    if (_refreshing) return;
    _refreshing = true;
    final run = _refresh();
    _inFlight = run;
    try {
      await run;
    } finally {
      _refreshing = false;
      _inFlight = null;
    }
    // After a failed fetch too: the cached profiles may name a picture an
    // earlier download missed.
    unawaited(_syncPictures());
  }

  /// The relay round trip behind a refresh; a seam for tests.
  @visibleForTesting
  Future<List<MostroNodeEntry>> fetchMetadata() =>
      nodes_api.refreshMostroNodeMetadata();

  /// The picture downloads behind a refresh; a seam for tests.
  @visibleForTesting
  Future<List<String>> syncPictures() => nodes_api.syncMostroNodePictures();

  Future<void> _refresh() async {
    try {
      final refreshed = await fetchMetadata();
      state = AsyncData(refreshed);
    } catch (e) {
      debugPrint('[mostroNodes] metadata refresh failed: $e');
    }
  }

  /// Download the pictures the profiles name — only those not stored yet,
  /// or stored from another URL — and have each node whose stored picture
  /// changed read it again.
  Future<void> _syncPictures() async {
    try {
      final changed = await syncPictures();
      for (final pubkey in changed) {
        // Through the container, which only touches a provider already
        // alive: `ref.invalidate` would create it in debug builds to check.
        ref.container.invalidate(nodePictureProvider(pubkey));
      }
    } catch (e) {
      debugPrint('[mostroNodes] picture sync failed: $e');
    }
    _warmPictures();
  }

  /// Read every node's stored picture, which decodes it into the image
  /// cache: the first QR of the session then paints it in its first frame
  /// instead of reading it from the device as it opens.
  void _warmPictures() {
    for (final node in state.valueOrNull ?? const <MostroNodeEntry>[]) {
      if (node.picture == null) continue;
      ref.container
          .read(nodePictureProvider(node.pubkey.toLowerCase()).future)
          .ignore();
    }
  }

  /// A refresh that starts only after the one in flight, when there is one,
  /// instead of being dropped into it. For a caller that knows the relays
  /// just became reachable: a refresh issued before that may have come back
  /// empty, so joining it would not do.
  Future<void> refreshMetadataAfterPending() async {
    final pending = _inFlight;
    if (pending != null) await pending;
    await refreshMetadata();
  }

  /// Activate `pubkey` — persists it, re-targets subscriptions (Rust side) and
  /// keeps [mostroPubkeyProvider] in sync. Rethrows on failure after rolling
  /// the pubkey provider back.
  Future<void> selectNode(String pubkey) async {
    final previous = ref.read(mostroPubkeyProvider);
    ref.read(mostroPubkeyProvider.notifier).state = pubkey;
    try {
      await settings_api.setActiveMostroNode(pubkey: pubkey);
    } catch (e) {
      ref.read(mostroPubkeyProvider.notifier).state = previous;
      rethrow;
    }
    state = AsyncData(await nodes_api.listMostroNodes());
  }

  /// Add a custom node by 64-char hex or `npub1…` pubkey. Rethrows the Rust
  /// marker error (`InvalidPubkey`, `PrivateKeyNotAllowed`,
  /// `NodeAlreadyExists`) for the dialog to localize.
  Future<void> addCustomNode({required String input, String? name}) async {
    await nodes_api.addCustomMostroNode(input: input, name: name);
    state = AsyncData(await nodes_api.listMostroNodes());
    refreshMetadata();
  }

  /// Remove a user-added node. Rethrows on failure
  /// (e.g. `CannotRemoveActiveNode`).
  Future<void> removeCustomNode(String pubkey) async {
    await nodes_api.removeCustomMostroNode(pubkey: pubkey);
    state = AsyncData(await nodes_api.listMostroNodes());
  }
}
