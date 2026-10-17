# Coolify deployment (this fork only)

This fork runs **upstream [`MostroP2P/app`](https://github.com/MostroP2P/app) as it is**, built
for the web and served by nginx from a Docker image that Coolify builds. It adds only new files
and edits no upstream file in git, so merging upstream never conflicts. Its defaults (below)
are applied inside the image, at build time:

| File | Purpose |
| --- | --- |
| `Dockerfile.web` | Builds the Rust core to wasm and the Flutter web bundle, serves it with nginx |
| `.dockerignore` | Keeps local build outputs out of the build context |
| `docker/nginx.conf` | Cross-origin isolation headers, SPA fallback, cache policy |
| `docker/README.md` | This file |
| `test/web/nginx_cache_test.dart` | Holds the cache policy of `docker/nginx.conf` |
| `.claude/rules/fork.md` | How to work in this fork: upstream vs fork-only changes (Spanish; Claude Code loads it) |
| `docker/fork_overlay.py` | Applies the fork's defaults to the image's copy of upstream's source |
| `docker/payment_methods.json` | Payment methods the fork suggests first, per currency |
| `docker/share_preview.html` | Link preview (Open Graph) tags added to `web/index.html` |
| `docker/og.jpg` | Link preview image, served at `/og.jpg` |
| `.github/workflows/fork-sync-upstream.yml` | Weekly pull request that brings upstream's `main` (below) |

Anything else that differs from `upstream/main` is a mistake. Check with:

```bash
git fetch upstream
git diff --stat upstream/main...HEAD   # must list only the files above
```

## Coolify resource

| Setting | Value |
| --- | --- |
| Build pack | Dockerfile |
| Base directory | `/` |
| Dockerfile location | `Dockerfile.web` |
| Ports exposes | `80` |
| Domain | a (sub)domain of its own, HTTPS on |

Build arguments (all optional, all compiled into the public bundle):

| Argument | Default | Meaning |
| --- | --- | --- |
| `BASE_HREF` | `/` | Path the app is served under. Keep `/` on a dedicated (sub)domain |
| `FCM_VAPID_KEY` | empty | Web Push public key, as upstream's build takes it |
| `PUSH_WEB_ENABLED` | empty | `true` turns web push on (docs/PUSH_NOTIFICATIONS.md) |
| `MOSTRO_DEFAULT_NODE` | BitMaxis | Hex pubkey of the node a new user starts on; must be in upstream's `TRUSTED_MOSTRO_NODES`. Empty keeps upstream's |
| `FLUTTER_VERSION`, `RUST_VERSION`, `WASM_PACK_VERSION` | upstream's | Toolchain; keep equal to `.github/workflows/web-build.yml` |

A runtime environment variable on the container changes nothing: the app is static files, and
everything it knows was compiled in. That includes the Mostro node and relays.

## The fork's defaults

`Dockerfile.web` runs `docker/fork_overlay.py` right after copying the source in. It edits that
copy, never the repository:

- **Default node:** `MOSTRO_DEFAULT_NODE` (BitMaxis) replaces `DEFAULT_MOSTRO_PUBKEY` in
  `rust/src/config.rs` and `defaultMostroPubkey` in `lib/core/mostro_defaults.dart`. Upstream's
  node stays in the trusted list, and users switch nodes in the app as in upstream. Relays are
  upstream's: the app adds the ones the node lists in its kind 10002 event.
- **Payment methods:** each currency in `docker/payment_methods.json` gets those methods first in
  `assets/data/payment_methods.json`, followed by upstream's (Ecuador's, under `USD`).
- **Link preview:** the Open Graph tags of `docker/share_preview.html` go just before `</head>`
  in `web/index.html`, so a shared link shows `docker/og.jpg` (served at `/og.jpg`). They name
  `app.bitmaxis.com`: another deployment edits that file.

If upstream moves what the script expects, it exits non-zero and the build fails, so Coolify
keeps the previous image instead of shipping one without the defaults.

The image needs no volume. A user's identity, trades and settings live in **their browser**
(IndexedDB and local storage of the app's origin), not on the server. Two consequences:

- Changing the domain changes the origin, and users find an empty app there. Keep the domain.
- Rolling back the image does not roll back what a newer build wrote into a browser.

The first build compiles Rust's standard library for wasm and takes a while (tens of minutes on
a small server); give the builder a few GB of RAM.

## After a deploy

```bash
curl -sI https://YOUR-DOMAIN/ | grep -i -E 'cross-origin|cache-control'
```

must show `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`. In the browser console,
`window.crossOriginIsolated` must be `true`; a blank page with `SharedArrayBuffer` or
`DataCloneError` in the console means it is not.

## Following upstream

`.github/workflows/fork-sync-upstream.yml` does this every Monday (or on demand, from Actions):
it merges upstream's `main` into the branch `sync/upstream`, takes the toolchain of
`web-build.yml` into `Dockerfile.web`, runs `fork_overlay.py --check`, builds `Dockerfile.web`
and opens or refreshes the pull request to `main`. It needs "Allow GitHub Actions to create and
approve pull requests" in the repository's Actions settings.

`main` of this fork is upstream's `main` plus the files above. To take a new upstream version by hand:

```bash
git fetch upstream
git switch -c sync/upstream-YYYYMMDD origin/main
git merge upstream/main          # never conflicts while no upstream file is edited here
git diff --stat upstream/main...HEAD
python3 docker/fork_overlay.py --check 001bd4747d7d265edfe3bd3b7299886146ad850d51095fe77b763c32015685b9   # the defaults still apply
```

Then compare the toolchain in upstream's `.github/workflows/web-build.yml` (`env:` block) and its
`flutter build web` flags with `Dockerfile.web`, update the `ARG`s if they moved, open a PR to
`main` and deploy it to staging before production. GitHub's **Sync fork** button does the merge
step too.

Upstream's workflows come along with its code. `deploy-pages.yml` publishes to GitHub Pages on
every push to `main` and `release.yml` signs APKs on a tag — neither is wanted here. Turn them off
in the fork's *Actions* settings rather than by editing them, which would conflict with every
merge.
