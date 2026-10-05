//! The community's own card, read from its relays.
//!
//! The operator's panel describes the community in a signed card — name,
//! currency, payment methods, website, contact (`api::community`). It used to
//! travel out of band only, as a QR or a link, and this client serves one
//! compiled-in community: no screen takes a card any more. So the card is
//! read from where everything else about the node is read — an addressable
//! event the node's own key signs:
//!
//! | | |
//! |---|---|
//! | kind | 30078 (NIP-78 application data, as `mostro-rates`) |
//! | author | the node |
//! | `d` | `mostro-community-card` |
//! | content | the card, JSON v1, carrying its own signature |
//!
//! That is what makes the payment methods follow the operator: a method
//! added in the panel reaches every install on its next look, with no build.
//! The convention is the panel's and this client's, not the protocol's, and
//! publishing is the operator's choice — so no card on the relays is the
//! normal case, never an error. Nor does the event say the node is alive: it
//! carries no expiry, and liveness comes from the info event alone.
//!
//! Only what the card is the source for is used from it: name, payment
//! methods, currency, website, contact. Its `fee_bps` and `bond_percent` are
//! indicative; the fee and the bond that apply are the info event's.
//!
//! Nothing here is taken on a relay's word. A relay is not held to the filter
//! it answers (`node_liveness`), so the event is checked for kind, author,
//! `d` and signature before the newest copy is picked, and the card inside
//! for the node's key and its own BIP-340 signature. A card that passes
//! replaces the stored profile; an absent, older or invalid one changes
//! nothing, so the last good card stays — and until one exists the screens
//! keep their built-in list.
//!
//! Every relay is heard out before the newest copy is picked: nobody waits
//! on this look, and a relay that still holds last month's revision is often
//! the first to answer. What that cannot cover is a fresh install answered
//! only by relays holding an old revision — it applies that one until a look
//! reads a newer. The date that orders two cards is their event's, which the
//! card's own signature does not cover; so an old card is always one the
//! node did sign, never anyone else's.

use std::sync::atomic::{AtomicI64, AtomicU32, Ordering};

use anyhow::Result;
use nostr_sdk::prelude::*;

use crate::api::community::CommunityProfile;
use crate::db::{settings_keys, Storage};

/// NIP-78 application data, the kind the node's `mostro-rates` event uses.
const KIND_COMMUNITY_CARD: u16 = 30078;

/// The `d` tag that addresses the card among the node's kind 30078 events.
pub(crate) const CARD_D_TAG: &str = "mostro-community-card";

/// How long a look waits for every relay to answer.
const LOOK_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);

/// How often a read of the stored profile may trigger another look once one
/// has found a card. The card changes when the operator edits it, a few
/// times a year; the look is one REQ.
const LOOK_EVERY_SECS: i64 = 600;

/// How soon a look that found no card — none published, or no relay that
/// has it answered in time — may be followed by another. Doubled after each
/// such look, up to [`LOOK_EVERY_SECS`]: a card that exists is read within a
/// minute of a slow start, and a node that publishes none is not asked every
/// minute for ever.
const LOOK_AGAIN_SECS: i64 = 60;

/// When the next look may start (unix seconds), so readers of the profile
/// do not each start one. `0` until the first.
static NEXT_LOOK: AtomicI64 = AtomicI64::new(0);

/// How many looks in a row found no card.
static EMPTY_LOOKS: AtomicU32 = AtomicU32::new(0);

/// How long to wait before the next look, after `empty_looks` in a row that
/// found no card (`0`: the last one found it).
fn wait_before_next_look(empty_looks: u32) -> i64 {
    match empty_looks {
        0 => LOOK_EVERY_SECS,
        n => LOOK_AGAIN_SECS
            .saturating_mul(1i64 << (n - 1).min(16))
            .min(LOOK_EVERY_SECS),
    }
}

/// Whether `event` is `node`'s community card event: its kind, its author,
/// its `d` tag, and a signature that holds.
pub(crate) fn is_card_event_of(event: &Event, node: &PublicKey) -> bool {
    event.kind == Kind::from(KIND_COMMUNITY_CARD)
        && event.pubkey == *node
        && event.tags.iter().map(|tag| tag.as_slice()).any(|tag| {
            tag.first().map(String::as_str) == Some("d")
                && tag.get(1).map(String::as_str) == Some(CARD_D_TAG)
        })
        && event.verify().is_ok()
}

