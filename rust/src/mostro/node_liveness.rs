//! Whether the Mostro node is announcing itself, and whether it says it is
//! in maintenance — checked before a new order or a take is sent.
//!
//! A daemon publishes its Kind 38385 info event at start and then every
//! `publish_mostro_info_interval` seconds (300 by default; a maintenance flip
//! republishes at once). That event outlives the daemon: a node that stopped
//! keeps its last 38385 on the relays, with a perfectly valid
//! `protocol_version` and `pow`, so every capability gate passed and the
//! request went out to nobody — the user learned it from a `NoDaemonResponse`
//! ten seconds later. The event's **age** is the one public sign that someone
//! is still there, and nothing read it.
//!
//! This module keeps, per node, when that event was signed and what its
//! `maintenance_mode` tag said, and turns it into a verdict:
//!
//! | snapshot | verdict |
//! |---|---|
//! | signed within [`MAX_ANNOUNCEMENT_AGE_SECS`], not in maintenance | send |
//! | signed within it, `maintenance_mode = true` | `MaintenanceMode` |
//! | older, or none at all | `NodeNotAnnouncing` |
//!
//! [`ensure_live`] never refuses on a snapshot alone: anything short of
//! "send" first takes a fresh look at the node's info event and judges what
//! came back. And it refuses only on evidence: an old snapshot is "the node
//! stopped" only when some relay handed over the event just now. A look that
//! read nothing — the REQ refused by a relay's subscription cap, a socket
//! gone stale behind a resume, a slow relay — is the same blindness as
//! having no relay at all, and the gate then says nothing. So a node that came out of maintenance or resumed
//! publishing a minute ago is not held to what it said at app start — and a
//! node with no info event at all, which used to end in
//! `NodeCapabilitiesUnknown` with nothing ever re-fetching, gets one more
//! look per attempt. What the look brings is applied like any capability
//! fetch; a look that brings nothing changes nothing ([`look_again`]).
//!
//! "Older" is by the device's clock, and a device clock that runs ahead ages
//! every event by as much. So the last step before `NodeNotAnnouncing` asks
//! the relays for the one "now" that is not the device's: when any other
//! node last announced itself. An event no further behind that than the
//! limit is as current as anyone's, and the node is not refused
//! ([`ensure_live_among`]).
//!
//! **It gates new business only** — `create_order` and `take_order`. Nothing
//! on an existing trade (fiat-sent, release, cancel, dispute, add-invoice,
//! rating) may ever wait on this: a user must be able to act on a trade they
//! are in whatever the node last announced.
//!
//! Like [`crate::mostro::pow`] and [`crate::mostro::protocol_version`] the
//! state is tagged with the node it came from, here by keying it: a node
//! switch finds no snapshot for the new node rather than the previous one's.

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex, PoisonError};

use anyhow::{anyhow, Result};

/// How old a node's info event may be before the node counts as silent: two
/// missed publications at the daemon's default five-minute interval, plus a
/// minute. The same threshold the node's own manager applies
/// (`NODE_INFO_FRESH_SECS`), so the app and the operator's panel agree on
/// "announcing".
pub(crate) const MAX_ANNOUNCEMENT_AGE_SECS: i64 = 660;

/// Kind of a node's info event (NIP-33 addressable, `d` = the node's hex
/// pubkey).
pub(crate) const KIND_NODE_INFO: u16 = 38385;

/// Whether `event` is `node`'s own info event: that kind, addressed by the
/// node's key, signed by the node.
///
/// A relay answers a REQ with whatever it likes. nostr-sdk verifies the
/// signature of every incoming event, but it matches the event against the
/// subscription's filter only when asked to (`verify_subscriptions`, off by
/// default and off in this client), so "a relay returned it for this filter"
/// says nothing about who wrote it. Read unchecked, any relay in the pool
/// could hand over an event signed by a throwaway key: dated in the future
/// and saying `maintenance_mode = true`, it would win over every genuine one
/// and refuse each new order and take for the rest of the session; carrying
/// a proof-of-work difficulty, a protocol version and a bond policy, it
/// would be applied as the node's. Every reader of this event goes through
/// here, before the newest copy is picked — a forgery must not be able to
/// shadow the node's event by claiming a later date either.
///
/// The signature is checked again on purpose, as for the rates event: it is
/// what makes the author check mean anything, and it costs one verification
/// per copy read.
pub(crate) fn is_info_event_of(
    event: &nostr_sdk::prelude::Event,
    node: &nostr_sdk::prelude::PublicKey,
) -> bool {
    let node_hex = node.to_hex();
    event.kind == nostr_sdk::prelude::Kind::from(KIND_NODE_INFO)
        && event.pubkey == *node
        && event.tags.iter().map(|t| t.as_slice()).any(|t| {
            t.first().map(String::as_str) == Some("d")
                && t.get(1).is_some_and(|v| v.eq_ignore_ascii_case(&node_hex))
        })
        && event.verify().is_ok()
}

/// The marker for a node with no recent info event. Dart localizes it.
pub(crate) const NODE_NOT_ANNOUNCING: &str = "NodeNotAnnouncing";

/// The marker for a node that announces `maintenance_mode = true` — the same
/// one the dispatcher returns for the daemon's `cant-do maintenance_mode`,
/// so the UI has one case to handle whichever way it is learned.
pub(crate) const MAINTENANCE_MODE: &str = "MaintenanceMode";

/// What a node's newest known info event said that matters here.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Announcement {
    /// The event's own `created_at` (unix seconds, the node's clock).
    pub(crate) announced_at: i64,
    /// Its `maintenance_mode` tag: the node refuses new orders and takes.
    pub(crate) maintenance: bool,
}

/// The verdict on a node's announcement.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Liveness {
    /// Announced recently and open for business.
    Live,
    /// Announced recently, and says it is in maintenance.
    Maintenance,
    /// The newest event known is too old: the node stopped publishing.
    Stale,
    /// No info event from this node has been seen at all.
    Missing,
}

/// Judge `snapshot` at `now` (unix seconds, the device's clock).
///
/// The two timestamps come from different clocks, and only one direction of
/// disagreement is tolerated for free: an event dated **after** `now` is
/// fresh, however far ahead. A device clock behind the node's is the common
/// skew, and it must never read a node that just announced as silent. The
/// other direction costs slack instead: a device clock running ahead eats
/// into the six minutes between a five-minute publication and the limit.
///
/// A stale snapshot is `Stale` whatever its maintenance tag said: a node
/// that is not announcing is not telling us anything current.
pub(crate) fn assess(snapshot: Option<Announcement>, now: i64) -> Liveness {
    let Some(announcement) = snapshot else {
        return Liveness::Missing;
    };
    let age = now.saturating_sub(announcement.announced_at);
    if age > MAX_ANNOUNCEMENT_AGE_SECS {
        return Liveness::Stale;
    }
    if announcement.maintenance {
        Liveness::Maintenance
    } else {
        Liveness::Live
    }
}

/// Read the `maintenance_mode` tag out of a Kind 38385 tag list. Only an
/// explicit `true` counts: a daemon that predates the tag publishes none, and
/// a blank or malformed value is not an announcement of anything.
pub(crate) fn parse_maintenance(tags: &[Vec<String>]) -> bool {
    tags.iter()
        .find(|t| t.first().map(String::as_str) == Some("maintenance_mode"))
        .and_then(|t| t.get(1))
        .is_some_and(|v| v.trim().eq_ignore_ascii_case("true"))
}

