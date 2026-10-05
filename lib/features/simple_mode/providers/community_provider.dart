import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/community.dart' as community_api;
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;

/// Provider for the currently active [CommunityProfile], if any.
final activeCommunityProfileProvider = StateNotifierProvider<
    ActiveCommunityNotifier, AsyncValue<CommunityProfile?>>(
  (ref) => ActiveCommunityNotifier(),
);

/// StateNotifier that manages the active community profile.
///
/// The profile is the community's card, which the core reads from the node's
/// relays and stores (`mostro::community_card`): it arrives after startup,
/// and changes whenever the operator edits it. Nothing announces either, so
/// the stored profile is read again every [reloadEvery] — a local read, and
/// the one that makes the core look for a newer card when its last look is
/// old.
class ActiveCommunityNotifier
    extends StateNotifier<AsyncValue<CommunityProfile?>> {
  ActiveCommunityNotifier({Future<CommunityProfile?> Function()? read})
    : _read = read ?? community_api.getActiveCommunityProfile,
      super(const AsyncValue.loading()) {
    load();
    _reload = Timer.periodic(reloadEvery, (_) => load());
  }

  /// Reads the stored profile: the core's, unless a test stands in for it.
  final Future<CommunityProfile?> Function() _read;

  /// How often the stored profile is read again.
  static const reloadEvery = Duration(seconds: 45);

  late final Timer _reload;

  Future<void> load() async {
    try {
      final profile = await _read();
      if (!mounted) return;
      // Only a change is a new state: every watcher rebuilds on one.
      if (state is AsyncData<CommunityProfile?> &&
          _sameCard(state.valueOrNull, profile)) {
        return;
      }
      state = AsyncValue.data(profile);
    } catch (e, st) {
      if (!mounted) return;
      // A read that fails keeps the profile already on screen.
      if (state.valueOrNull != null) return;
      state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _reload.cancel();
    super.dispose();
  }

  /// Apply a new community profile.
  Future<void> applyProfile(CommunityProfile profile) async {
    state = const AsyncValue.loading();
    try {
      await community_api.applyCommunityProfile(profile: profile);
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Clear the active community profile.
  Future<void> clearProfile() async {
    state = const AsyncValue.loading();
    try {
      await community_api.clearActiveCommunityProfile();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// Whether [a] and [b] are the same card, field by field. The generated
/// `==` compares the two lists by identity, so two reads of one stored
/// profile are never equal under it.
bool _sameCard(CommunityProfile? a, CommunityProfile? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.version == b.version &&
      a.name == b.name &&
      a.pubkey == b.pubkey &&
      listEquals(a.relays, b.relays) &&
      a.currency == b.currency &&
      listEquals(a.paymentMethods, b.paymentMethods) &&
      a.feeBps == b.feeBps &&
      a.bondPercent == b.bondPercent &&
      a.website == b.website &&
      a.contact == b.contact &&
      a.signature == b.signature;
}

/// Provider for the list of accepted payment methods configured by the community.
final communityPaymentMethodsProvider = FutureProvider<List<String>>((ref) async {
  // Invalidate when community profile changes
  ref.watch(activeCommunityProfileProvider);
  return community_api.getCommunityPaymentMethods();
});
