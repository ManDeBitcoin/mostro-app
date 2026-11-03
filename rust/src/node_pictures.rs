//! The pictures of the registry's nodes, kept on the device.
//!
//! A node's face — the `picture` of its kind 0 profile — is what the node
//! selector shows beside it and what a QR that pays the node shows in its
//! centre (#851). Loaded straight from its URL, it was downloaded again on
//! every launch, at the moment the first QR needed it, and the QR's centre
//! stayed blank until it came. So the bytes are downloaded when the profile
//! is ([`sync`], after every kind 0 refresh) and kept with the URL they came
//! from: a picture is fetched again only when the profile names another URL,
//! or when an earlier download failed.
//!
//! The bytes are kept as served. Decoding them is the UI's job, as it was
//! when the UI fetched them: on the web, Rust runs on the page's only thread,
//! and a picture of a few megabytes would freeze it while it decoded.
use std::collections::HashMap;
use std::future::Future;
use std::sync::OnceLock;
use std::time::Duration;

use anyhow::{anyhow, bail, Result};
use tokio::sync::Mutex;

use crate::api::logging::short_id;
use crate::api::types::MostroNodeEntry;
use crate::db::Storage;

/// The largest picture kept. The heaviest a registry node publishes today
/// weighs 1.4 MB; a larger one is not stored, and the UI loads it from its
/// URL.
pub(crate) const MAX_PICTURE_BYTES: usize = 5 * 1024 * 1024;

/// How long one download may take: a few megabytes on a slow mobile link.
const FETCH_TIMEOUT: Duration = Duration::from_secs(30);

/// Serializes syncs: two that overlapped would download the same pictures.
/// Held across the downloads — the second sync then finds them stored.
static SYNC_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

/// What one sync does.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct SyncPlan {
    /// `(pubkey, url)` of each node whose picture is not stored, or was
    /// stored from another URL.
    pub fetch: Vec<(String, String)>,
    /// Stored pictures no node names any more: the node left the registry,
    /// or its profile no longer has a picture.
    pub drop: Vec<String>,
}

/// Compare what the profiles name (`nodes`, as `api::nodes` lists them) with
/// the URL each stored picture came from (`stored`, by pubkey).
pub(crate) fn plan(nodes: &[MostroNodeEntry], stored: &HashMap<String, String>) -> SyncPlan {
    let mut out = SyncPlan::default();
    for node in nodes {
        if let Some(url) = &node.picture {
            if stored.get(&node.pubkey) != Some(url) {
                out.fetch.push((node.pubkey.clone(), url.clone()));
            }
        }
    }
    let mut drop: Vec<String> = stored
        .keys()
        .filter(|pubkey| {
            !nodes
                .iter()
                .any(|n| &n.pubkey == *pubkey && n.picture.is_some())
        })
        .cloned()
        .collect();
    drop.sort();
    out.drop = drop;
    out
}