/// The newest announcement seen per node, keyed by the node's hex pubkey in
/// lower case. A handful of entries at most: the active node, and any other
/// whose info event a screen asked for.
static ANNOUNCEMENTS: LazyLock<Mutex<HashMap<String, Known>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// What is kept per node: its newest announcement, and how many copies of
/// the event have been read that were at least as new as the one known at
/// the time — the count [`ensure_live`] reads before and after a look to
/// tell "the relays hold nothing newer" from "nobody said anything current".
#[derive(Clone, Copy)]
struct Known {
    announcement: Announcement,
    current_copies: u64,
}

fn announcements() -> std::sync::MutexGuard<'static, HashMap<String, Known>> {
    // Every critical section is one map operation, so a poisoned lock holds
    // nothing half-written — and refusing it would switch the gate to
    // "missing" for the rest of the session.
    ANNOUNCEMENTS.lock().unwrap_or_else(PoisonError::into_inner)
}

fn key(node: &str) -> String {
    node.trim().to_ascii_lowercase()
}

/// Record that `node`'s info event, signed at `announced_at`, carried `tags`.
///
/// Called with every copy of the event a relay hands over, and relays do not
/// all hold the same revision: one the daemon lost its connection to keeps
/// serving the last copy it got. So an older event never replaces a newer
/// one — any signed copy proves the node was alive at its date, and the
/// newest proof is the one that counts.
pub(crate) fn note_announcement(node: &str, announced_at: i64, tags: &[Vec<String>]) {
    let seen = Announcement {
        announced_at,
        maintenance: parse_maintenance(tags),
    };
    let mut map = announcements();
    match map.get(&key(node)).copied() {
        // A copy from a relay that lags behind: it neither replaces what is
        // known nor counts as news about the node.
        Some(known) if known.announcement.announced_at > seen.announced_at => {}
        known => {
            map.insert(
                key(node),
                Known {
                    announcement: seen,
                    current_copies: known.map_or(0, |k| k.current_copies) + 1,
                },
            );
        }
    }
}

/// The newest announcement recorded for `node`, if any.
pub(crate) fn announcement_of(node: &str) -> Option<Announcement> {
    announcements().get(&key(node)).map(|known| known.announcement)
}

/// How many copies of `node`'s info event have been read that were current
/// when they arrived (see [`Known`]).
fn current_copies_read(node: &str) -> u64 {
    announcements()
        .get(&key(node))
        .map_or(0, |known| known.current_copies)
}

/// Fail unless `node` (hex pubkey) is announcing itself and open for new
/// orders and takes. See the module docs for the rule and for what this may
/// never gate.
///
/// Errors are the bare markers [`NODE_NOT_ANNOUNCING`] and
/// [`MAINTENANCE_MODE`].
pub(crate) async fn ensure_live(node: &str) -> Result<()> {
    ensure_live_among(
        node,
        crate::rt::unix_now,
        || async {
            matches!(
                crate::api::nostr::get_connection_state().await,
                Ok(crate::api::types::ConnectionState::Online)
            )
        },
        || fresh_look(node),
        || newest_peer_announcement(node, crate::rt::unix_now()),
    )
    .await
}

/// How many of the relays' newest info events are read to find when another
/// node last announced itself.
const PEER_SAMPLE: usize = 20;

/// When any **other** node on these relays last announced itself: the newest
/// `created_at` among their info events, as far as the relays answer within
/// [`EVERY_RELAY_WAIT`]. `None` when no relay hands one over.
///
/// It is the one reading of "now" this client can get that does not come
/// from the device's clock, and [`ensure_live_among`] says what it is for.
async fn newest_peer_announcement(node: &str, now: i64) -> Option<i64> {
    use nostr_sdk::prelude::*;

    let client = crate::api::nostr::get_pool().ok()?.client();
    let own = PublicKey::from_hex(node).ok()?;
    let filter = Filter::new()
        .kind(Kind::from(KIND_NODE_INFO))
        .limit(PEER_SAMPLE);
    let events = client
        .fetch_events(filter)
        .timeout(EVERY_RELAY_WAIT)
        .await
        .ok()?;
    newest_peer_at(events, &own, now)
}

/// The newest date among the info events in `events` that other nodes than
/// `own` signed, none later than `now`.
///
/// An event dated after the device's `now` is left out: it comes from a
/// clock ahead of this one, or was made up, and either way says nothing
/// about how far ahead this device's own clock may be. Only signed info
/// events addressed by their author's key count — what a node publishes
/// about itself — so a relay cannot pass anything else off as a peer.
fn newest_peer_at(
    events: impl IntoIterator<Item = nostr_sdk::prelude::Event>,
    own: &nostr_sdk::prelude::PublicKey,
    now: i64,
) -> Option<i64> {
    events
        .into_iter()
        .filter(|event| event.pubkey != *own && is_info_event_of(event, &event.pubkey))
        .map(|event| event.created_at.as_secs() as i64)
        .filter(|at| *at <= now)
        .max()
}

/// How long the patient look waits for every relay to answer.
const EVERY_RELAY_WAIT: std::time::Duration = std::time::Duration::from_secs(6);

/// The fresh look [`ensure_live`] takes before it refuses anything: the
/// quick one ([`look_again`]) and — only when that still leaves the node
/// short of live — a patient one that hears every relay out
/// ([`look_everywhere`]).
///
/// The quick look stops listening 750 ms after the first copy of the event.
/// A relay the daemon lost its connection to keeps serving the last revision
/// it got; when that relay is also the fastest to answer by more than that
/// grace, the quick look reads a node that is announcing as silent — or as
/// still in maintenance — and so would every retry. Refusing new orders on
/// that would be this gate's worst failure: the node is there and reachable
/// through the other relays. The second look costs up to
/// [`EVERY_RELAY_WAIT`], and only on the way to a refusal.
async fn fresh_look(node: &str) -> bool {
    fresh_look_with(
        node,
        crate::rt::unix_now,
        || look_again(node),
        || look_everywhere(node),
    )
    .await
}

/// [`fresh_look`] with the clock and the two looks injected. `true` when
/// either look read a copy of the event.
async fn fresh_look_with<Now, Quick, QuickFut, Patient, PatientFut>(
    node: &str,
    now: Now,
    quick: Quick,
    patient: Patient,
) -> bool
where
    Now: Fn() -> i64,
    Quick: FnOnce() -> QuickFut,
    QuickFut: std::future::Future<Output = bool>,
    Patient: FnOnce() -> PatientFut,
    PatientFut: std::future::Future<Output = bool>,
{
    let quick_read = quick().await;
    if assess(announcement_of(node), now()) == Liveness::Live {
        return quick_read;
    }
    let patient_read = patient().await;
    quick_read || patient_read
}

/// One patient look at `node`'s info event: every relay is heard out, and
/// the newest copy among them is what counts. Applied like [`look_again`],
/// and like it a look that brings nothing changes nothing.
async fn look_everywhere(node: &str) -> bool {
    look_again_with(
        node,
        fetch_from_every_relay,
        crate::api::nostr::apply_node_capabilities,
    )
    .await
}