/// The card `content` holds, when it is `node_hex`'s own: JSON, version 1,
/// issued for that key and signed by it.
///
/// Only JSON: the payload parser also takes an `nprofile` or an `npub`,
/// which carry no card at all and are filled in with invented values.
pub(crate) fn card_from_content(content: &str, node_hex: &str) -> Option<CommunityProfile> {
    let content = content.trim();
    if !content.starts_with('{') {
        return None;
    }
    let card = crate::api::community::parse_community_payload(content.to_string()).ok()?;
    is_card_of(&card, node_hex).then_some(card)
}

/// Whether `card` is one `node_hex` issued: version 1, that key, and the
/// card's own signature by it.
pub(crate) fn is_card_of(card: &CommunityProfile, node_hex: &str) -> bool {
    card.version == 1
        && card.pubkey.eq_ignore_ascii_case(node_hex)
        && crate::api::community::verify_community_signature(card)
}

/// Stores `card`, signed at `issued_at`, as the community's profile. Returns
/// whether anything changed.
///
/// An older card than the one stored is refused: a relay still holding last
/// month's revision must not bring back a payment method the operator
/// removed.
pub(crate) async fn store<S: Storage>(
    db: &S,
    card: &CommunityProfile,
    issued_at: i64,
) -> Result<bool> {
    let stored_at = db
        .get_setting(settings_keys::COMMUNITY_CARD_AT)
        .await?
        .and_then(|at| at.trim().parse::<i64>().ok());
    if stored_at.is_some_and(|at| issued_at < at) {
        return Ok(false);
    }
    let json = serde_json::to_string(card)?;
    let unchanged = db
        .get_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE)
        .await?
        .is_some_and(|stored| stored == json);
    if unchanged && stored_at == Some(issued_at) {
        return Ok(false);
    }
    db.set_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE, &json)
        .await?;
    db.set_setting(
        settings_keys::COMMUNITY_PAYMENT_METHODS,
        &serde_json::to_string(&card.payment_methods)?,
    )
    .await?;
    db.set_setting(settings_keys::COMMUNITY_CARD_AT, &issued_at.to_string())
        .await?;
    Ok(!unchanged)
}

/// One look at the active node's card, stored when it is newer. Best effort:
/// a look that fails, or finds no card, leaves what is stored.
pub(crate) async fn refresh() {
    // No other look while this one is out, however it ends.
    NEXT_LOOK.store(
        crate::rt::unix_now().saturating_add(LOOK_EVERY_SECS),
        Ordering::Relaxed,
    );
    let found = read_and_store().await;
    let empty_looks = if found {
        EMPTY_LOOKS.store(0, Ordering::Relaxed);
        0
    } else {
        EMPTY_LOOKS.fetch_add(1, Ordering::Relaxed).saturating_add(1)
    };
    NEXT_LOOK.store(
        crate::rt::unix_now().saturating_add(wait_before_next_look(empty_looks)),
        Ordering::Relaxed,
    );
}

/// Looks for the active node's card and stores it. `true` when a card was
/// read and the store took the look's answer — the card or "nothing new".
async fn read_and_store() -> bool {
    let node_hex = crate::config::active_mostro_pubkey();
    let found = match look(&node_hex).await {
        Ok(found) => found,
        Err(e) => {
            log::debug!("[community] card look failed: {e}");
            return false;
        }
    };
    let Some((card, issued_at)) = found else {
        log::debug!("[community] no card read from the node's relays");
        return false;
    };
    let Some(db) = crate::db::app_db::db() else {
        return false;
    };
    match store(db, &card, issued_at).await {
        Ok(true) => {
            log::info!(
                "[community] card applied: {} payment methods, {}",
                card.payment_methods.len(),
                card.currency
            );
            true
        }
        Ok(false) => true,
        Err(e) => {
            log::warn!("[community] could not store the card: {e}");
            false
        }
    }
}

