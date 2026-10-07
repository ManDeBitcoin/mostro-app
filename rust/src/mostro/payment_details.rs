//! How a seller is paid, kept on this device, and when it may leave it.
//!
//! A sell order names the ways its seller takes the money (`pm`) and nothing
//! else about them: the order is public. The account behind each method is
//! what the buyer needs at exactly one moment — when the seller's sats are
//! locked and it is the buyer's turn to pay — and the only private channel
//! between the two exists from that same moment: mostrod names each party's
//! trade key to the other in `buyer-took-order` and
//! `hold-invoice-payment-accepted`, the two messages that announce `active`
//! (v0.19.2, `flow.rs::hold_invoice_paid`), and the chat keys are derived
//! from both keys.
//!
//! Simple Mode used to ask the seller for those details on the way to
//! publishing, show them back on the confirmation sheet and drop them: the
//! buyer's "send the money" card never had an account to send it to.
//!
//! Kept here, in the settings store and with the identity
//! (`settings_keys::IDENTITY_SCOPED_PREFIXES`):
//!
//! - the details, one text per payment method, so that a seller writes each
//!   account once and, whichever of an order's methods the buyer pays by, its
//!   details are at hand — also for a seller who took a buy order and never
//!   passed through a form;
//! - per order, when they were sent, so that "sent" on a screen is a relay's
//!   acceptance and not a guess.
//!
//! And one rule is decided here rather than by whichever screen holds the
//! button — [`may_send`]: only the seller, only while the escrow is locked.
//! In Lightning mode the chat cannot exist earlier anyway; in Cashu mode the
//! seller learns the buyer's key at `waiting-payment`, before locking
//! (`show_cashu_escrow_request`), so "a chat exists" is not the test.
//!
//! The message itself is composed in Dart: it is prose, and Rust does not
//! translate. Nothing in this module logs a method's details.

use anyhow::{anyhow, bail, Result};

use crate::api::payment_details::PaymentDetails;
use crate::api::types::{TradeInfo, TradeRole};
use crate::db::{settings_keys, Storage};

/// Longest text kept for one method, in characters. An account number, a
/// holder and a note fit many times over; the bound keeps one settings row
/// from growing without limit.
pub(crate) const MAX_DETAILS_CHARS: usize = 1000;

/// Longest payment method name kept, in characters. The community's card
/// writes them in a few words.
pub(crate) const MAX_METHOD_CHARS: usize = 100;

/// No trade row for the order: nothing here says who would read the details.
pub(crate) const NO_TRADE: &str = "PaymentDetailsNoTrade";

/// The details are the seller's to give; the buyer has none to send.
pub(crate) const NOT_SELLER: &str = "PaymentDetailsNotSeller";

/// The seller's sats are not locked, or no longer: nobody is about to pay.
pub(crate) const ESCROW_NOT_LOCKED: &str = "PaymentDetailsEscrowNotLocked";

/// The buyer's key has not reached this device yet, so there is no chat to
/// send over. It arrives with the message that announces the lock; a trade
/// rebuilt by a restore can be a replay behind.
pub(crate) const PEER_UNKNOWN: &str = "PaymentDetailsPeerUnknown";

/// Serializes the read-modify-write of the one saved document: two methods
/// saved at once would otherwise each write back the list without the other.
static WRITES: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// How a payment method is told from another: without regard to case or
/// outer spaces, as Simple Mode tells them apart (`paymentMethodKey`). A card
/// that comes back writing `banco x` still finds what was kept for `Banco X`.
fn method_key(method: &str) -> String {
    method.trim().to_lowercase()
}

/// Whether the seller's payment details may go to the counterparty of
/// `trade` now. `Err` carries the marker to refuse with.
///
/// Read off the trade row, which only the node's private messages move: the
/// public book's `in-progress` says "taken", never "locked" (#203).
pub(crate) fn may_send(trade: Option<&TradeInfo>) -> std::result::Result<(), &'static str> {
    let Some(trade) = trade else {
        return Err(NO_TRADE);
    };
    if trade.role != TradeRole::Seller {
        return Err(NOT_SELLER);
    }
    if trade.outcome.is_some()
        || !crate::mostro::funds_at_risk::escrow_is_locked(&trade.order.status)
    {
        return Err(ESCROW_NOT_LOCKED);
    }
    Ok(())
}