/// The tags of `node_hex`'s newest info event among the copies of every relay
/// that answers within [`EVERY_RELAY_WAIT`], recorded as an announcement.
///
/// The same filter as `fetch_mostro_instance_tags`, read the slow way on
/// purpose: `fetch_events` returns once every relay has sent EOSE (or the
/// wait is over), where the streamed fetch takes the first copy and a short
/// grace.
async fn fetch_from_every_relay(node_hex: String) -> Result<Option<Vec<Vec<String>>>> {
    use nostr_sdk::prelude::*;

    let client = crate::api::nostr::get_pool()?.client();
    let pubkey =
        PublicKey::from_hex(&node_hex).map_err(|e| anyhow!("invalid pubkey hex: {e}"))?;
    let filter = Filter::new()
        .kind(Kind::from(KIND_NODE_INFO))
        .author(pubkey)
        .custom_tag(SingleLetterTag::LOWERCASE_D, &node_hex)
        .limit(1);
    let events = client
        .fetch_events(filter)
        .timeout(EVERY_RELAY_WAIT)
        .await
        .map_err(|e| anyhow!("fetch_events failed: {e}"))?;
    let Some(newest) = newest_info_event(events, &pubkey) else {
        return Ok(None);
    };
    let tags = newest
        .tags
        .iter()
        .map(|t| t.as_slice().to_vec())
        .collect::<Vec<Vec<String>>>();
    note_announcement(&node_hex, newest.created_at.as_secs() as i64, &tags);
    Ok(Some(tags))
}

/// The newest of `node`'s own info events among `events`
/// ([`is_info_event_of`] first, so nothing a relay made up is in the running).
fn newest_info_event(
    events: impl IntoIterator<Item = nostr_sdk::prelude::Event>,
    node: &nostr_sdk::prelude::PublicKey,
) -> Option<nostr_sdk::prelude::Event> {
    events
        .into_iter()
        .filter(|event| is_info_event_of(event, node))
        .max_by_key(crate::nostr::first_answer::replaceable_rank)
}

/// One fresh look at `node`'s info event, for [`ensure_live`].
///
/// The fetch itself refreshes the snapshot (`fetch_mostro_instance_tags`
/// records every event it reads). What it brought is then applied the way
/// the pool-online fetch applies it — difficulty, protocol version, escrow
/// mode, bond policy — so a node that only now started announcing, or
/// changed its difficulty since, is read correctly by the send that follows.
///
/// **A look that brings nothing changes nothing.** The pool-online fetch
/// (`fetch_and_set_node_capabilities`) forgets on an empty or failed fetch:
/// the difficulty goes to 0 on an empty one, the bond policy and the escrow
/// mode are cleared on both. That is right when the pool has just come
/// online and nothing held from before can be assumed current. Here it
/// would be wrong: this runs in the middle of a session, because the user
/// tapped "create" or "take", and one relay round trip that came back empty
/// must not cost the trades already under way the difficulty their next
/// message is mined at — a node that asks for proof of work drops an
/// under-mined `release` without a word. The gate then refuses the new
/// order or the take, and everything else keeps what it had.
async fn look_again(node: &str) -> bool {
    look_again_with(
        node,
        crate::api::nostr::fetch_mostro_instance_tags,
        crate::api::nostr::apply_node_capabilities,
    )
    .await
}

/// [`look_again`] with the fetch and the capability store injected. `true`
/// when a copy of the event was read — whatever its date.
async fn look_again_with<Fetch, FetchFut, Apply>(node: &str, fetch: Fetch, apply: Apply) -> bool
where
    Fetch: FnOnce(String) -> FetchFut,
    FetchFut: std::future::Future<Output = Result<Option<Vec<Vec<String>>>>>,
    Apply: FnOnce(&str, Result<Option<Vec<Vec<String>>>>),
{
    match fetch(node.to_string()).await {
        Ok(Some(tags)) => {
            apply(node, Ok(Some(tags)));
            true
        }
        Ok(None) => {
            crate::api::logging::blog_info(
                "nostr",
                format!(
                    "fresh look: no info event from node {} — what was known about it stays",
                    crate::api::logging::short_id(node),
                ),
            );
            false
        }
        Err(e) => {
            crate::api::logging::blog_warn(
                "nostr",
                format!(
                    "fresh look at node {} failed: {e} — what was known about it stays",
                    crate::api::logging::short_id(node),
                ),
            );
            false
        }
    }
}

/// [`ensure_live`] with its three inputs injected: the clock, whether a
/// relay can be reached, and the fresh look that refreshes the snapshot
/// ([`fresh_look`]) and says whether it read a copy of the event.
///
/// The reachability question comes before the fetch on purpose. With no
/// relay to ask, nothing can tell whether the node is announcing, and saying
/// "the node is silent" about a phone with no signal would send the user
/// looking for a problem that is not the node's. The gate then says nothing
/// and the send path reports the failure it meets, in its own words, exactly
/// as before this gate existed.
#[cfg(test)]
async fn ensure_live_with<Now, Online, OnlineFut, Refetch, RefetchFut>(
    node: &str,
    now: Now,
    relays_reachable: Online,
    refetch: Refetch,
) -> Result<()>
where
    Now: Fn() -> i64,
    Online: FnOnce() -> OnlineFut,
    OnlineFut: std::future::Future<Output = bool>,
    Refetch: FnOnce() -> RefetchFut,
    RefetchFut: std::future::Future<Output = bool>,
{
    // No word about any other node: the device's clock decides alone.
    ensure_live_among(node, now, relays_reachable, refetch, || async { None }).await
}

