//! The node's id for a dispute, kept per order.
//!
//! A dispute has an id of its own, minted by the node. It is what the solver
//! and the node's Kind 38386 event refer to, and it reaches each party in
//! exactly one message: `dispute-initiated-by-you` for whoever opened the
//! dispute and `dispute-initiated-by-peer` for the other, both carrying
//! `payload: {"dispute": ["<dispute id>", null]}` (mostrod v0.19.2, flow
//! `dispute_admin_cancel`). Nothing public ties a dispute to its order — the
//! 38386 event names the dispute, never the order — so a client that drops
//! that payload cannot learn the id again.
//!
//! Dispute records live in memory (`api::disputes`), so the id went with the
//! process: after a restart the record was rebuilt with a freshly minted UUID,
//! and the party that did not open the dispute never held a record at all
//! until a solver took it. This module is the durable half: the id, and — for
//! the party the message says opened it — the origin marker the record needs
//! to describe itself correctly once it is rebuilt.
//!
//! Two settings keys per order, both identity-scoped and both cleared with
//! the trade's other dispute keys (`settings_keys::dispute_id`,
//! `settings_keys::dispute_mine`). Lives here rather than in `api/` because
//! nothing in it is callable from Dart.

use crate::db::{settings_keys, Storage};

/// Keep what a `dispute-initiated-by-*` message says about the dispute on
/// `order_id`: the node's id for it and, when the message is the
/// `by-you` one, that this side opened it.
///
/// Returns whether the id is **news** — stored now and different from what
/// was stored before. The caller uses that to build the dispute record once,
/// rather than on every replay of the same message: the global kind-14 feed
/// re-delivers it on every start for as long as the dispute is open.
///
/// A message without a dispute id stores nothing and is not news: the record
/// it would announce could not be told from one with a made-up id. Without a
/// store nothing is kept either — best effort, like every other dispute key.
pub(crate) async fn remember(order_id: &str, dispute_id: Option<&str>, opened_by_me: bool) -> bool {
    match crate::db::app_db::db() {
        Some(db) => remember_in(db, order_id, dispute_id, opened_by_me).await,
        None => false,
    }
}

/// The node's dispute id for `order_id`, if a message ever carried one here.
pub(crate) async fn recall(order_id: &str) -> Option<String> {
    recall_in(crate::db::app_db::db()?, order_id).await
}

/// [`remember`] against a given store.
pub(crate) async fn remember_in(
    db: &impl Storage,
    order_id: &str,
    dispute_id: Option<&str>,
    opened_by_me: bool,
) -> bool {
    let Some(dispute_id) = dispute_id.map(str::trim).filter(|id| !id.is_empty()) else {
        crate::api::logging::blog_warn(
            "disputes",
            format!(
                "dispute opened on order={} without a dispute id — nothing kept",
                crate::api::logging::short_id(order_id),
            ),
        );
        return false;
    };
    // The origin first: a record rebuilt between the two writes would
    // otherwise read as opened by the counterparty. Written only for the
    // side the daemon says opened it, and never cleared from here — the
    // peer's message cannot un-open a dispute this side opened.
    if opened_by_me {
        if let Err(e) = db
            .set_setting(&settings_keys::dispute_mine(order_id), "1")
            .await
        {
            crate::api::logging::blog_warn(
                "disputes",
                format!("could not persist dispute origin for {order_id}: {e}"),
            );
        }
    }
    let key = settings_keys::dispute_id(order_id);
    let known = match db.get_setting(&key).await {
        Ok(known) => known,
        Err(e) => {
            crate::api::logging::blog_warn(
                "disputes",
                format!("could not read the dispute id of {order_id}: {e}"),
            );
            None
        }
    };
    if known.as_deref() == Some(dispute_id) {
        return false;
    }
    if let Err(e) = db.set_setting(&key, dispute_id).await {
        crate::api::logging::blog_warn(
            "disputes",
            format!("could not persist the dispute id of {order_id}: {e}"),
        );
        return false;
    }
    crate::api::logging::blog_info(
        "disputes",
        format!(
            "dispute id kept for order={} opened_by_me={opened_by_me}",
            crate::api::logging::short_id(order_id),
        ),
    );
    true
}

