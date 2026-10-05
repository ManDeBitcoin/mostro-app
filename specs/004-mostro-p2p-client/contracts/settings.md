# Contract: Settings API

**Module**: `rust/src/api/settings.rs`

User-configurable app preferences. All settings are persisted locally.
`logging_enabled` is runtime-only in the Rust store; the Flutter layer persists
it and re-applies it on launch, so the user's choice survives a restart.
`privacy_mode` in `AppSettings` is a read-only mirror of `Identity.privacy_mode`.
To change privacy mode, call `set_privacy_mode()` in the Reputation API
(`rust/src/api/reputation.rs`), which is the single write path.

## Functions

### get_settings() → AppSettings
Return all current user preferences.

**Returns**:
```text
AppSettings {
  theme: ThemeMode                 # System | Dark | Light (default: System)
  language: String                 # BCP-47 locale code (default: device locale)
  default_fiat_code: String?       # ISO 4217 code, e.g. "USD" (default: null — show all)
  default_lightning_address: String?  # Lightning address for auto-fill when selling
  logging_enabled: bool            # Runtime-only in Rust; re-applied by Flutter on launch
  privacy_mode: bool               # Mirrors Identity.privacy_mode; false when no Identity exists
}
```

---

### set_theme(theme: ThemeMode) → ()
Persist the user's theme preference.

**Errors**: `StorageError`.

---

### set_language(locale: String) → ()
Persist the user's language preference.

**Validation**: `locale` MUST be one of the BCP-47 codes supported at
initial release per FR-020d: `en`, `es`, `it`, `fr`, `de`.

**Errors**: `UnsupportedLocale`, `StorageError`.

---

### set_default_fiat_code(code: String?) → ()
Set the default fiat currency for new orders. Pass null to clear
(show all currencies).

**Validation** (applied only when `code` is non-null):
- If no active Mostro node is selected: perform format-only validation
  (accept any syntactically valid ISO 4217 code). Do NOT return
  `UnsupportedCurrency`.
- If an active node exists but `MostroNodeInfo.supported_currencies` is
  `null` (list unknown): likewise perform format-only validation and do
  NOT return `UnsupportedCurrency`.
- Only return `UnsupportedCurrency` when an active node provides a
  non-null `supported_currencies` Vec and `code` is not in that Vec.

**Errors**: `UnsupportedCurrency`, `StorageError`.

---

### set_default_lightning_address(address: String?) → ()
Set a default Lightning Address to auto-fill when selling (buyer
submits invoice). Pass null to clear.

**Validation**: If non-null, MUST match `user@domain` format.

**Errors**: `InvalidLightningAddress`, `StorageError`.

---

### set_logging_enabled(enabled: bool) → ()
Enable or disable verbose diagnostic logging at runtime. Applies the global log
filter synchronously: `Debug` while enabled, otherwise the build default
(`Debug` in debug builds, `Info` in release).

Not persisted in the Rust store — the Flutter layer owns persistence and calls
this once at startup with the saved value.

---

## Mostro Node Selection

### get_mostro_pubkey() → String
Return the active Mostro node's pubkey (hex) — the user-selected override, or
the compiled-in `DEFAULT_MOSTRO_PUBKEY` when none has been selected.

---

### set_active_mostro_node(pubkey: String) → ()
The single entry point for selecting / switching the active Mostro node.

Normalizes `pubkey` to lowercase hex (the registry compares case-sensitively),
validates it, persists it as the active node's **identity**, updates the
in-memory override (so outgoing events target the new node immediately), and
re-targets the live feeds to it: the order book is cleared, the Kind 38383
(orders) and Kind 14 (Mostro replies) filters are re-subscribed — author-pinned
to the new node under the same stable subscription IDs, each closed before it is
re-issued, because nostr-sdk 0.45 rejects a subscribe whose ID already exists and
keeps the old filters — the node's current orders are refetched, and its PoW
requirement is refreshed. A re-subscribe that no relay accepts is an error, not
a silent success.

The switch is **purely local**: no Nostr message is sent to either node. Pass
`DEFAULT_MOSTRO_PUBKEY` to return to the default node.