/// [`ensure_live`] with the clock, the reachability check, the fresh look
/// and the peers' newest announcement injected.
///
/// `peers` is asked only on the way to a refusal, and exists for one case:
/// **a device clock running ahead.** Every age here is "the device's now
/// minus the node's own date", so a phone ten minutes fast reads a node that
/// announced a minute ago as silent for eleven — and refused every new order
/// and take, for as long as its clock stayed wrong. The relays offer a
/// second opinion that needs no clock at all: when other nodes last
/// announced themselves. A node whose event is no more than
/// [`MAX_ANNOUNCEMENT_AGE_SECS`] older than the newest of theirs is as
/// current as anyone on those relays, and the disagreement is with the
/// device's clock, not with the node.
///
/// It can only relax the verdict where the relays back it, never tighten
/// it: with no peer event to compare with, the clock decides as before. And
/// what it lets through is a send, which reports a node that is really gone
/// by itself, as it did before this gate existed.
async fn ensure_live_among<Now, Online, OnlineFut, Refetch, RefetchFut, Peers, PeersFut>(
    node: &str,
    now: Now,
    relays_reachable: Online,
    refetch: Refetch,
    peers: Peers,
) -> Result<()>
where
    Now: Fn() -> i64,
    Online: FnOnce() -> OnlineFut,
    OnlineFut: std::future::Future<Output = bool>,
    Refetch: FnOnce() -> RefetchFut,
    RefetchFut: std::future::Future<Output = bool>,
    Peers: FnOnce() -> PeersFut,
    PeersFut: std::future::Future<Output = Option<i64>>,
{
    let first = assess(announcement_of(node), now());
    if first == Liveness::Live {
        return Ok(());
    }
    if !relays_reachable().await {
        crate::api::logging::blog_info(
            "nostr",
            format!(
                "node {} reads {first:?} but no relay is reachable — leaving it to the send",
                crate::api::logging::short_id(node),
            ),
        );
        return Ok(());
    }
    // One fresh look before refusing anything: the snapshot dates from the
    // last time the pool came online, and a node may have resumed publishing
    // or left maintenance since.
    let current_before = current_copies_read(node);
    // A copy that is older than what was already known comes from a relay
    // lagging behind and says nothing about the node today: only one at
    // least as new counts as having heard about it.
    let read_a_copy = refetch().await && current_copies_read(node) > current_before;
    let second = assess(announcement_of(node), now());
    crate::api::logging::blog_info(
        "nostr",
        format!(
            "node {} read {first:?}, {second:?} after a fresh look (copy read: {read_a_copy})",
            crate::api::logging::short_id(node),
        ),
    );
    match second {
        Liveness::Live => Ok(()),
        // Said by an event signed within the last eleven minutes — this look's
        // or the snapshot's: recent word from the node itself either way.
        Liveness::Maintenance => Err(anyhow!(MAINTENANCE_MODE)),
        // An old snapshot and a look that read nothing: nobody answered, so
        // nothing says the node stopped. The pool's "online" is a cached
        // state — one relay marked connected is enough for it — and a REQ can
        // still come back empty: refused at a relay's subscription cap,
        // sent down a socket that died behind a resume, or simply late. The
        // order went out before this gate existed, and it goes out now; if
        // the node is gone the send reports it.
        Liveness::Stale if !read_a_copy => Ok(()),
        // A relay handed over the newest event known and it is old by this
        // device's clock. Old next to what, though: before calling the node
        // silent, the same event is held against the newest any other node
        // published on these relays.
        Liveness::Stale => {
            let Some(own) = announcement_of(node) else {
                return Err(anyhow!(NODE_NOT_ANNOUNCING));
            };
            let abreast = peers()
                .await
                .is_some_and(|peer_at| {
                    peer_at.saturating_sub(own.announced_at) <= MAX_ANNOUNCEMENT_AGE_SECS
                });
            if !abreast {
                // Other nodes have announced since and this one has not —
                // or there is nobody to compare with: it stopped publishing.
                return Err(anyhow!(NODE_NOT_ANNOUNCING));
            }
            crate::api::logging::blog_warn(
                "nostr",
                format!(
                    "node {} announced {} s ago by this device's clock but is abreast of the other nodes on its relays — the device clock looks ahead; not refusing",
                    crate::api::logging::short_id(node),
                    now().saturating_sub(own.announced_at),
                ),
            );
            // Its last word still counts: a node in maintenance says so in
            // the very event that proved it current.
            if own.maintenance {
                Err(anyhow!(MAINTENANCE_MODE))
            } else {
                Ok(())
            }
        }
        // No relay has ever had an info event from this node — which also
        // leaves the send without the node's proof-of-work difficulty.
        Liveness::Missing => Err(anyhow!(NODE_NOT_ANNOUNCING)),
    }
}

