/// First-launch seed data — populates default relays and Mostro node.
///
/// Called once after DB migration, before relay pool initialization.
/// All operations are idempotent (IF NOT EXISTS / skip-if-present).
use anyhow::Result;

use crate::api::types::{RelayInfo, RelaySource, RelayStatus};
use crate::config;
use crate::db::{settings_keys, Storage};

/// Seed default relays if not already present.
pub async fn seed_defaults<S: Storage>(storage: &S) -> Result<()> {
    seed_default_relays(storage).await?;
    Ok(())
}

/// Seed `DEFAULT_RELAYS` into the relay table if no relays exist yet.
async fn seed_default_relays<S: Storage>(storage: &S) -> Result<()> {
    let existing = storage.list_relays().await?;
    if !existing.is_empty() {
        return Ok(());
    }

    for url in config::DEFAULT_RELAYS {
        let relay = RelayInfo {
            url: url.to_string(),
            is_active: true,
            is_default: true,
            source: RelaySource::Default,
            is_blacklisted: false,
            status: RelayStatus::Disconnected,
            last_connected_at: None,
            last_error: None,
        };
        storage.save_relay(&relay).await?;
    }

    Ok(())
}

/// Bring the persisted active node in line with the one node the app serves.
///
/// The app trades on `DEFAULT_MOSTRO_PUBKEY` only, but an install that
/// predates that may hold another node as its active one, plus the community
/// profile that described it. Both go, so `rehydrate_active_mostro_node`
/// finds the pinned node. Nothing persisted, or the pinned node already,
/// is left alone. Returns `true` when a foreign node was replaced.
///
/// Runs when the store opens — before the rehydrate, and before a test build
/// seeds its own daemon through `set_active_mostro_node`.
pub async fn pin_active_node<S: Storage>(storage: &S) -> Result<bool> {
    let pinned = config::DEFAULT_MOSTRO_PUBKEY;
    match storage.get_active_mostro_pubkey().await? {
        Some(persisted) if !persisted.eq_ignore_ascii_case(pinned) => {
            // The node goes last: it is what this match reads, so a write
            // that fails anywhere below leaves the whole repair to be retried
            // on the next launch. The first two are the same writes as
            // `api::community::clear_active_community_profile`.
            storage
                .set_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE, "")
                .await?;
            storage
                .set_setting(settings_keys::COMMUNITY_PAYMENT_METHODS, "[]")
                .await?;
            // And the date of that node's card, or the pinned node's own —
            // possibly signed earlier — would be refused as older.
            storage
                .set_setting(settings_keys::COMMUNITY_CARD_AT, "")
                .await?;
            storage.save_active_mostro_pubkey(pinned).await?;
            Ok(true)
        }
        _ => Ok(false),
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::db::sqlite::SqliteStorage;

    /// A store of its own per test: the pin is exercised against real rows
    /// without touching the process-wide singleton.
    async fn temp_storage(tag: &str) -> (SqliteStorage, std::path::PathBuf) {
        let path =
            std::env::temp_dir().join(format!("mostro_pin_{}_{tag}.db", std::process::id()));
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        (storage, path)
    }

    #[tokio::test]
    async fn an_install_on_another_node_is_moved_to_the_pinned_one() {
        // Arrange — the node the app used to default to, plus its profile.
        let (db, path) = temp_storage("foreign").await;
        let other = "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";
        db.save_active_mostro_pubkey(other).await.unwrap();
        db.set_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE, "{\"name\":\"x\"}")
            .await
            .unwrap();
        db.set_setting(settings_keys::COMMUNITY_PAYMENT_METHODS, "[\"Zelle\"]")
            .await
            .unwrap();

        // Act
        let moved = pin_active_node(&db).await.unwrap();

        // Assert
        assert!(moved);
        assert_eq!(
            db.get_active_mostro_pubkey().await.unwrap().as_deref(),
            Some(config::DEFAULT_MOSTRO_PUBKEY)
        );
        assert_eq!(
            db.get_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE)
                .await
                .unwrap()
                .as_deref(),
            Some("")
        );
        assert_eq!(
            db.get_setting(settings_keys::COMMUNITY_PAYMENT_METHODS)
                .await
                .unwrap()
                .as_deref(),
            Some("[]")
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn a_fresh_or_already_pinned_install_is_left_alone() {
        let (db, path) = temp_storage("pinned").await;

        // Fresh install: nothing persisted, nothing written.
        assert!(!pin_active_node(&db).await.unwrap());
        assert_eq!(db.get_active_mostro_pubkey().await.unwrap(), None);

        // Already on the pinned node, in any case: its profile survives.
        db.save_active_mostro_pubkey(&config::DEFAULT_MOSTRO_PUBKEY.to_uppercase())
            .await
            .unwrap();
        db.set_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE, "{\"name\":\"BitMaxis\"}")
            .await
            .unwrap();
        assert!(!pin_active_node(&db).await.unwrap());
        assert_eq!(
            db.get_setting(settings_keys::ACTIVE_COMMUNITY_PROFILE)
                .await
                .unwrap()
                .as_deref(),
            Some("{\"name\":\"BitMaxis\"}")
        );
        drop(db);
        let _ = std::fs::remove_file(&path);
    }
}
