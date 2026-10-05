/// Shared Mostro node defaults — mirrors rust/src/config.rs.
///
/// Update both this file and config.rs when the defaults change.
library;

/// The BitMaxis Mostro daemon public key (64-char hex) — the one node this
/// app trades on.
const defaultMostroPubkey =
    '001bd4747d7d265edfe3bd3b7299886146ad850d51095fe77b763c32015685b9';

/// Name of the community the app serves, shown where the node has not
/// answered with its own kind 0 name yet.
const defaultMostroName = 'BitMaxis';

/// Default Nostr relay URLs used by the Mostro daemon.
const defaultMostroRelays = [
  'wss://relay.mostro.network',
  'wss://mostro-p2p.tech',
  'wss://relay.shadowbip.com',
];