/// Forget every announcement. Only for tests, which share the process-wide
/// store and must not inherit a verdict from one another.
#[cfg(test)]
pub(crate) fn forget_for_test(node: &str) {
    announcements().remove(&key(node));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    const NOW: i64 = 1_791_130_933;

    fn tag(name: &str, value: &str) -> Vec<String> {
        vec![name.to_string(), value.to_string()]
    }

    fn open_at(announced_at: i64) -> Option<Announcement> {
        Some(Announcement {
            announced_at,
            maintenance: false,
        })
    }

    /// A node of its own per test: the store is process-wide and tests run
    /// in parallel.
    fn node(tag: &str) -> String {
        format!("liveness-test-node-{tag}")
    }

    #[test]
    fn a_recent_announcement_is_live() {
        // Just signed, one publication old, two missed and still inside.
        for age in [0, 1, 300, 600, MAX_ANNOUNCEMENT_AGE_SECS] {
            assert_eq!(assess(open_at(NOW - age), NOW), Liveness::Live, "age {age}");
        }
    }

    #[test]
    fn an_old_announcement_is_stale() {
        for age in [MAX_ANNOUNCEMENT_AGE_SECS + 1, 3_600, 30 * 24 * 3_600] {
            assert_eq!(
                assess(open_at(NOW - age), NOW),
                Liveness::Stale,
                "age {age}"
            );
        }
    }

    #[test]
    fn no_announcement_is_missing() {
        assert_eq!(assess(None, NOW), Liveness::Missing);
    }

    #[test]
    fn a_recent_maintenance_announcement_is_maintenance() {
        let announcement = Some(Announcement {
            announced_at: NOW - 10,
            maintenance: true,
        });
        assert_eq!(assess(announcement, NOW), Liveness::Maintenance);
    }

    /// Stale wins over maintenance: a node that stopped announcing an hour
    /// ago while in maintenance is, as far as anyone can tell, off.
    #[test]
    fn a_stale_maintenance_announcement_is_stale() {
        let announcement = Some(Announcement {
            announced_at: NOW - 3_600,
            maintenance: true,
        });
        assert_eq!(assess(announcement, NOW), Liveness::Stale);
    }

    /// A device clock behind the node's dates the node's events in the
    /// future. That is skew, not silence — at any distance.
    #[test]
    fn an_announcement_from_the_future_is_fresh() {
        for ahead in [1, 60, 3_600, 365 * 24 * 3_600] {
            assert_eq!(
                assess(open_at(NOW + ahead), NOW),
                Liveness::Live,
                "{ahead}s ahead"
            );
        }
        // No arithmetic trap at the edges of the type either.
        assert_eq!(assess(open_at(i64::MAX), i64::MIN), Liveness::Live);
        assert_eq!(assess(open_at(i64::MIN), i64::MAX), Liveness::Stale);
    }

    /// The tag, read from the info events v0.19.2 published
    /// (`public-events.json`): always present, `false` on a node in service.
    #[test]
    fn the_maintenance_tag_is_read_from_the_info_event() {
        let in_service = vec![
            tag("mostro_version", "0.19.2"),
            tag("protocol_version", "2"),
            tag("bond_enabled", "false"),
            tag("maintenance_mode", "false"),
        ];
        assert!(!parse_maintenance(&in_service));

        let draining = vec![tag("protocol_version", "2"), tag("maintenance_mode", "true")];
        assert!(parse_maintenance(&draining));
        assert!(parse_maintenance(&[tag("maintenance_mode", " TRUE ")]));

        // A daemon that predates the tag, and values that announce nothing.
        assert!(!parse_maintenance(&[tag("protocol_version", "2")]));
        assert!(!parse_maintenance(&[tag("maintenance_mode", "")]));
        assert!(!parse_maintenance(&[tag("maintenance_mode", "yes")]));
        assert!(!parse_maintenance(&[vec!["maintenance_mode".to_string()]]));
    }

    /// Relays do not all hold the same revision. The newest copy seen is the
    /// proof of life; an older one arriving later changes nothing.
    #[test]
    fn an_older_copy_never_replaces_a_newer_one() {
        let n = node("newest-wins");
        note_announcement(&n, NOW, &[tag("maintenance_mode", "false")]);
        note_announcement(&n, NOW - 900, &[tag("maintenance_mode", "true")]);
        assert_eq!(announcement_of(&n), open_at(NOW));

        // A newer one does, tag and all.
        note_announcement(&n, NOW + 300, &[tag("maintenance_mode", "true")]);
        assert_eq!(
            announcement_of(&n),
            Some(Announcement {
                announced_at: NOW + 300,
                maintenance: true,
            })
        );
        // The same revision re-read is the same announcement.
        note_announcement(&n, NOW + 300, &[tag("maintenance_mode", "true")]);
        assert_eq!(
            announcement_of(&n).map(|a| a.announced_at),
            Some(NOW + 300)
        );
        forget_for_test(&n);
    }

    /// A node switch must find nothing for the new node, however fresh the
    /// previous node's snapshot is — and the key ignores case.
    #[test]
    fn a_snapshot_never_serves_another_node() {
        let a = node("scope-A");
        let b = node("scope-B");
        note_announcement(&a, NOW, &[]);
        assert_eq!(announcement_of(&b), None);
        assert_eq!(assess(announcement_of(&b), NOW), Liveness::Missing);
        assert_eq!(announcement_of(&a.to_uppercase()), open_at(NOW));
        forget_for_test(&a);
    }

    /// Counts the refetches a check triggers.
    struct Fetches(AtomicU32);

    impl Fetches {
        fn new() -> Self {
            Self(AtomicU32::new(0))
        }
        fn count(&self) -> u32 {
            self.0.load(Ordering::SeqCst)
        }
    }

    #[tokio::test]
    async fn a_live_node_is_passed_without_asking_anyone() {
        let n = node("gate-live");
        note_announcement(&n, NOW - 30, &[tag("maintenance_mode", "false")]);
        let fetches = Fetches::new();

        ensure_live_with(
            &n,
            || NOW,
            || async { panic!("a live node needs no reachability check") },
            || async {
                fetches.0.fetch_add(1, Ordering::SeqCst);
                true
            },
        )
        .await
        .expect("a node that just announced is live");

        assert_eq!(fetches.count(), 0);
        forget_for_test(&n);
    }

    /// The case the gate exists for: the daemon stopped, its last info event
    /// is still on the relays, and a fresh look finds the same old event.
    #[tokio::test]
    async fn a_node_that_stopped_announcing_is_refused_after_one_fresh_look() {
        let n = node("gate-stale");
        note_announcement(&n, NOW - 3_600, &[tag("maintenance_mode", "false")]);
        let fetches = Fetches::new();

        let err = ensure_live_with(
            &n,
            || NOW,
            || async { true },
            || async {
                fetches.0.fetch_add(1, Ordering::SeqCst);
                // The relays still hold the hour-old event.
                note_announcement(&n, NOW - 3_600, &[tag("maintenance_mode", "false")]);
                true
            },
        )
        .await
        .unwrap_err();

        assert_eq!(err.to_string(), "NodeNotAnnouncing");
        assert_eq!(fetches.count(), 1, "exactly one fresh look");
        forget_for_test(&n);
    }

    /// A node with no info event at all used to end in
    /// `NodeCapabilitiesUnknown` with nothing re-fetching. Now it gets one
    /// look, and the answer names the node.
    #[tokio::test]
    async fn a_node_that_never_announced_is_refused_after_one_fresh_look() {
        let n = node("gate-missing");
        let fetches = Fetches::new();

        let err = ensure_live_with(
            &n,
            || NOW,
            || async { true },
            || async {
                fetches.0.fetch_add(1, Ordering::SeqCst);
                false
            },
        )
        .await
        .unwrap_err();

        assert_eq!(err.to_string(), "NodeNotAnnouncing");
        assert_eq!(fetches.count(), 1);
    }

    /// An aged snapshot is not evidence: the app has simply not looked for a
    /// while. When the look then reads nothing — every REQ refused, dropped
    /// or late — nobody has said the node stopped, and the order goes out as
    /// it did before the gate existed.
    #[tokio::test]
    async fn an_aged_snapshot_and_a_look_that_reads_nothing_refuse_nothing() {
        let n = node("gate-aged-blind");
        note_announcement(&n, NOW - 3_600, &[tag("maintenance_mode", "false")]);
        let fetches = Fetches::new();

        ensure_live_with(
            &n,
            || NOW,
            || async { true },
            || async {
                fetches.0.fetch_add(1, Ordering::SeqCst);
                false
            },
        )
        .await
        .expect("with no relay answering, silence is not the node's");

        assert_eq!(fetches.count(), 1, "it did look");
        forget_for_test(&n);
    }

    /// The snapshot dates from the last time the pool came online. A node
    /// that resumed since is found by the fresh look, not refused on the
    /// stale one.
    #[tokio::test]
    async fn a_node_that_resumed_announcing_is_passed_by_the_fresh_look() {
        for start in ["stale", "missing"] {
            let n = node(&format!("gate-resumed-{start}"));
            if start == "stale" {
                note_announcement(&n, NOW - 3_600, &[]);
            }
            ensure_live_with(
                &n,
                || NOW,
                || async { true },
                || async {
                    note_announcement(&n, NOW - 5, &[tag("maintenance_mode", "false")]);
                    true
                },
            )
            .await
            .unwrap_or_else(|e| panic!("{start}: a node announcing again is live, got {e}"));
            forget_for_test(&n);
        }
    }

    #[tokio::test]
    async fn a_node_in_maintenance_is_refused_with_the_maintenance_marker() {
        let n = node("gate-maintenance");
        note_announcement(&n, NOW - 30, &[tag("maintenance_mode", "true")]);
        let fetches = Fetches::new();

        let err = ensure_live_with(
            &n,
            || NOW,
            || async { true },
            || async {
                fetches.0.fetch_add(1, Ordering::SeqCst);
                note_announcement(&n, NOW - 1, &[tag("maintenance_mode", "true")]);
                true
            },
        )
        .await
        .unwrap_err();

        assert_eq!(err.to_string(), "MaintenanceMode");
        assert_eq!(
            fetches.count(),
            1,
            "maintenance is confirmed by a fresh look before refusing"
        );
        forget_for_test(&n);
    }

    /// The daemon republishes the moment the flag flips, so a node out of
    /// maintenance says so at once — and is not held to the snapshot.
    #[tokio::test]
    async fn a_node_that_left_maintenance_is_passed_by_the_fresh_look() {
        let n = node("gate-left-maintenance");
        note_announcement(&n, NOW - 120, &[tag("maintenance_mode", "true")]);

        ensure_live_with(
            &n,
            || NOW,
            || async { true },
            || async {
                note_announcement(&n, NOW - 2, &[tag("maintenance_mode", "false")]);
                true
            },
        )
        .await
        .expect("the newer announcement says the node is back");
        forget_for_test(&n);
    }

    /// With no relay to ask, the gate says nothing: silence from the node
    /// cannot be told from a device with no connection, and the send path
    /// reports that failure itself. This is also what leaves every test
    /// without a relay pool untouched.
    #[tokio::test]
    async fn without_a_reachable_relay_the_gate_abstains() {
        for start in ["stale", "missing", "maintenance"] {
            let n = node(&format!("gate-offline-{start}"));
            match start {
                "stale" => note_announcement(&n, NOW - 3_600, &[]),
                "maintenance" => {
                    note_announcement(&n, NOW - 30, &[tag("maintenance_mode", "true")])
                }
                _ => {}
            }
            ensure_live_with(
                &n,
                || NOW,
                || async { false },
                || async { panic!("no relay is reachable: nothing to fetch from") },
            )
            .await
            .unwrap_or_else(|e| panic!("{start}: the gate must abstain offline, got {e}"));
            forget_for_test(&n);
        }
    }

    /// The real gate, in a process with no relay pool: it abstains, so the
    /// create and take paths behave as they did before it existed.
    #[tokio::test]
    async fn the_gate_abstains_when_there_is_no_relay_pool() {
        ensure_live(&node("gate-no-pool"))
            .await
            .expect("no pool, no verdict");
    }

    /// The snapshot has one feeder: the fetch of the node's info event, which
    /// used to hand back the tags and drop the event's date. Without that
    /// call the store stays empty and the gate reads every node as missing —
    /// it would then refetch on each attempt and, online, refuse them all —
    /// so the wiring is pinned on the source (the fetch needs a relay pool).
    #[test]
    fn the_info_event_fetch_feeds_the_snapshot() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("src")
            .join("api")
            .join("nostr.rs");
        let source = std::fs::read_to_string(path).expect("read api/nostr.rs");
        let start = source
            .find("pub async fn fetch_mostro_instance_tags(")
            .expect("fetch_mostro_instance_tags exists");
        let body = &source[start..];
        let body = &body[..body.find("\n}\n").expect("fetch_mostro_instance_tags ends")];
        let feeds = body
            .find("node_liveness::note_announcement(")
            .expect("the fetch must record the announcement");
        assert!(
            body[feeds..].contains("event.created_at"),
            "with the event's own date"
        );
        // Whose event it is gets checked before the newest copy is picked:
        // a relay is not held to the filter, and a forged event dated later
        // would otherwise win.
        let checks = body
            .find("node_liveness::is_info_event_of(&event, &pubkey)")
            .expect("the fetch must check whose event it reads");
        let picks = body
            .find("first_answer::newest_answer(")
            .expect("the fetch picks the newest copy");
        assert!(checks < picks && picks < feeds);
        // And the fresh look the gate takes goes through that same fetch —
        // not through the pool-online one, which forgets what it knew when a
        // fetch comes back empty.
        let own = include_str!("node_liveness.rs");
        // (Searched by its full signature: a shorter needle would find this
        // very line first.)
        let look = own
            .find("async fn look_again(node: &str) -> bool {")
            .expect("look_again exists");
        let look = &own[look..];
        let look = &look[..look.find("\n}\n").expect("it ends")];
        assert!(look.contains("crate::api::nostr::fetch_mostro_instance_tags,"));
        assert!(look.contains("crate::api::nostr::apply_node_capabilities,"));
        let production = &own[..own.find("#[cfg(test)]\nmod tests {").expect("tests follow")];
        assert!(
            !production.contains("fetch_and_set_node_capabilities()")
                && !production.contains("fetch_and_set_node_capabilities,"),
            "the gate must not call the fetch that clears on failure"
        );
        // The patient look reads every relay's copy and picks among them
        // through the same check.
        let patient = production
            .find("async fn fetch_from_every_relay(")
            .expect("the patient fetch exists");
        let patient = &production[patient..];
        let patient = &patient[..patient.find("\n}\n").expect("it ends")];
        assert!(patient.contains("newest_info_event(events, &pubkey)"));
        assert!(!patient.contains("max_by_key("), "never the newest of whatever came back");
    }

    // ── A device clock running ahead ────────────────────────────────────────

    /// How far ahead the device's clock runs in these tests: enough to read
    /// an event signed a minute ago as older than the limit.
    const AHEAD: i64 = 900;

    /// The reported failure: a phone fifteen minutes fast. The node announced
    /// two minutes ago; by the phone's clock that is seventeen, and every new
    /// order and take was refused for as long as the clock stayed wrong. The
    /// relays say otherwise — another node announced a few seconds ago, and
    /// this one is two minutes behind it, not seventeen.
    #[tokio::test]
    async fn a_clock_ahead_does_not_silence_a_node_abreast_of_its_peers() {
        let n = node("skew-live");
        let true_now = NOW - AHEAD;
        note_announcement(&n, true_now - 120, &[tag("maintenance_mode", "false")]);

        ensure_live_among(
            &n,
            || NOW,
            || async { true },
            || async {
                // The relays hand over the same event: nothing newer exists.
                note_announcement(&n, true_now - 120, &[tag("maintenance_mode", "false")]);
                true
            },
            || async { Some(true_now - 20) },
        )
        .await
        .expect("a node abreast of its peers is announcing, whatever the clock says");
        forget_for_test(&n);
    }

    /// The clock is right and the node is gone: other nodes went on
    /// announcing and this one stopped fifty minutes ago.
    #[tokio::test]
    async fn a_node_its_peers_left_behind_is_silent() {
        let n = node("skew-dead");
        note_announcement(&n, NOW - 3_000, &[tag("maintenance_mode", "false")]);

        let err = ensure_live_among(
            &n,
            || NOW,
            || async { true },
            || async {
                note_announcement(&n, NOW - 3_000, &[tag("maintenance_mode", "false")]);
                true
            },
            || async { Some(NOW - 30) },
        )
        .await
        .unwrap_err();

        assert_eq!(err.to_string(), "NodeNotAnnouncing");
        forget_for_test(&n);
    }

    /// The limit is the same one, measured from the peers instead of from
    /// the clock: exactly at it the node is abreast, a second past it is not.
    #[tokio::test]
    async fn abreast_is_the_same_eleven_minutes_measured_from_the_peers() {
        for (behind, abreast) in [
            (MAX_ANNOUNCEMENT_AGE_SECS, true),
            (MAX_ANNOUNCEMENT_AGE_SECS + 1, false),
        ] {
            let n = node(&format!("skew-edge-{behind}"));
            let peer_at = NOW - AHEAD;
            let own_at = peer_at - behind;
            note_announcement(&n, own_at, &[]);

            let verdict = ensure_live_among(
                &n,
                || NOW,
                || async { true },
                || async {
                    note_announcement(&n, own_at, &[]);
                    true
                },
                || async { Some(peer_at) },
            )
            .await;

            assert_eq!(verdict.is_ok(), abreast, "{behind} s behind its peers");
            forget_for_test(&n);
        }
    }

    /// A node that announced after every peer on the relays is not behind
    /// any of them.
    #[tokio::test]
    async fn a_node_ahead_of_its_peers_is_abreast() {
        let n = node("skew-newest");
        let true_now = NOW - AHEAD;
        note_announcement(&n, true_now - 10, &[]);

        ensure_live_among(
            &n,
            || NOW,
            || async { true },
            || async {
                note_announcement(&n, true_now - 10, &[]);
                true
            },
            || async { Some(true_now - 200) },
        )
        .await
        .expect("the newest announcement on the relays is not a silent node");
        forget_for_test(&n);
    }

    /// Being abreast proves the event current — and a current event that
    /// says maintenance is the node refusing new orders.
    #[tokio::test]
    async fn a_clock_ahead_still_hears_maintenance() {
        let n = node("skew-maintenance");
        let true_now = NOW - AHEAD;
        note_announcement(&n, true_now - 60, &[tag("maintenance_mode", "true")]);

        let err = ensure_live_among(
            &n,
            || NOW,
            || async { true },
            || async {
                note_announcement(&n, true_now - 60, &[tag("maintenance_mode", "true")]);
                true
            },
            || async { Some(true_now - 5) },
        )
        .await
        .unwrap_err();

        assert_eq!(err.to_string(), "MaintenanceMode");
        forget_for_test(&n);
    }

    /// The peers are a second opinion on the way to a refusal, nothing else:
    /// a live node, an unreachable pool and a look nobody answered never ask
    /// for it.
    #[tokio::test]
    async fn the_peers_are_asked_only_on_the_way_to_a_refusal() {
        async fn never() -> Option<i64> {
            panic!("no refusal is at stake: the peers must not be asked")
        }

        let live = node("skew-unasked-live");
        note_announcement(&live, NOW - 60, &[]);
        ensure_live_among(&live, || NOW, || async { true }, || async { true }, never)
            .await
            .expect("live");
        forget_for_test(&live);

        let offline = node("skew-unasked-offline");
        note_announcement(&offline, NOW - 3_600, &[]);
        ensure_live_among(&offline, || NOW, || async { false }, || async { true }, never)
            .await
            .expect("left to the send");
        forget_for_test(&offline);

        let unanswered = node("skew-unasked-silent-relays");
        note_announcement(&unanswered, NOW - 3_600, &[]);
        ensure_live_among(&unanswered, || NOW, || async { true }, || async { false }, never)
            .await
            .expect("nobody answered: not the node's silence");
        forget_for_test(&unanswered);
    }

    /// What counts as a peer's announcement: an info event another node
    /// signed about itself, dated no later than this device's now.
    #[test]
    fn a_peer_is_another_nodes_own_signed_info_event() {
        use nostr_sdk::prelude::*;
        let own = Keys::generate();
        let own_hex = own.public_key().to_hex();
        let peer = Keys::generate();
        let peer_hex = peer.public_key().to_hex();
        let other = Keys::generate();
        let other_hex = other.public_key().to_hex();

        let at = |events: Vec<Event>| newest_peer_at(events, &own.public_key(), NOW);

        // The newest of the peers', whatever order the relays send them in.
        assert_eq!(
            at(vec![
                info_event(&peer, &peer_hex, (NOW - 200) as u64, "false"),
                info_event(&other, &other_hex, (NOW - 40) as u64, "false"),
                info_event(&peer, &peer_hex, (NOW - 500) as u64, "false"),
            ]),
            Some(NOW - 40)
        );
        // The node's own event is not a second opinion on itself.
        assert_eq!(
            at(vec![info_event(&own, &own_hex, (NOW - 5) as u64, "false")]),
            None
        );
        // Dated after this device's now: no measure of how fast its clock is.
        assert_eq!(
            at(vec![
                info_event(&peer, &peer_hex, (NOW + 60) as u64, "false"),
                info_event(&other, &other_hex, (NOW - 300) as u64, "false"),
            ]),
            Some(NOW - 300)
        );
        // Not about its author, and not an info event at all.
        assert_eq!(
            at(vec![info_event(&peer, &other_hex, (NOW - 5) as u64, "false")]),
            None
        );
        let note = EventBuilder::new(Kind::TextNote, "hello")
            .tag(Tag::parse(["d", peer_hex.as_str()]).unwrap())
            .custom_created_at(Timestamp::from((NOW - 5) as u64))
            .finalize(&peer)
            .unwrap();
        assert_eq!(at(vec![note]), None);
        // A date rewritten under a signature that covered another.
        let mut json = serde_json::to_value(info_event(&peer, &peer_hex, (NOW - 900) as u64, "false")).unwrap();
        json["created_at"] = serde_json::json!(NOW - 5);
        let redated: Event = serde_json::from_value(json).unwrap();
        assert_eq!(at(vec![redated]), None);
        assert_eq!(at(vec![]), None);
    }

    fn info_tags() -> Vec<Vec<String>> {
        vec![
            tag("protocol_version", "2"),
            tag("pow", "12"),
            tag("maintenance_mode", "false"),
        ]
    }

    /// The fresh look found the node's info event: everything it says is
    /// taken, the way the pool-online fetch takes it — so a node that only
    /// now started announcing is also known to speak this protocol by the
    /// time the send that follows asks.
    /// A relay lagging behind hands over a copy older than the one already
    /// known. That is no news about the node: with nothing current read, the
    /// gate has not heard that the node stopped, and abstains.
    #[tokio::test]
    async fn a_lagging_relays_older_copy_is_not_evidence_that_the_node_stopped() {
        let n = node("gate-lagging-relay");
        // Known since the app last looked, twelve minutes ago.
        note_announcement(&n, NOW - 720, &[tag("maintenance_mode", "false")]);

        ensure_live_with(
            &n,
            || NOW,
            || async { true },
            || async {
                // The only relay that answers still holds an hour-old copy.
                note_announcement(&n, NOW - 3_600, &[tag("maintenance_mode", "false")]);
                true
            },
        )
        .await
        .expect("an older copy says nothing about the node today");

        assert_eq!(
            announcement_of(&n),
            open_at(NOW - 720),
            "and it does not replace what was known"
        );
        forget_for_test(&n);
    }

    fn info_event(
        keys: &nostr_sdk::prelude::Keys,
        d: &str,
        created_at: u64,
        maintenance: &str,
    ) -> nostr_sdk::prelude::Event {
        use nostr_sdk::prelude::*;
        EventBuilder::new(Kind::from(KIND_NODE_INFO), "")
            .tag(Tag::parse(["d", d]).unwrap())
            .tag(Tag::parse(["maintenance_mode", maintenance]).unwrap())
            .custom_created_at(Timestamp::from(created_at))
            .finalize(keys)
            .unwrap()
    }

    /// A relay answers a REQ with whatever it likes, and the SDK does not
    /// hold it to the filter. Only the node's own, signed event is the
    /// node's info event.
    #[test]
    fn only_the_nodes_own_signed_event_is_its_info_event() {
        use nostr_sdk::prelude::*;
        let node = Keys::generate();
        let node_hex = node.public_key().to_hex();
        let stranger = Keys::generate();

        let genuine = info_event(&node, &node_hex, NOW as u64, "false");
        assert!(is_info_event_of(&genuine, &node.public_key()));
        // The daemon writes its key in lower case; an upper-case `d` is the
        // same address.
        let upper = info_event(&node, &node_hex.to_uppercase(), NOW as u64, "false");
        assert!(is_info_event_of(&upper, &node.public_key()));

        // Signed by someone else, even addressed to the node's key.
        let foreign = info_event(&stranger, &node_hex, NOW as u64, "true");
        assert!(!is_info_event_of(&foreign, &node.public_key()));
        // The node's own event of another kind, or for another address.
        let other_kind = EventBuilder::new(Kind::TextNote, "")
            .tag(Tag::parse(["d", node_hex.as_str()]).unwrap())
            .finalize(&node)
            .unwrap();
        assert!(!is_info_event_of(&other_kind, &node.public_key()));
        let other_d = info_event(&node, &stranger.public_key().to_hex(), NOW as u64, "false");
        assert!(!is_info_event_of(&other_d, &node.public_key()));
        // The node's event with a tag rewritten on the way: every field
        // check still passes, only the signature gives it away.
        let mut json: serde_json::Value = serde_json::from_str(&genuine.as_json()).unwrap();
        json["tags"][1][1] = serde_json::Value::String("true".to_string());
        let rewritten = Event::from_json(json.to_string()).unwrap();
        assert!(!is_info_event_of(&rewritten, &node.public_key()));
    }

    /// What an unchecked reader would have swallowed: an event from a
    /// throwaway key, dated a year ahead, saying the node is in maintenance.
    /// It must not be in the running at all — picked as the newest, it would
    /// refuse every new order and take for the rest of the session.
    #[test]
    fn a_forged_newer_event_cannot_shadow_the_nodes_own() {
        use nostr_sdk::prelude::*;
        let node = Keys::generate();
        let node_hex = node.public_key().to_hex();
        let attacker = Keys::generate();
        let genuine = info_event(&node, &node_hex, NOW as u64, "false");
        let forged = info_event(
            &attacker,
            &node_hex,
            NOW as u64 + 365 * 24 * 3_600,
            "true",
        );

        let newest = newest_info_event([forged.clone(), genuine.clone()], &node.public_key())
            .expect("the node's own event is there");
        assert_eq!(newest.id, genuine.id);
        assert!(newest_info_event([forged], &node.public_key()).is_none());

        // Two genuine revisions: the newer one, as before.
        let later = info_event(&node, &node_hex, NOW as u64 + 300, "true");
        let newest = newest_info_event([genuine, later.clone()], &node.public_key()).unwrap();
        assert_eq!(newest.id, later.id);
    }

    /// The patient look is the way out of a stale copy served by the fastest
    /// relay: taken only when the quick one left the node short of live.
    #[tokio::test]
    async fn every_relay_is_heard_out_only_on_the_way_to_a_refusal() {
        // Arrange — the quick look finds the node announcing.
        let live = node("fresh-look-live");
        let patient = Fetches::new();

        // Act
        fresh_look_with(
            &live,
            || NOW,
            || async {
                note_announcement(&live, NOW - 30, &[]);
                true
            },
            || async {
                patient.0.fetch_add(1, Ordering::SeqCst);
                false
            },
        )
        .await;

        // Assert
        assert_eq!(patient.count(), 0, "a live node costs no second look");
        forget_for_test(&live);

        // Arrange — the fastest relay holds a copy from an hour ago; the
        // others have the one the node signed a minute ago.
        let stale_first = node("fresh-look-stale-relay");

        // Act
        fresh_look_with(
            &stale_first,
            || NOW,
            || async {
                note_announcement(&stale_first, NOW - 3_600, &[]);
                true
            },
            || async {
                patient.0.fetch_add(1, Ordering::SeqCst);
                note_announcement(&stale_first, NOW - 60, &[]);
                true
            },
        )
        .await;

        // Assert — heard out, and the node is live after all.
        assert_eq!(patient.count(), 1);
        assert_eq!(assess(announcement_of(&stale_first), NOW), Liveness::Live);
        forget_for_test(&stale_first);

        // A node no relay has anything recent for stays refused, after both.
        let silent = node("fresh-look-silent");
        fresh_look_with(
            &silent,
            || NOW,
            || async {
                note_announcement(&silent, NOW - 3_600, &[]);
                true
            },
            || async {
                patient.0.fetch_add(1, Ordering::SeqCst);
                false
            },
        )
        .await;
        assert_eq!(patient.count(), 2);
        assert_eq!(assess(announcement_of(&silent), NOW), Liveness::Stale);
        forget_for_test(&silent);
    }

    /// A stale maintenance flag is the same trap: the relay that missed the
    /// node leaving maintenance must not keep its orders refused.
    #[tokio::test]
    async fn a_stale_maintenance_copy_does_not_outlive_the_patient_look() {
        let n = node("fresh-look-maintenance");

        fresh_look_with(
            &n,
            || NOW,
            || async {
                note_announcement(&n, NOW - 400, &[tag("maintenance_mode", "true")]);
                true
            },
            || async {
                note_announcement(&n, NOW - 20, &[tag("maintenance_mode", "false")]);
                true
            },
        )
        .await;

        assert_eq!(assess(announcement_of(&n), NOW), Liveness::Live);
        forget_for_test(&n);
    }

    #[tokio::test]
    async fn a_fresh_look_applies_what_it_brought() {
        let n = node("look-found");
        let applied = Mutex::new(Vec::new());

        look_again_with(
            &n,
            |asked: String| async move {
                assert_eq!(asked, node("look-found"), "the node the gate is judging");
                Ok(Some(info_tags()))
            },
            |applied_to: &str, fetched: Result<Option<Vec<Vec<String>>>>| {
                applied
                    .lock()
                    .unwrap()
                    .push((applied_to.to_string(), fetched.ok().flatten()));
            },
        )
        .await;

        assert_eq!(
            applied.into_inner().unwrap(),
            vec![(n, Some(info_tags()))],
            "applied once, for that node, with the tags the look brought"
        );
    }

    /// The fresh look came back empty, or failed. The pool-online fetch
    /// would now reset the difficulty to 0 and clear the bond policy and the
    /// escrow mode; from the gate that would break the next message of a
    /// trade already under way, on a node that asks for proof of work. So
    /// nothing is applied at all: the stores keep what they had.
    #[tokio::test]
    async fn a_fresh_look_that_brings_nothing_changes_nothing() {
        for outcome in ["empty", "failed"] {
            let n = node(&format!("look-{outcome}"));
            let applied = Fetches::new();

            look_again_with(
                &n,
                |_asked: String| async move {
                    match outcome {
                        "empty" => Ok(None),
                        _ => Err(anyhow!("stream_events failed: timeout")),
                    }
                },
                |_: &str, _: Result<Option<Vec<Vec<String>>>>| {
                    applied.0.fetch_add(1, Ordering::SeqCst);
                },
            )
            .await;

            assert_eq!(
                applied.count(),
                0,
                "{outcome}: a look that brought nothing must not touch what is known"
            );
        }
    }

    /// The real look, in a process with no relay pool: the fetch fails at
    /// once and nothing panics or waits.
    #[tokio::test]
    async fn the_fresh_look_survives_having_no_relay_pool() {
        look_again(&node("look-no-pool")).await;
    }

    /// The gate is for new business. A user in a trade must be able to act
    /// on it — send fiat, release, cancel, dispute, add an invoice, rate —
    /// whatever the node last announced, so nothing but a new order and a
    /// take may call it; and both call it before anything is derived, so a
    /// silent node costs no trade key index.
    #[test]
    fn the_gate_stands_only_in_front_of_a_new_order_and_a_take() {
        fn rust_files(dir: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
            for entry in std::fs::read_dir(dir).expect("read src").flatten() {
                let path = entry.path();
                if path.is_dir() {
                    rust_files(&path, out);
                } else if path.extension().is_some_and(|ext| ext == "rs") {
                    out.push(path);
                }
            }
        }
        let name_of = |path: &std::path::Path| {
            path.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string()
        };

        let src = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
        let mut files = Vec::new();
        rust_files(&src, &mut files);
        let call = "node_liveness::ensure_live(";
        let mut callers = Vec::new();
        let mut orders = String::new();
        for file in files {
            let name = name_of(&file);
            // This module, and the generated bridge (which names no such call).
            if name == "node_liveness.rs" || name == "frb_generated.rs" {
                continue;
            }
            let body = std::fs::read_to_string(&file).expect("read file");
            let calls = body.matches(call).count();
            if calls > 0 {
                let module = file.parent().map(name_of).unwrap_or_default();
                callers.push((format!("{module}/{name}"), calls));
            }
            if name == "orders.rs" && file.parent().map(name_of).as_deref() == Some("api") {
                orders = body;
            }
        }
        assert_eq!(
            callers,
            vec![("api/orders.rs".to_string(), 2)],
            "only create_order and take_order may be gated on the node's liveness"
        );

        for (function, must_follow) in [
            (
                "async fn create_order_once(",
                &["protocol_version::ensure_supported(", "derive_trade_key()"][..],
            ),
            ("async fn take_order_once(", &["derive_trade_key()"][..]),
        ] {
            let start = orders
                .find(function)
                .unwrap_or_else(|| panic!("{function} not found in api/orders.rs"));
            let end = start
                + orders[start..]
                    .find("\n}\n")
                    .unwrap_or_else(|| panic!("{function} has no end"));
            let body = &orders[start..end];
            let gate = body
                .find(call)
                .unwrap_or_else(|| panic!("{function} is not gated"));
            for later in must_follow {
                let at = body
                    .find(later)
                    .unwrap_or_else(|| panic!("{function} no longer calls {later}"));
                assert!(
                    gate < at,
                    "{function} must check the node's liveness before {later}"
                );
            }
        }
    }
}