/// [`recall`] against a given store. A read error is "unknown", logged: the
/// caller falls back to what it did before the id was kept.
pub(crate) async fn recall_in(db: &impl Storage, order_id: &str) -> Option<String> {
    match db.get_setting(&settings_keys::dispute_id(order_id)).await {
        Ok(id) => id.filter(|id| !id.trim().is_empty()),
        Err(e) => {
            crate::api::logging::blog_warn(
                "disputes",
                format!("could not read the dispute id of {order_id}: {e}"),
            );
            None
        }
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::db::sqlite::SqliteStorage;

    /// A store of its own per test: the process-wide one is shared by every
    /// test running in parallel.
    async fn temp_storage(tag: &str) -> (SqliteStorage, std::path::PathBuf) {
        let path = std::env::temp_dir().join(format!(
            "mostro_dispute_ids_{}_{tag}.db",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        (storage, path)
    }

    /// mostrod v0.19.2, flow `dispute_admin_cancel`: the id both parties get.
    const NODE_DISPUTE_ID: &str = "1b84909d-bbf5-405a-ae1e-3e2beafa5458";
    const ORDER_ID: &str = "deb9ccdf-4f5c-43a3-9988-0dc630bb8c5f";

    #[tokio::test]
    async fn the_peers_message_keeps_the_id_and_no_origin() {
        let (db, path) = temp_storage("peer").await;

        assert_eq!(recall_in(&db, ORDER_ID).await, None);
        assert!(
            remember_in(&db, ORDER_ID, Some(NODE_DISPUTE_ID), false).await,
            "the first sight of the id is news"
        );
        assert_eq!(
            recall_in(&db, ORDER_ID).await.as_deref(),
            Some(NODE_DISPUTE_ID)
        );
        assert_eq!(
            db.get_setting(&settings_keys::dispute_mine(ORDER_ID))
                .await
                .unwrap(),
            None,
            "the counterparty opened it: no origin marker"
        );

        // The feed replays the message on every start: not news again.
        assert!(!remember_in(&db, ORDER_ID, Some(NODE_DISPUTE_ID), false).await);

        // It survives the restart it exists for.
        drop(db);
        let db = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        assert_eq!(
            recall_in(&db, ORDER_ID).await.as_deref(),
            Some(NODE_DISPUTE_ID)
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn the_initiators_message_keeps_the_id_and_the_origin() {
        let (db, path) = temp_storage("mine").await;

        assert!(remember_in(&db, ORDER_ID, Some(NODE_DISPUTE_ID), true).await);
        assert_eq!(
            recall_in(&db, ORDER_ID).await.as_deref(),
            Some(NODE_DISPUTE_ID)
        );
        assert_eq!(
            db.get_setting(&settings_keys::dispute_mine(ORDER_ID))
                .await
                .unwrap()
                .as_deref(),
            Some("1")
        );

        // A peer-side copy arriving later cannot un-open it.
        assert!(!remember_in(&db, ORDER_ID, Some(NODE_DISPUTE_ID), false).await);
        assert_eq!(
            db.get_setting(&settings_keys::dispute_mine(ORDER_ID))
                .await
                .unwrap()
                .as_deref(),
            Some("1")
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn a_message_without_an_id_keeps_nothing() {
        let (db, path) = temp_storage("no_id").await;

        for missing in [None, Some(""), Some("   ")] {
            assert!(!remember_in(&db, ORDER_ID, missing, true).await);
        }
        assert_eq!(recall_in(&db, ORDER_ID).await, None);
        assert_eq!(
            db.get_setting(&settings_keys::dispute_mine(ORDER_ID))
                .await
                .unwrap(),
            None,
            "no id, no dispute to mark as ours"
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    /// The id is per order, and it goes with the identity that traded.
    #[tokio::test]
    async fn the_id_is_per_order_and_wiped_with_the_identity() {
        let (db, path) = temp_storage("scope").await;

        remember_in(&db, "order-a", Some("dispute-a"), false).await;
        remember_in(&db, "order-b", Some("dispute-b"), true).await;
        assert_eq!(recall_in(&db, "order-a").await.as_deref(), Some("dispute-a"));
        assert_eq!(recall_in(&db, "order-b").await.as_deref(), Some("dispute-b"));
        assert!(settings_keys::IDENTITY_SCOPED_PREFIXES
            .contains(&settings_keys::DISPUTE_ID_PREFIX));

        db.clear_identity_data().await.unwrap();
        assert_eq!(recall_in(&db, "order-a").await, None);
        assert_eq!(recall_in(&db, "order-b").await, None);
        drop(db);
        let _ = std::fs::remove_file(&path);
    }
}
