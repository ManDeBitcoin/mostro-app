//! The seller's payment details: kept per payment method on this device,
//! and handed to the buyer over the trade's chat once the escrow is locked.
//!
//! The rules — what is kept, and when it may leave — are
//! `mostro::payment_details`; this is their bridge surface.

use anyhow::{anyhow, bail, Result};

use crate::api::types::ChatMessage;
use crate::db::Storage;
use crate::mostro::payment_details as rules;

/// One payment method and what its seller is paid with.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PaymentDetails {
    /// The method's name, as an order or the community's card writes it.
    pub method: String,
    /// Account, holder, phone — free text. Empty when nothing is kept.
    pub details: String,
}

/// Every payment method this device keeps details for, in the order each was
/// first saved. Empty when it keeps none.
///
/// Errors: `StorageUnavailable` before `init_db`.
pub async fn saved_payment_details() -> Result<Vec<PaymentDetails>> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    rules::all_in(db).await
}

/// What is kept for each of `methods` — an order's, or the ones ticked on the
/// Sell tab — in their order and their spelling. `details` is empty where
/// nothing is kept, and an empty name is skipped. A method is found whatever
/// its case or outer spaces.
///
/// Errors: `StorageUnavailable` before `init_db`.
pub async fn payment_details_for(methods: Vec<String>) -> Result<Vec<PaymentDetails>> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    rules::for_methods_in(db, &methods).await
}

/// Keep `details` for `method` on this device, in place of what was kept for
/// it. Empty `details` forget the method.
///
/// Kept with the identity: generating or importing another one erases them.
///
/// Errors are markers: `StorageUnavailable`, `InvalidPaymentMethod` (no name,
/// or one past 100 characters), `PaymentDetailsTooLong` (past 1000).
pub async fn save_payment_details(method: String, details: String) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    rules::save_in(db, &method, &details).await
}

/// Send the seller's payment details to the buyer of `order_id`, over the
/// trade's end-to-end encrypted chat.
///
/// `content` is the message as the buyer will read it. Dart composes it —
/// it is prose — from the methods the seller left ticked.
///
/// Refused, with nothing sent, unless this user is the seller and the
/// escrow is locked (`active`, `fiat-sent` or `dispute` on the trade row).
/// Returns the message, now in the conversation, only once a relay accepted
/// it; from then on [`payment_details_sent_at`] answers for the order.
///
/// Errors are markers: `StorageUnavailable`, `MessageEmpty`,
/// `PaymentDetailsNoTrade`, `PaymentDetailsNotSeller`,
/// `PaymentDetailsEscrowNotLocked`, then those of the send —
/// `PaymentDetailsPeerUnknown` (the buyer's key is not here yet),
/// `NoRelayAccepted`, `MessageTooLarge`, `SendFailed`.
pub async fn send_payment_details(order_id: String, content: String) -> Result<ChatMessage> {
    if content.trim().is_empty() {
        bail!("MessageEmpty: content must not be empty");
    }
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    let trade = db.get_trade_by_order_id(&order_id).await?;
    rules::may_send(trade.as_ref()).map_err(|marker| anyhow!(marker))?;

    let sent = crate::api::messages::send_delivered(&order_id, &content)
        .await
        .map_err(rules::send_error)?;
    rules::mark_sent_in(db, &order_id, sent.created_at).await;
    crate::api::logging::blog_info(
        "payment_details",
        format!(
            "payment details sent to the buyer of order={}",
            crate::api::logging::short_id(&order_id),
        ),
    );
    Ok(sent)
}

/// When the payment details of `order_id` were sent from this device (unix
/// seconds), or `None` if they never were.
///
/// Errors: `StorageUnavailable` before `init_db`.
pub async fn payment_details_sent_at(order_id: String) -> Result<Option<i64>> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    Ok(rules::sent_at_in(db, &order_id).await)
}

#[cfg(test)]
mod tests {
    /// The body of `fn name` in this file, up to its closing brace.
    fn fn_body(name: &str) -> &'static str {
        let source = include_str!("payment_details.rs");
        let start = source.find(name).expect("the function exists");
        let end = start + source[start..].find("\n}\n").expect("the function ends");
        &source[start..end]
    }

    /// The rule is only worth its tests if nothing leaves before it is
    /// asked, and "sent" is only recorded for a message that left.
    #[test]
    fn the_details_leave_only_past_the_gate_and_are_marked_only_once_sent() {
        let send = fn_body("pub async fn send_payment_details(");
        let gate = send.find("rules::may_send(").expect("asks the rule");
        let sent = send
            .find("messages::send_delivered(")
            .expect("sends through the send that must arrive");
        let marked = send.find("rules::mark_sent_in(").expect("records the send");
        assert!(gate < sent, "the rule is asked before anything is sent");
        assert!(sent < marked, "the mark follows a send that returned");
        assert!(
            !send.contains("messages::send_message("),
            "the chat's own send keeps a message no relay took"
        );
    }

    /// An account number in a log outlives the identity it belonged to. The
    /// log lines of both modules put an error or a shortened order id into
    /// their text, and nothing else.
    #[test]
    fn the_logs_carry_an_error_or_an_order_id_and_nothing_else() {
        for source in [
            include_str!("payment_details.rs"),
            include_str!("../mostro/payment_details.rs"),
        ] {
            let production = source.split("\n#[cfg(").next().unwrap();
            let mut rest = production;
            let mut calls = 0;
            while let Some(at) = rest.find("blog_") {
                let end = rest[at..].find(");\n").expect("the log call ends");
                let call = &rest[at..at + end];
                let named: Vec<&str> = call
                    .split('{')
                    .skip(1)
                    .filter_map(|after| after.split('}').next())
                    .filter(|name| !name.is_empty())
                    .collect();
                assert!(named.iter().all(|name| *name == "e"), "{call}");
                assert_eq!(
                    call.matches("{}").count(),
                    call.matches("short_id(").count(),
                    "{call}"
                );
                calls += 1;
                rest = &rest[at + end..];
            }
            assert!(calls > 0, "the module logs, so there is something to check");
        }
    }
}