/// Starts a look when the next one is due. Called by whoever reads the
/// stored profile, so a card the operator changed during a long session is
/// picked up without a timer of its own.
pub(crate) fn refresh_if_stale() {
    let now = crate::rt::unix_now();
    let due = NEXT_LOOK.load(Ordering::Relaxed);
    if now < due {
        return;
    }
    // Claimed before spawning, so two readers do not both look.
    if NEXT_LOOK
        .compare_exchange(
            due,
            now.saturating_add(LOOK_EVERY_SECS),
            Ordering::Relaxed,
            Ordering::Relaxed,
        )
        .is_err()
    {
        return;
    }
    crate::rt::spawn(refresh());
}

/// The newest card `node_hex` publishes, with the time its event was signed.
async fn look(node_hex: &str) -> Result<Option<(CommunityProfile, i64)>> {
    let client = crate::api::nostr::get_pool()?.client();
    let node =
        PublicKey::from_hex(node_hex).map_err(|e| anyhow::anyhow!("invalid pubkey hex: {e}"))?;
    let filter = Filter::new()
        .kind(Kind::from(KIND_COMMUNITY_CARD))
        .author(node)
        .custom_tag(SingleLetterTag::LOWERCASE_D, CARD_D_TAG)
        .limit(1);
    // Every relay is heard out — to EOSE, or the timeout for one that sits
    // on the REQ. Unlike the node's info event, nothing waits on this, and
    // taking the first answer would let the relay that holds an old revision
    // decide: it is as likely as any to be the fastest.
    let events = client
        .fetch_events(filter)
        .timeout(LOOK_TIMEOUT)
        .await
        .map_err(|e| anyhow::anyhow!("fetch_events failed: {e}"))?;
    Ok(newest_card(events, &node, node_hex))
}