/// A failed send, by the marker this feature's screen has words for.
///
/// The chat says "nobody to send to yet" in two ways (`SessionNotFound`,
/// `PeerUnknown`) that it also uses for attachments, in either direction of
/// a trade; here they mean one thing, the buyer's key is not here yet, and
/// the wording says "buyer". Every other failure passes as it came.
pub(crate) fn send_error(err: anyhow::Error) -> anyhow::Error {
    let raw = err.to_string();
    if raw.starts_with("SessionNotFound") || raw.starts_with("PeerUnknown") {
        anyhow!("{PEER_UNKNOWN}: {raw}")
    } else {
        err
    }
}

/// Everything kept, in the order each method was first saved.
pub(crate) async fn all_in(db: &impl Storage) -> Result<Vec<PaymentDetails>> {
    let Some(json) = db
        .get_setting(settings_keys::PAYMENT_DETAILS_SAVED)
        .await?
    else {
        return Ok(Vec::new());
    };
    match serde_json::from_str(&json) {
        Ok(saved) => Ok(saved),
        // Unreadable is "nothing kept": the next save writes a sound
        // document over it. The error names a position, never the text.
        Err(e) => {
            crate::api::logging::blog_warn(
                "payment_details",
                format!("saved payment details are unreadable, treated as none: {e}"),
            );
            Ok(Vec::new())
        }
    }
}

/// What is kept for each of `methods`, in their order and their spelling;
/// `details` is empty where nothing is kept. An empty name is skipped.
pub(crate) async fn for_methods_in(
    db: &impl Storage,
    methods: &[String],
) -> Result<Vec<PaymentDetails>> {
    let saved = all_in(db).await?;
    Ok(methods
        .iter()
        .map(|method| method.trim())
        .filter(|method| !method.is_empty())
        .map(|method| {
            let key = method_key(method);
            PaymentDetails {
                method: method.to_string(),
                details: saved
                    .iter()
                    .find(|kept| method_key(&kept.method) == key)
                    .map(|kept| kept.details.clone())
                    .unwrap_or_default(),
            }
        })
        .collect())
}

/// Keep `details` for `method`, in place of what was kept for it. Empty
/// `details` forget the method.
///
/// Refused by marker, with nothing written: `InvalidPaymentMethod` for a name
/// that is empty or longer than [`MAX_METHOD_CHARS`], `PaymentDetailsTooLong`
/// past [`MAX_DETAILS_CHARS`].
pub(crate) async fn save_in(db: &impl Storage, method: &str, details: &str) -> Result<()> {
    let method = method.trim();
    let details = details.trim();
    if method.is_empty() || method.chars().count() > MAX_METHOD_CHARS {
        bail!("InvalidPaymentMethod: a payment method needs a name of at most {MAX_METHOD_CHARS} characters");
    }
    if details.chars().count() > MAX_DETAILS_CHARS {
        bail!("PaymentDetailsTooLong: at most {MAX_DETAILS_CHARS} characters per payment method");
    }

    let _writing = WRITES.lock().await;
    let mut saved = all_in(db).await?;
    let key = method_key(method);
    let kept_at = saved.iter().position(|kept| method_key(&kept.method) == key);
    match (kept_at, details.is_empty()) {
        (None, true) => return Ok(()),
        (Some(at), true) => {
            saved.remove(at);
        }
        // The spelling follows the last save, like the text.
        (Some(at), false) => {
            saved[at] = PaymentDetails {
                method: method.to_string(),
                details: details.to_string(),
            };
        }
        (None, false) => saved.push(PaymentDetails {
            method: method.to_string(),
            details: details.to_string(),
        }),
    }
    if saved.is_empty() {
        db.delete_setting(settings_keys::PAYMENT_DETAILS_SAVED).await
    } else {
        db.set_setting(
            settings_keys::PAYMENT_DETAILS_SAVED,
            &serde_json::to_string(&saved)?,
        )
        .await
    }
}