**Persistence**: only the pubkey is stored, under key `active_mostro_pubkey` in
the generic `settings` key-value table. Node **metadata** (name, fees, accepted
currencies, limits — the `MostroNodeInfo` model) is NOT persisted as the active
selection; display metadata lives in the node registry below.

**Errors**: `InvalidPubkey` if `pubkey` is not a valid 64-char hex key;
`StorageError` on a persistence failure.

---

## Node Registry (`api/nodes.rs`)

The registry yields `MostroNodeEntry` rows merged from three sources: the
compiled-in trusted registry (`config::TRUSTED_MOSTRO_NODES` — a single entry,
the BitMaxis node), user-added custom nodes, and cached kind 0 display
metadata (name, picture, about, website). The app serves that one node, so no
screen opens the selector any more: Settings → Mostro Node reads the active
entry's name from this list and opens About. The add/remove calls below have
no caller left in the UI.

### list_mostro_nodes() → Vec<MostroNodeEntry>
Trusted nodes first (registry order), then custom nodes (insertion order),
each flagged `is_active` against the current override. An active pubkey not
present in the registry (selected before the registry existed) is
auto-imported as a custom node so the selector always shows what the app is
actually using. Custom entries whose pubkey has since joined the trusted
registry are dropped (and the cleanup persisted) — otherwise a promotion
would leave a duplicate row that `remove_custom_mostro_node` refuses to
delete.

### add_custom_mostro_node(input: String, name: Option<String>) → MostroNodeEntry
Accepts a 64-char hex pubkey or `npub1…` (normalized to lowercase hex). A
user-given `name` takes precedence over kind 0 metadata.
**Errors** (stable markers, localized in Dart): `PrivateKeyNotAllowed` (nsec
input), `InvalidPubkey`, `NodeAlreadyExists` (trusted or already added),
`NotInitialized`.

### remove_custom_mostro_node(pubkey: String) → ()
Removes a user-added node; removing an absent one is a no-op.
**Errors**: `CannotRemoveActiveNode`, `NodeIsTrusted`, `NotInitialized`.

### refresh_mostro_node_metadata() → Vec<MostroNodeEntry>
Fetches kind 0 profile events for all known nodes in one relay query (10s
timeout), updates the persisted cache, and returns the refreshed registry.
Best-effort with partial updates: whatever arrives within the window is
cached, even when some authors never answered; only an outright query failure
errors, leaving the cache untouched. `picture`/`website` are kept only when
`https://` — a kind 0 event is attacker-controlled input.

### fetch_mostro_node_stats(pubkeys: Vec<String>) → Vec<MostroNodeStats> (`api/node_stats.rs`)
Decision data for the selector cards, one row per requested pubkey in request
order. Two batched relay queries (10s each, run concurrently): the nodes'
kind 38385 instance events and their `pending` kind 38383 orders. Per node:
`info_seen_at` (the 38385 `created_at` — a liveness signal, mostrod republishes
it every `publish_mostro_info_interval`, 300 s by default, and never in Cashu
mode), `latest_order_at`, `fee_pct` (the wire `fee` fraction × 100),
`min_order_amount` / `max_order_amount`, `accepted_currencies`
(`fiat_currencies_accepted` split, trimmed, upper-cased, deduplicated),
`escrow_mode` marker (`unknown` / `lightning` / `cashu`), `cashu_mint_url`
(Cashu only), `bond_required` (`bond_enabled`; `None` on a daemon without
bonds), `bond_pct` (only when required), `orders_by_fiat` and `total_orders`.
Orders are counted by the app — never declared by the node — keeping only the
newest version per (`author`, `d`), `pending`, and not past `expiration`.
Best-effort like `refresh_mostro_node_metadata`: a node that answered nothing
is an empty row (the UI shows it as unreachable), never a missing one. The
kind 38385 events it received refresh the node info cache (below), best effort
and only on a change; order counts are never persisted and the active-node
order book is never touched. **Errors**: `InvalidPubkey`, or a failed relay
query.