/// The newest of `node`'s cards among `events`, with the time its event was
/// signed. Only an event that is the node's card event and holds a card the
/// node signed is in the running, so an event with a later date and nothing
/// valid inside cannot shadow the real one.
fn newest_card(
    events: impl IntoIterator<Item = Event>,
    node: &PublicKey,
    node_hex: &str,
) -> Option<(CommunityProfile, i64)> {
    events
        .into_iter()
        .filter(|event| is_card_event_of(event, node))
        .filter_map(|event| {
            let issued_at = i64::try_from(event.created_at.as_secs()).ok()?;
            let rank = crate::nostr::first_answer::replaceable_rank(&event);
            card_from_content(&event.content, node_hex).map(|card| (rank, card, issued_at))
        })
        .max_by_key(|(rank, _, _)| *rank)
        .map(|(_, card, issued_at)| (card, issued_at))
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::db::sqlite::SqliteStorage;

    const ISSUED: i64 = 1_790_000_000;

    /// A store of its own per test, removed when the test is done.
    struct TempDb(SqliteStorage, std::path::PathBuf);

    impl std::ops::Deref for TempDb {
        type Target = SqliteStorage;
        fn deref(&self) -> &SqliteStorage {
            &self.0
        }
    }

    impl Drop for TempDb {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.1);
        }
    }

    /// A card `keys` signs for itself, with `methods`.
    fn signed_card(keys: &Keys, methods: &[&str]) -> CommunityProfile {
        let mut card = CommunityProfile {
            version: 1,
            name: "BitMaxis".to_string(),
            pubkey: keys.public_key().to_hex(),
            relays: vec!["wss://relay.mostro.network".to_string()],
            currency: "USD".to_string(),
            payment_methods: methods.iter().map(|m| m.to_string()).collect(),
            fee_bps: 80,
            bond_percent: 5,
            website: Some("https://mostro.bitmaxis.com/".to_string()),
            contact: None,
            signature: String::new(),
        };
        card.signature = String::new();
        resign(keys, card)
    }

    /// `card` signed by `keys` as it stands: BIP-340 over the digest, as
    /// the panel signs it.
    fn resign(keys: &Keys, mut card: CommunityProfile) -> CommunityProfile {
        let digest = crate::api::community::canonical_digest(&card);
        let signer =
            k256::schnorr::SigningKey::from_bytes(&keys.secret_key().to_secret_bytes())
                .expect("a valid secret key");
        let signature: k256::schnorr::Signature =
            signer.sign_raw(&digest, &[0u8; 32]).expect("sign");
        card.signature = hex::encode(signature.to_bytes());
        card
    }

    fn card_event(signer: &Keys, d: &str, content: &str, at: u64) -> Event {
        EventBuilder::new(Kind::from(KIND_COMMUNITY_CARD), content)
            .tag(Tag::parse(["d", d]).unwrap())
            .custom_created_at(Timestamp::from(at))
            .finalize(signer)
            .unwrap()
    }

    async fn memory_db() -> TempDb {
        static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let path = std::env::temp_dir().join(format!(
            "mostro_card_{}_{}.db",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        TempDb(storage, path)
    }

    #[test]
    fn a_card_the_node_signed_is_read() {
        let node = Keys::generate();
        let card = signed_card(&node, &["Transferencia", "Banco Pichincha"]);
        let json = serde_json::to_string(&card).unwrap();

        let read = card_from_content(&json, &node.public_key().to_hex()).expect("the card");

        assert_eq!(read.payment_methods, ["Transferencia", "Banco Pichincha"]);
        assert_eq!(read.currency, "USD");
    }

    #[test]
    fn a_card_is_refused_unless_it_is_the_nodes_own() {
        let node = Keys::generate();
        let node_hex = node.public_key().to_hex();
        let card = signed_card(&node, &["Transferencia"]);

        // Tampered after signing: the list is part of what was signed.
        let mut tampered = card.clone();
        tampered.payment_methods.push("Western Union".to_string());
        let json = serde_json::to_string(&tampered).unwrap();
        assert!(card_from_content(&json, &node_hex).is_none());

        // Signed, but by and for another key.
        let stranger = Keys::generate();
        let foreign = serde_json::to_string(&signed_card(&stranger, &["Zelle"])).unwrap();
        assert!(card_from_content(&foreign, &node_hex).is_none());

        // The node's key on a card it never signed.
        let mut forged = signed_card(&stranger, &["Zelle"]);
        forged.pubkey = node_hex.clone();
        let json = serde_json::to_string(&forged).unwrap();
        assert!(card_from_content(&json, &node_hex).is_none());

        // No signature at all, and a version this client does not read.
        let mut unsigned = card.clone();
        unsigned.signature = String::new();
        let json = serde_json::to_string(&unsigned).unwrap();
        assert!(card_from_content(&json, &node_hex).is_none());
        let mut later = card.clone();
        later.version = 2;
        let json = serde_json::to_string(&later).unwrap();
        assert!(card_from_content(&json, &node_hex).is_none());
    }

    /// A relay written `WSS://…` is a relay, and is part of what was signed:
    /// dropped while parsing, the card no longer matched its own signature.
    #[test]
    fn a_relay_scheme_in_capitals_does_not_cost_the_card_its_signature() {
        let node = Keys::generate();
        let mut card = signed_card(&node, &["Transferencia"]);
        card.relays = vec![
            "WSS://Relay.Mostro.Network".to_string(),
            "wss://mostro-p2p.tech".to_string(),
        ];
        let card = resign(&node, card);
        let json = serde_json::to_string(&card).unwrap();

        let read = card_from_content(&json, &node.public_key().to_hex()).expect("the card");

        assert_eq!(read.relays.len(), 2);
        // What is not a relay at all is still dropped — and a card signed
        // over it then fails its check, which the panel never signs.
        let mut odd = card.clone();
        odd.relays.push("https://not-a-relay.example".to_string());
        let odd = resign(&node, odd);
        let json = serde_json::to_string(&odd).unwrap();
        assert!(card_from_content(&json, &node.public_key().to_hex()).is_none());
    }

    #[test]
    fn only_json_is_a_card() {
        let node = Keys::generate();
        let node_hex = node.public_key().to_hex();
        // The payload parser reads these too, and invents a currency, a fee
        // and a bond for them.
        let npub = node.public_key().to_bech32().unwrap();
        assert!(card_from_content(&npub, &node_hex).is_none());
        assert!(card_from_content("", &node_hex).is_none());
        assert!(card_from_content("not a card", &node_hex).is_none());
        assert!(card_from_content("{\"version\":1}", &node_hex).is_none());
    }

    #[test]
    fn the_event_is_checked_for_kind_author_address_and_signature() {
        let node = Keys::generate();
        let stranger = Keys::generate();
        let content = serde_json::to_string(&signed_card(&node, &["Transferencia"])).unwrap();

        let genuine = card_event(&node, CARD_D_TAG, &content, ISSUED as u64);
        assert!(is_card_event_of(&genuine, &node.public_key()));

        // The node's card, republished by someone else: the card's own
        // signature holds, the event is not the node's.
        let relayed = card_event(&stranger, CARD_D_TAG, &content, ISSUED as u64);
        assert!(!is_card_event_of(&relayed, &node.public_key()));

        // The node's other kind 30078 event.
        let rates = card_event(&node, "mostro-rates", &content, ISSUED as u64);
        assert!(!is_card_event_of(&rates, &node.public_key()));

        let other_kind = EventBuilder::new(Kind::from(38385u16), content.clone())
            .tag(Tag::parse(["d", CARD_D_TAG]).unwrap())
            .finalize(&node)
            .unwrap();
        assert!(!is_card_event_of(&other_kind, &node.public_key()));

        // Content swapped under a signature that covered the original.
        let mut json = serde_json::to_value(&genuine).unwrap();
        json["content"] = serde_json::Value::String("{}".to_string());
        let rewritten: Event = serde_json::from_value(json).unwrap();
        assert!(!is_card_event_of(&rewritten, &node.public_key()));
    }

    #[tokio::test]
    async fn a_card_is_stored_with_its_payment_methods() {
        let db = memory_db().await;
        let node = Keys::generate();
        let card = signed_card(&node, &["Transferencia", "Banco Pichincha"]);

        assert!(store(&*db, &card, ISSUED).await.unwrap());

        let profile: CommunityProfile = serde_json::from_str(
            &db.get_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE)
                .await
                .unwrap()
                .unwrap(),
        )
        .unwrap();
        assert_eq!(profile, card);
        // Stored as signed, so a later read can verify it again.
        assert!(is_card_of(&profile, &node.public_key().to_hex()));
        assert_eq!(
            db.get_setting(settings_keys::COMMUNITY_PAYMENT_METHODS)
                .await
                .unwrap()
                .as_deref(),
            Some("[\"Transferencia\",\"Banco Pichincha\"]")
        );
    }

    #[tokio::test]
    async fn a_newer_card_replaces_the_stored_one_and_an_older_one_does_not() {
        let db = memory_db().await;
        let node = Keys::generate();
        let first = signed_card(&node, &["Transferencia"]);
        let second = signed_card(&node, &["Transferencia", "DeUna"]);
        assert!(store(&*db, &first, ISSUED).await.unwrap());

        // The operator added a method.
        assert!(store(&*db, &second, ISSUED + 60).await.unwrap());
        // A relay still holding the first revision answers the next look.
        assert!(!store(&*db, &first, ISSUED).await.unwrap());

        let methods = db
            .get_setting(settings_keys::COMMUNITY_PAYMENT_METHODS)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(methods, "[\"Transferencia\",\"DeUna\"]");
    }

    #[tokio::test]
    async fn the_same_card_again_changes_nothing() {
        let db = memory_db().await;
        let node = Keys::generate();
        let card = signed_card(&node, &["Transferencia"]);
        assert!(store(&*db, &card, ISSUED).await.unwrap());

        assert!(!store(&*db, &card, ISSUED).await.unwrap());
        // Republished unchanged, as the panel does on a schedule: the date
        // moves on, the profile does not.
        assert!(!store(&*db, &card, ISSUED + 3600).await.unwrap());
        assert_eq!(
            db.get_setting(settings_keys::COMMUNITY_CARD_AT)
                .await
                .unwrap()
                .as_deref(),
            Some((ISSUED + 3600).to_string().as_str())
        );
    }

    #[test]
    fn the_newest_valid_card_wins_whichever_relay_answers_first() {
        let node = Keys::generate();
        let node_hex = node.public_key().to_hex();
        let old = serde_json::to_string(&signed_card(&node, &["Transferencia"])).unwrap();
        let new =
            serde_json::to_string(&signed_card(&node, &["Transferencia", "DeUna"])).unwrap();
        let old_event = card_event(&node, CARD_D_TAG, &old, ISSUED as u64);
        let new_event = card_event(&node, CARD_D_TAG, &new, (ISSUED + 60) as u64);

        // The relay with last month's revision answers first, and second.
        for order in [
            vec![old_event.clone(), new_event.clone()],
            vec![new_event.clone(), old_event.clone()],
        ] {
            let (card, issued_at) =
                newest_card(order, &node.public_key(), &node_hex).expect("a card");
            assert_eq!(card.payment_methods, ["Transferencia", "DeUna"]);
            assert_eq!(issued_at, ISSUED + 60);
        }
    }

    #[test]
    fn a_later_event_with_no_valid_card_shadows_nothing() {
        let node = Keys::generate();
        let node_hex = node.public_key().to_hex();
        let stranger = Keys::generate();
        let card = serde_json::to_string(&signed_card(&node, &["Transferencia"])).unwrap();
        let genuine = card_event(&node, CARD_D_TAG, &card, ISSUED as u64);
        // Later, and each wrong in its own way: someone else's event, the
        // node's event around another node's card, and the node's event
        // around a card tampered after signing.
        let foreign_card =
            serde_json::to_string(&signed_card(&stranger, &["Western Union"])).unwrap();
        let mut tampered = signed_card(&node, &["Transferencia"]);
        tampered.payment_methods.push("Western Union".to_string());
        let later = [
            card_event(&stranger, CARD_D_TAG, &foreign_card, (ISSUED + 300) as u64),
            card_event(&node, CARD_D_TAG, &foreign_card, (ISSUED + 300) as u64),
            card_event(
                &node,
                CARD_D_TAG,
                &serde_json::to_string(&tampered).unwrap(),
                (ISSUED + 300) as u64,
            ),
        ];

        let mut events = later.to_vec();
        events.push(genuine);
        let (card, issued_at) =
            newest_card(events, &node.public_key(), &node_hex).expect("the genuine card");
        assert_eq!(card.payment_methods, ["Transferencia"]);
        assert_eq!(issued_at, ISSUED);
        assert!(newest_card(later, &node.public_key(), &node_hex).is_none());
    }

    /// A look that found no card is followed by another soon, then less and
    /// less often; one that found it waits the full interval.
    #[test]
    fn a_look_that_found_nothing_is_repeated_sooner_at_first() {
        assert_eq!(wait_before_next_look(0), LOOK_EVERY_SECS);
        assert_eq!(wait_before_next_look(1), 60);
        assert_eq!(wait_before_next_look(2), 120);
        assert_eq!(wait_before_next_look(3), 240);
        assert_eq!(wait_before_next_look(4), 480);
        assert_eq!(wait_before_next_look(5), LOOK_EVERY_SECS);
        assert_eq!(wait_before_next_look(u32::MAX), LOOK_EVERY_SECS);
    }

    /// The card is requested behind the order book, never in front of it:
    /// nothing relay-bound may delay `subscribe_orders()` when the pool comes
    /// online. The wiring needs a relay pool, so it is pinned on the source.
    #[test]
    fn the_look_is_spawned_after_the_book_subscribes() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("src")
            .join("api")
            .join("nostr.rs");
        let source = std::fs::read_to_string(path).expect("read api/nostr.rs");
        let start = source
            .find("async fn on_pool_online() {")
            .expect("on_pool_online exists");
        let body = &source[start..];
        let body = &body[..body.find("\n}\n").expect("on_pool_online ends")];
        let book = body
            .find("crate::api::orders::subscribe_orders().await;")
            .expect("the book subscribes");
        let card = body
            .find("crate::rt::spawn(crate::mostro::community_card::refresh());")
            .expect("the card look is spawned, not awaited");
        assert!(book < card);
    }
}
