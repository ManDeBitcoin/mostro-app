import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/community.dart' as community_api;
import 'package:mostro/src/rust/api/community.dart' show CommunityProfile;

/// Provider for the currently active [CommunityProfile], if any.
final activeCommunityProfileProvider = StateNotifierProvider<
    ActiveCommunityNotifier, AsyncValue<CommunityProfile?>>(
  (ref) => ActiveCommunityNotifier(),
);

/// StateNotifier that manages the active community profile.
class ActiveCommunityNotifier
    extends StateNotifier<AsyncValue<CommunityProfile?>> {
  ActiveCommunityNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final profile = await community_api.getActiveCommunityProfile();
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
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

/// Provider for the list of accepted payment methods configured by the community.
final communityPaymentMethodsProvider = FutureProvider<List<String>>((ref) async {
  // Invalidate when community profile changes
  ref.watch(activeCommunityProfileProvider);
  return community_api.getCommunityPaymentMethods();
});