/// When `order_id`'s payment details were sent (unix seconds), or `None` if
/// they never were. A read error is "not sent", logged: the seller is
/// offered the button again, which costs the buyer a repeated message at
/// worst.
pub(crate) async fn sent_at_in(db: &impl Storage, order_id: &str) -> Option<i64> {
    match db
        .get_setting(&settings_keys::payment_details_sent(order_id))
        .await
    {
        Ok(at) => at.and_then(|at| at.trim().parse().ok()),
        Err(e) => {
            crate::api::logging::blog_warn(
                "payment_details",
                format!(
                    "could not read when the payment details of order={} were sent: {e}",
                    crate::api::logging::short_id(order_id),
                ),
            );
            None
        }
    }
}

/// Record that `order_id`'s payment details were sent at `at` (unix
/// seconds). Best effort: the message is out either way.
pub(crate) async fn mark_sent_in(db: &impl Storage, order_id: &str, at: i64) {
    if let Err(e) = db
        .set_setting(
            &settings_keys::payment_details_sent(order_id),
            &at.to_string(),
        )
        .await
    {
        crate::api::logging::blog_warn(
            "payment_details",
            format!(
                "could not record that the payment details of order={} were sent: {e}",
                crate::api::logging::short_id(order_id),
            ),
        );
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::api::types::{
        OrderInfo, OrderKind, OrderStatus, SellerStep, TradeOutcome, TradeStep,
    };
    use crate::db::sqlite::SqliteStorage;

    /// A store of its own per test: the process-wide one is shared by every
    /// test running in parallel.
    async fn temp_storage(tag: &str) -> (SqliteStorage, std::path::PathBuf) {
        let path = std::env::temp_dir().join(format!(
            "mostro_payment_details_{}_{tag}.db",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        (storage, path)
    }

    fn methods(names: &[&str]) -> Vec<String> {
        names.iter().map(|name| name.to_string()).collect()
    }

    fn kept(method: &str, details: &str) -> PaymentDetails {
        PaymentDetails {
            method: method.to_string(),
            details: details.to_string(),
        }
    }

    fn trade(role: TradeRole, status: OrderStatus) -> TradeInfo {
        TradeInfo {
            id: "o".into(),
            order: OrderInfo {
                id: "o".into(),
                kind: OrderKind::Sell,
                status,
                amount_sats: None,
                fiat_amount: Some(100.0),
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "USD".into(),
                payment_method: "Banco Pichincha,De Una".into(),
                premium: 0.0,
                creator_pubkey: "maker".into(),
                created_at: 1,
                expires_at: None,
                is_mine: true,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role,
            counterparty_pubkey: "peer".into(),
            current_step: TradeStep::Seller(SellerStep::AwaitingFiat),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
            bond: None,
            buyer_trade_pubkey: None,
            seller_trade_pubkey: None,
            cashu_mint_url: None,
            cashu_escrow_token: None,
            cashu_locked_at: None,
            cashu_rejected_escrow_tokens: Vec::new(),
        }
    }

    /// The whole point: the details leave only for a buyer who is about to
    /// pay, from the side that is paid.
    #[test]
    fn only_the_seller_of_a_locked_trade_may_send() {
        use OrderStatus::*;

        for locked in [Active, FiatSent, Dispute] {
            assert_eq!(
                may_send(Some(&trade(TradeRole::Seller, locked.clone()))),
                Ok(()),
                "{locked:?}"
            );
            assert_eq!(
                may_send(Some(&trade(TradeRole::Buyer, locked.clone()))),
                Err(NOT_SELLER),
                "{locked:?}"
            );
        }

        // Before the lock — the order published, taken, waiting on either
        // side, or only known as "taken" from the public book — and after
        // the trade is over.
        for not_locked in [
            Pending,
            WaitingMakerBond,
            WaitingTakerBond,
            WaitingBuyerInvoice,
            WaitingPayment,
            InProgress,
            SettledHoldInvoice,
            Success,
            Canceled,
            Expired,
            CooperativelyCanceled,
            CanceledByAdmin,
            SettledByAdmin,
            CompletedByAdmin,
        ] {
            assert_eq!(
                may_send(Some(&trade(TradeRole::Seller, not_locked.clone()))),
                Err(ESCROW_NOT_LOCKED),
                "{not_locked:?}"
            );
        }

        assert_eq!(may_send(None), Err(NO_TRADE));
    }

    #[test]
    fn a_send_with_nobody_to_send_to_is_said_in_this_features_words() {
        for chat_marker in [
            "SessionNotFound: 6f2c",
            "PeerUnknown: the counterpart's key has not arrived yet",
        ] {
            let err = send_error(anyhow!(chat_marker));
            assert!(
                err.to_string().starts_with(PEER_UNKNOWN),
                "{chat_marker} → {err}"
            );
        }
        // What the screen already has words for, or words as a plain
        // failure, is left alone.
        for other in ["NoRelayAccepted", "SendFailed: relay pool not ready"] {
            assert_eq!(send_error(anyhow!(other)).to_string(), other);
        }
    }

    /// A row that already has an outcome is over, whatever its status still
    /// reads.
    #[test]
    fn a_finished_trade_is_not_sent_to() {
        let mut over = trade(TradeRole::Seller, OrderStatus::Active);
        over.outcome = Some(TradeOutcome::Canceled);
        assert_eq!(may_send(Some(&over)), Err(ESCROW_NOT_LOCKED));
    }

    #[tokio::test]
    async fn details_are_kept_per_method_and_found_whatever_the_spelling() {
        let (db, path) = temp_storage("per_method").await;

        assert!(all_in(&db).await.unwrap().is_empty());
        save_in(&db, "Banco Pichincha", "Ahorros 2201234567 · Ana P.")
            .await
            .unwrap();
        save_in(&db, "De Una", "099 123 4567").await.unwrap();

        // In the order and the spelling asked for; nothing kept is empty.
        assert_eq!(
            for_methods_in(&db, &methods(&[" de una ", "Efectivo", "BANCO PICHINCHA", "  "]))
                .await
                .unwrap(),
            vec![
                kept("de una", "099 123 4567"),
                kept("Efectivo", ""),
                kept("BANCO PICHINCHA", "Ahorros 2201234567 · Ana P."),
            ]
        );

        // It survives the restart it is kept for.
        drop(db);
        let db = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        assert_eq!(
            all_in(&db).await.unwrap(),
            vec![
                kept("Banco Pichincha", "Ahorros 2201234567 · Ana P."),
                kept("De Una", "099 123 4567"),
            ]
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn a_save_replaces_and_an_empty_one_forgets() {
        let (db, path) = temp_storage("replace").await;

        save_in(&db, "De Una", "099 123 4567").await.unwrap();
        save_in(&db, "Efectivo", "En persona, Quito norte")
            .await
            .unwrap();
        // The same method under another spelling is the same entry, in the
        // place it had.
        save_in(&db, " de una ", "  098 765 4321  ").await.unwrap();
        assert_eq!(
            all_in(&db).await.unwrap(),
            vec![
                kept("de una", "098 765 4321"),
                kept("Efectivo", "En persona, Quito norte"),
            ]
        );

        save_in(&db, "DE UNA", "   ").await.unwrap();
        assert_eq!(
            all_in(&db).await.unwrap(),
            vec![kept("Efectivo", "En persona, Quito norte")]
        );
        // Forgetting what was never kept is not an error.
        save_in(&db, "Zelle", "").await.unwrap();

        // The last one gone leaves no row behind, not an empty list.
        save_in(&db, "Efectivo", "").await.unwrap();
        assert_eq!(
            db.get_setting(settings_keys::PAYMENT_DETAILS_SAVED)
                .await
                .unwrap(),
            None
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn what_cannot_be_kept_is_refused_and_changes_nothing() {
        let (db, path) = temp_storage("refused").await;
        save_in(&db, "De Una", "099 123 4567").await.unwrap();

        let too_long = "9".repeat(MAX_DETAILS_CHARS + 1);
        let err = save_in(&db, "De Una", &too_long).await.unwrap_err();
        assert!(
            err.to_string().starts_with("PaymentDetailsTooLong"),
            "got: {err}"
        );
        // Counted in characters: an accented text of the full length fits.
        save_in(&db, "Efectivo", &"ñ".repeat(MAX_DETAILS_CHARS))
            .await
            .unwrap();

        for no_name in ["", "   ", &"m".repeat(MAX_METHOD_CHARS + 1)] {
            let err = save_in(&db, no_name, "x").await.unwrap_err();
            assert!(
                err.to_string().starts_with("InvalidPaymentMethod"),
                "got: {err}"
            );
        }

        assert_eq!(
            for_methods_in(&db, &methods(&["De Una"])).await.unwrap(),
            vec![kept("De Una", "099 123 4567")]
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    /// Saves made at once each keep their own method: none writes back a
    /// list read before the other landed.
    #[tokio::test]
    async fn saves_made_at_once_all_land() {
        let (db, path) = temp_storage("at_once").await;

        let names: Vec<String> = (0..12).map(|n| format!("Banco {n}")).collect();
        let saves = names
            .iter()
            .map(|name| save_in(&db, name, "cuenta"))
            .collect::<Vec<_>>();
        for saved in futures_util::future::join_all(saves).await {
            saved.unwrap();
        }

        let mut found: Vec<String> = all_in(&db)
            .await
            .unwrap()
            .into_iter()
            .map(|kept| kept.method)
            .collect();
        found.sort();
        let mut expected = names.clone();
        expected.sort();
        assert_eq!(found, expected);
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    /// A document this build cannot read is "nothing kept", and the next
    /// save puts a sound one in its place.
    #[tokio::test]
    async fn an_unreadable_document_is_treated_as_none() {
        let (db, path) = temp_storage("unreadable").await;
        db.set_setting(settings_keys::PAYMENT_DETAILS_SAVED, "{not json")
            .await
            .unwrap();

        assert!(all_in(&db).await.unwrap().is_empty());
        save_in(&db, "De Una", "099 123 4567").await.unwrap();
        assert_eq!(
            all_in(&db).await.unwrap(),
            vec![kept("De Una", "099 123 4567")]
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn the_sent_mark_is_per_order() {
        let (db, path) = temp_storage("sent").await;

        assert_eq!(sent_at_in(&db, "order-a").await, None);
        mark_sent_in(&db, "order-a", 1_760_000_000).await;
        assert_eq!(sent_at_in(&db, "order-a").await, Some(1_760_000_000));
        assert_eq!(sent_at_in(&db, "order-b").await, None);

        // Sent again: the mark follows the last message.
        mark_sent_in(&db, "order-a", 1_760_000_600).await;
        assert_eq!(sent_at_in(&db, "order-a").await, Some(1_760_000_600));
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    /// Issue #533: the next user of the device finds neither the previous
    /// one's accounts nor a trace of whom they were sent to — and still finds
    /// what belongs to the device.
    #[tokio::test]
    async fn both_are_wiped_with_the_identity() {
        let (db, path) = temp_storage("identity").await;

        save_in(&db, "Banco Pichincha", "Ahorros 2201234567 · Ana P.")
            .await
            .unwrap();
        mark_sent_in(&db, "order-a", 1_760_000_000).await;
        db.set_setting(settings_keys::PUSH_ENABLED, "1").await.unwrap();
        for prefix in [
            settings_keys::PAYMENT_DETAILS_PREFIX,
            settings_keys::PAYMENT_DETAILS_SENT_PREFIX,
        ] {
            assert!(settings_keys::IDENTITY_SCOPED_PREFIXES.contains(&prefix));
        }
        assert!(settings_keys::PAYMENT_DETAILS_SAVED
            .starts_with(settings_keys::PAYMENT_DETAILS_PREFIX));

        db.clear_identity_data().await.unwrap();

        assert!(all_in(&db).await.unwrap().is_empty());
        assert_eq!(
            db.get_setting(settings_keys::PAYMENT_DETAILS_SAVED)
                .await
                .unwrap(),
            None
        );
        assert_eq!(sent_at_in(&db, "order-a").await, None);
        assert_eq!(
            db.get_setting(settings_keys::PUSH_ENABLED)
                .await
                .unwrap()
                .as_deref(),
            Some("1"),
            "a device preference is not the identity's"
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }
}