/// Whether `bytes` start like an image Flutter decodes on every platform:
/// PNG, JPEG, GIF, WebP, BMP or ICO. Anything else — an HTML error page
/// served with a 200, an SVG — is not kept, and the UI falls back to the
/// URL as it did before.
pub(crate) fn is_image(bytes: &[u8]) -> bool {
    bytes.starts_with(b"\x89PNG\r\n\x1a\n")
        || bytes.starts_with(&[0xFF, 0xD8, 0xFF])
        || bytes.starts_with(b"GIF8")
        || (bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP")
        || bytes.starts_with(b"BM")
        || bytes.starts_with(&[0x00, 0x00, 0x01, 0x00])
}

/// Download the picture at `url`. Only `https://` is fetched: a kind 0 event
/// is attacker-controlled, and `api::nodes` keeps nothing else anyway.
pub(crate) async fn download(url: &str) -> Result<Vec<u8>> {
    if !url.starts_with("https://") {
        bail!("only https URLs are fetched");
    }
    fetch(url, MAX_PICTURE_BYTES).await
}

/// Most redirects a download follows.
#[cfg(not(target_arch = "wasm32"))]
const MAX_REDIRECTS: usize = 5;

/// The same client on both targets, as for Blossom (`nostr::blossom`): on
/// the web it is the browser's `fetch`, a CORS request that a host without
/// `Access-Control-Allow-Origin` refuses. The UI then loads the picture from
/// its URL, as it did before.
///
/// Natively a redirect may not leave https: the URL comes from a profile
/// anyone can publish, and every launch now follows it without the user
/// opening anything. The browser follows redirects itself, and an https page
/// may not load plain http.
fn http_client() -> Result<reqwest::Client> {
    let builder = reqwest::Client::builder();
    #[cfg(not(target_arch = "wasm32"))]
    let builder = builder.redirect(reqwest::redirect::Policy::custom(|attempt| {
        if attempt.url().scheme() != "https" {
            attempt.stop()
        } else if attempt.previous().len() > MAX_REDIRECTS {
            attempt.error("too many redirects")
        } else {
            attempt.follow()
        }
    }));
    builder
        .build()
        .map_err(|e| anyhow!("HTTP client build failed: {e}"))
}

/// Download `url` whole, refusing a body over `max_bytes` — by its declared
/// length and by the bytes themselves, since a server may omit the header
/// or lie — and one that is not an image ([`is_image`]). A redirect off
/// https is not followed ([`http_client`]): its 3xx is the answer, an error.
async fn fetch(url: &str, max_bytes: usize) -> Result<Vec<u8>> {
    use futures_util::StreamExt;

    // Per request: the wasm builder has no timeout.
    let response = http_client()?
        .get(url)
        .timeout(FETCH_TIMEOUT)
        .send()
        .await
        .map_err(|e| anyhow!("GET failed: {e}"))?;
    if !response.status().is_success() {
        bail!("server returned {}", response.status());
    }
    if response
        .content_length()
        .is_some_and(|len| len > max_bytes as u64)
    {
        bail!("larger than {max_bytes} bytes");
    }
    let mut bytes = Vec::new();
    let mut chunks = response.bytes_stream();
    while let Some(chunk) = chunks.next().await {
        let chunk = chunk.map_err(|e| anyhow!("reading body: {e}"))?;
        bytes.extend_from_slice(&chunk);
        if bytes.len() > max_bytes {
            bail!("larger than {max_bytes} bytes");
        }
    }
    if !is_image(&bytes) {
        bail!("not an image");
    }
    Ok(bytes)
}

/// Bring the stored pictures in line with `nodes`: download each new or
/// changed picture, drop the ones no node names. Returns the pubkeys whose
/// stored picture changed, for the UI to read again.
///
/// Best effort, per picture: a failed download is logged and tried again on
/// the next sync, and the node keeps whatever was stored before — which the
/// UI shows only while the profile still names its URL.
pub(crate) async fn sync(db: &impl Storage, nodes: &[MostroNodeEntry]) -> Result<Vec<String>> {
    let _guard = SYNC_LOCK.get_or_init(|| Mutex::new(())).lock().await;
    sync_with(db, nodes, |url| async move { download(&url).await }).await
}

/// [`sync`] with the downloader as a parameter: a seam for tests.
async fn sync_with<F, Fut>(
    db: &impl Storage,
    nodes: &[MostroNodeEntry],
    fetch: F,
) -> Result<Vec<String>>
where
    F: Fn(String) -> Fut,
    Fut: Future<Output = Result<Vec<u8>>>,
{
    let plan = plan(nodes, &db.list_node_picture_urls().await?);
    let mut changed = Vec::new();

    // Each URL once, though several nodes may name it; side by side, since
    // a first launch fetches every node's picture.
    let mut urls: Vec<&String> = plan.fetch.iter().map(|(_, url)| url).collect();
    urls.sort();
    urls.dedup();
    let downloads =
        futures_util::future::join_all(urls.iter().map(|url| fetch((*url).clone()))).await;
    let downloaded: HashMap<&String, Result<Vec<u8>>> = urls.into_iter().zip(downloads).collect();
    for (pubkey, url) in &plan.fetch {
        let bytes = match &downloaded[url] {
            Ok(bytes) => bytes,
            Err(e) => {
                log::warn!("[node_pictures] {}: download failed: {e}", short_id(pubkey));
                continue;
            }
        };
        match db.save_node_picture(pubkey, url, bytes).await {
            Ok(()) => changed.push(pubkey.clone()),
            Err(e) => log::warn!("[node_pictures] {}: not stored: {e}", short_id(pubkey)),
        }
    }

    for pubkey in plan.drop {
        match db.delete_node_picture(&pubkey).await {
            Ok(()) => changed.push(pubkey),
            Err(e) => log::warn!("[node_pictures] {}: not dropped: {e}", short_id(&pubkey)),
        }
    }
    Ok(changed)
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::db::sqlite::SqliteStorage;
    use crate::nostr::blossom::test_server::serve;
    use std::sync::atomic::{AtomicU32, Ordering};

    const PNG: &[u8] = b"\x89PNG\r\n\x1a\n rest of a png";

    fn node(pubkey: &str, picture: Option<&str>) -> MostroNodeEntry {
        MostroNodeEntry {
            pubkey: pubkey.into(),
            region: None,
            is_trusted: true,
            is_active: false,
            name: None,
            picture: picture.map(str::to_string),
            about: None,
            website: None,
        }
    }

    fn stored(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    async fn store() -> SqliteStorage {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "mostro_node_pictures_{}_{n}.db",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        SqliteStorage::open(path.to_str().unwrap()).await.unwrap()
    }

    #[test]
    fn plan_fetches_a_picture_not_stored_or_stored_from_another_url() {
        let nodes = [
            node("a", Some("https://a/1.png")),
            node("b", Some("https://b/2.png")),
            node("c", Some("https://c/3.png")),
        ];
        let plan = plan(
            &nodes,
            &stored(&[("b", "https://b/old.png"), ("c", "https://c/3.png")]),
        );
        assert_eq!(
            plan.fetch,
            vec![
                ("a".to_string(), "https://a/1.png".to_string()),
                ("b".to_string(), "https://b/2.png".to_string()),
            ]
        );
        assert!(plan.drop.is_empty());
    }

    #[test]
    fn plan_drops_a_picture_no_node_names() {
        let nodes = [node("a", None), node("b", Some("https://b/2.png"))];
        let plan = plan(
            &nodes,
            &stored(&[
                ("a", "https://a/1.png"),
                ("b", "https://b/2.png"),
                ("gone", "https://g/1.png"),
            ]),
        );
        assert!(plan.fetch.is_empty());
        assert_eq!(plan.drop, vec!["a".to_string(), "gone".to_string()]);
    }

    #[test]
    fn is_image_knows_the_formats_flutter_decodes() {
        for bytes in [
            PNG,
            &[0xFF, 0xD8, 0xFF, 0xE1][..],
            b"GIF89a....",
            b"RIFF\x10\x00\x00\x00WEBPVP8 ",
            b"BM\x00\x00",
            &[0x00, 0x00, 0x01, 0x00, 0x03][..],
        ] {
            assert!(is_image(bytes), "{bytes:?}");
        }
        for bytes in [
            &b""[..],
            b"<!DOCTYPE html><html>",
            b"<svg xmlns=\"http://www.w3.org/2000/svg\">",
            b"RIFF\x10\x00\x00\x00WAVE",
        ] {
            assert!(!is_image(bytes), "{bytes:?}");
        }
    }

    #[tokio::test]
    async fn fetch_returns_an_image_whole() {
        let (base, _) = serve(200, PNG.to_vec()).await;
        assert_eq!(fetch(&format!("{base}/p.png"), 1024).await.unwrap(), PNG);
    }

    #[tokio::test]
    async fn fetch_refuses_an_error_a_non_image_and_an_oversized_body() {
        let (base, _) = serve(404, PNG.to_vec()).await;
        assert!(fetch(&format!("{base}/p.png"), 1024).await.is_err());

        let (base, _) = serve(200, b"<html>moved</html>".to_vec()).await;
        let err = fetch(&format!("{base}/p.png"), 1024).await.unwrap_err();
        assert!(err.to_string().contains("not an image"), "{err}");

        let (base, _) = serve(200, PNG.to_vec()).await;
        let err = fetch(&format!("{base}/p.png"), 8).await.unwrap_err();
        assert!(err.to_string().contains("larger than"), "{err}");
    }

    #[tokio::test]
    async fn fetch_does_not_follow_a_redirect_off_https() {
        use tokio::io::AsyncWriteExt;

        let (target, seen) = serve(200, PNG.to_vec()).await;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let reply = format!(
                "HTTP/1.1 302 Found\r\nLocation: {target}/p.png\r\n\
                 Content-Length: 0\r\nConnection: close\r\n\r\n"
            );
            socket.write_all(reply.as_bytes()).await.unwrap();
            socket.shutdown().await.ok();
        });

        let err = fetch(&format!("{base}/p.png"), 1024).await.unwrap_err();
        assert!(err.to_string().contains("302"), "{err}");
        assert!(seen.lock().unwrap().is_empty(), "the http target was asked");
    }

    #[tokio::test]
    async fn download_fetches_https_only() {
        let (base, seen) = serve(200, PNG.to_vec()).await;
        assert!(download(&format!("{base}/p.png")).await.is_err());
        assert!(seen.lock().unwrap().is_empty());
    }

    /// A downloader that serves `PNG` plus the URL, fails on URLs holding
    /// "broken", and counts its calls.
    fn fake(calls: &AtomicU32) -> impl Fn(String) -> std::future::Ready<Result<Vec<u8>>> + '_ {
        move |url: String| {
            calls.fetch_add(1, Ordering::Relaxed);
            std::future::ready(if url.contains("broken") {
                Err(anyhow!("unreachable"))
            } else {
                Ok([PNG, url.as_bytes()].concat())
            })
        }
    }

    #[tokio::test]
    async fn sync_downloads_a_picture_once_until_its_url_changes() {
        let db = store().await;
        let calls = AtomicU32::new(0);
        let first = [
            node("a", Some("https://a/1.png")),
            node("b", Some("https://b/1.png")),
        ];

        let changed = sync_with(&db, &first, fake(&calls)).await.unwrap();
        assert_eq!(changed, vec!["a".to_string(), "b".to_string()]);
        let a = db.get_node_picture("a").await.unwrap().unwrap();
        assert_eq!(a.url, "https://a/1.png");
        assert_eq!(a.bytes, [PNG, b"https://a/1.png"].concat());

        // The same profiles again — the next launch: nothing is downloaded.
        assert!(sync_with(&db, &first, fake(&calls))
            .await
            .unwrap()
            .is_empty());
        assert_eq!(calls.load(Ordering::Relaxed), 2);

        // A new URL is a new picture.
        let edited = [
            node("a", Some("https://a/2.png")),
            node("b", Some("https://b/1.png")),
        ];
        let changed = sync_with(&db, &edited, fake(&calls)).await.unwrap();
        assert_eq!(changed, vec!["a".to_string()]);
        assert_eq!(calls.load(Ordering::Relaxed), 3);
        let a = db.get_node_picture("a").await.unwrap().unwrap();
        assert_eq!(a.url, "https://a/2.png");
    }

    #[tokio::test]
    async fn sync_downloads_a_url_two_nodes_share_once() {
        let db = store().await;
        let calls = AtomicU32::new(0);
        let shared = [
            node("a", Some("https://same/p.png")),
            node("b", Some("https://same/p.png")),
        ];

        let changed = sync_with(&db, &shared, fake(&calls)).await.unwrap();
        assert_eq!(changed, vec!["a".to_string(), "b".to_string()]);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        assert_eq!(
            db.get_node_picture("b").await.unwrap().unwrap().bytes,
            [PNG, b"https://same/p.png"].concat()
        );
    }

    #[tokio::test]
    async fn sync_keeps_the_old_picture_when_a_download_fails_and_retries_next_time() {
        let db = store().await;
        let calls = AtomicU32::new(0);
        sync_with(&db, &[node("a", Some("https://a/1.png"))], fake(&calls))
            .await
            .unwrap();

        let broken = [node("a", Some("https://a/broken.png"))];
        assert!(sync_with(&db, &broken, fake(&calls))
            .await
            .unwrap()
            .is_empty());
        assert_eq!(
            db.get_node_picture("a").await.unwrap().unwrap().url,
            "https://a/1.png"
        );
        sync_with(&db, &broken, fake(&calls)).await.unwrap();
        assert_eq!(calls.load(Ordering::Relaxed), 3);
    }

    #[tokio::test]
    async fn sync_drops_the_picture_of_a_node_without_one_or_gone() {
        let db = store().await;
        let calls = AtomicU32::new(0);
        sync_with(
            &db,
            &[
                node("a", Some("https://a/1.png")),
                node("b", Some("https://b/1.png")),
            ],
            fake(&calls),
        )
        .await
        .unwrap();

        let changed = sync_with(&db, &[node("a", None)], fake(&calls))
            .await
            .unwrap();
        assert_eq!(changed, vec!["a".to_string(), "b".to_string()]);
        assert!(db.list_node_picture_urls().await.unwrap().is_empty());
    }
}
