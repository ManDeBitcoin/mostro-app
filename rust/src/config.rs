//! Default configuration constants for the Mostro network.
//!
//! These are compiled into the app and used on first launch when no
//! user-configured relays or Mostro node exist in the database.

use std::sync::RwLock;

/// Default relay URLs seeded on first launch.
///
/// These are the three relays the BitMaxis node lists in its kind 10002
/// relay list. Public relays rate-limit and cap replays differently —
/// `relay.mostro.network` stops at 300 events — so covering the node's whole
/// set keeps the book reachable when one of them is throttling us.
pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.mostro.network",
    "wss://mostro-p2p.tech",
    "wss://relay.shadowbip.com",
];

/// The BitMaxis Mostro daemon public key (hex, 32 bytes) — the one node this
/// app trades on. Published at <https://mostro.bitmaxis.com/>.
pub const DEFAULT_MOSTRO_PUBKEY: &str =
    "001bd4747d7d265edfe3bd3b7299886146ad850d51095fe77b763c32015685b9";

/// Default Mostro daemon display name.
pub const DEFAULT_MOSTRO_NAME: &str = "BitMaxis";

// ── Trusted node registry ────────────────────────────────────────────────────

/// Static configuration for a trusted Mostro community node.
///
/// Only the *identity* (pubkey) and region label are compiled in; display
/// metadata (name, picture, about) comes from the node's Nostr kind 0 event —
/// see `crate::api::nodes`.
pub struct TrustedNodeConfig {
    /// Node pubkey, 64-char lowercase hex.
    pub pubkey: &'static str,
    /// Region label: flag emoji + place name (a proper noun, not translated).
    pub region: &'static str,
}

/// The trusted registry — one entry, because this app serves the BitMaxis
/// community only. It stays a list so the node registry, its metadata cache
/// and the stats behind the Settings row keep working unchanged.
pub const TRUSTED_MOSTRO_NODES: &[TrustedNodeConfig] = &[TrustedNodeConfig {
    pubkey: DEFAULT_MOSTRO_PUBKEY,
    region: "🇪🇨 Ecuador",
}];

/// The push server (docs/PUSH_NOTIFICATIONS.md §3). The Fly.io instance the
/// server repository deploys; a build may point elsewhere with
/// `PUSH_SERVER_URL` at compile time (forks, a local server under test).
pub const DEFAULT_PUSH_SERVER_URL: &str = "https://mostro-push-server.fly.dev";

static PUSH_SERVER_URL_OVERRIDE: RwLock<Option<String>> = RwLock::new(None);

/// The push server base URL: the runtime override (tests), else the
/// compile-time `PUSH_SERVER_URL`, else the default. No trailing slash.
pub fn push_server_url() -> String {
    if let Some(url) = PUSH_SERVER_URL_OVERRIDE.read().unwrap().clone() {
        return url;
    }
    option_env!("PUSH_SERVER_URL")
        .unwrap_or(DEFAULT_PUSH_SERVER_URL)
        .trim_end_matches('/')
        .to_string()
}

/// Set (or clear) the push server URL override.
pub fn set_push_server_url_override(url: Option<String>) {
    *PUSH_SERVER_URL_OVERRIDE.write().unwrap() = url.map(|u| u.trim_end_matches('/').to_string());
}

// ── Runtime pubkey override ──────────────────────────────────────────────────

static ACTIVE_MOSTRO_PUBKEY: RwLock<Option<String>> = RwLock::new(None);

/// Returns the active Mostro pubkey — either the user-selected override or
/// the compiled-in default.
pub fn active_mostro_pubkey() -> String {
    ACTIVE_MOSTRO_PUBKEY
        .read()
        .unwrap()
        .clone()
        .unwrap_or_else(|| DEFAULT_MOSTRO_PUBKEY.to_string())
}

static ORDER_EXPIRY_OVERRIDE: RwLock<Option<u64>> = RwLock::new(None);

/// Seconds after creation a new order asks the daemon to expire it, when
/// the Mortsom test environment set one. `None` leaves the expiry to the
/// daemon's own default, as every production build does.
pub fn order_expiry_override() -> Option<u64> {
    *ORDER_EXPIRY_OVERRIDE.read().unwrap()
}

/// Set (or clear) the order expiry the test environment asks for.
pub fn set_order_expiry_override(secs: Option<u64>) {
    *ORDER_EXPIRY_OVERRIDE.write().unwrap() = secs;
}

/// Set (or clear) the active Mostro pubkey override.
///
/// Any daemon responses still in flight from a previously active
/// daemon will be rejected by `dispatch_mostro_message` once this changes
/// — callers that care about clean handoff should quiesce pending trades
/// before swapping the override.
pub fn set_active_mostro_pubkey(pubkey: Option<String>) {
    *ACTIVE_MOSTRO_PUBKEY.write().unwrap() = pubkey;
}