### cached_mostro_node_stats(pubkeys: Vec<String>) → Vec<MostroNodeStats> (`api/node_stats.rs`)
What the selector shows the moment it opens: one row per requested pubkey in
request order, built from the persisted kind 38385 cache alone — no relay is
asked. A node never seen is an empty row. These rows carry **no order count**
(`total_orders == 0`, `latest_order_at == None` whatever the node's real book)
and an `info_seen_at` as old as the cache, so the UI must not derive liquidity
or availability from them: the card shows fee, range, currencies, custody and
bond, keeps a skeleton on the order count, draws no availability line and never
blocks the node. `fetch_mostro_node_stats` runs behind it and replaces the row.
**Errors**: a failed storage read.

### refresh_mostro_node_info_cache() → () (`api/node_stats.rs`)
Startup warm-up, fired in the background by `app_bootstrap.dart` once the relay
pool exists. Waits up to 5 s for the relay handshakes it races with, fetches
the kind 38385 event of every registry node (trusted and user-added) in one
query (10 s), and persists the newest valid one per node (`d` tag = author).
"Newest" is NIP-01's order for a replaceable event: the greater `created_at`,
and within one second the **lowest event id** — so which relay answers first
never decides what is cached. The id is persisted with the entry; an entry
written before it was kept yields a same-second tie to any event with an id.
Nodes that did not answer keep their cached event; entries of nodes no longer
in the registry are dropped. Node settings rarely change, which is why a cached
copy is good enough to paint first. **Errors**: a failed relay query (the
cache is then untouched); a failed cache write is logged and ignored.

**Persistence**: `custom_mostro_nodes` (JSON array), `mostro_node_metadata`
(JSON map, pubkey → metadata) and `mostro_node_info` (JSON map, pubkey →
`{ created_at, tags }` — the raw tags of the node's newest kind 38385 event,
parsed on read by the same code as a live event) in the generic `settings`
key-value table.

---

### rehydrate_active_mostro_node() → ()
Load the persisted active pubkey into the in-memory override. Call once at
startup, after `init_db` and **before** the relay pool starts subscribing, so
the first subscription already targets the persisted node. `init_db` has by
then run `db::seeds::pin_active_node`, so that node is the compiled-in one
(see Default Mostro Node below). No-op when nothing has been persisted or when
the DB is unavailable.

---

## Streams

### on_settings_changed() → Stream<AppSettings>
Emits whenever any setting is updated.

---

## Default Configuration (Hardcoded Seed Values)

These values are compiled into the app as defaults. They are used on first launch
before the user adds or removes anything.

### Default Relays

| URL | Purpose |
|-----|---------|
| `wss://relay.mostro.network` | BitMaxis node's kind 10002 list |
| `wss://mostro-p2p.tech` | BitMaxis node's kind 10002 list |
| `wss://relay.shadowbip.com` | BitMaxis node's kind 10002 list |

The set mirrors the BitMaxis node's own kind 10002 relay list. Public relays
rate-limit and cap replays differently (`relay.mostro.network` stops at 300
stored events per REQ), so seeding all three keeps the order book reachable
when one of them is throttling the client.

These are stored as `RelayInfo` entries with `user_added: false`. They cannot be
removed by the user from the UI (only user-added relays are deletable), but they
can be disabled.

### Default Mostro Node

| Field | Value |
|-------|-------|
| `pubkey` | `001bd4747d7d265edfe3bd3b7299886146ad850d51095fe77b763c32015685b9` |
| `name` | `BitMaxis` |

The app serves the BitMaxis community only: this compiled-in pubkey is the
active node and the single entry of the trusted registry (region
`🇪🇨 Ecuador`). No screen selects another node. When the store opens,
`db::seeds::pin_active_node` rewrites a persisted node other than this one —
an install that predates the pin — and clears the community profile that
described it, so `rehydrate_active_mostro_node` then loads the pinned node.
`set_active_mostro_node` remains for test builds, which seed a local daemon
through `MOSTRO_PUB_KEY`.

### Rust Constants (suggested location: `rust/src/config.rs`)

```rust
pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.mostro.network",
    "wss://mostro-p2p.tech",
    "wss://relay.shadowbip.com",
];

pub const DEFAULT_MOSTRO_PUBKEY: &str =
    "001bd4747d7d265edfe3bd3b7299886146ad850d51095fe77b763c32015685b9";

pub const DEFAULT_MOSTRO_NAME: &str = "BitMaxis";
```
