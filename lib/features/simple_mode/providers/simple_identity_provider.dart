import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/src/rust/api/types.dart' show NymIdentity;

/// Retrieves the user's master Nostr public key.
final myPubkeyProvider = FutureProvider<String?>((ref) async {
  try {
    return (await identity_api.getIdentity())?.publicKey;
  } catch (_) {
    return null;
  }
});

/// Resolves the user's own Nym identity (pseudonym and avatar).
final myNymProvider = FutureProvider<NymIdentity?>((ref) async {
  final pubkey = await ref.watch(myPubkeyProvider.future);
  if (pubkey == null || pubkey.isEmpty) return null;
  return ref.watch(peerNymProvider(pubkey).future);
});
