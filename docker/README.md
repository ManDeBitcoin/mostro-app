# Coolify deployment (this fork only)

This fork runs **upstream [`MostroP2P/app`](https://github.com/MostroP2P/app) as it is**, built
for the web and served by nginx from a Docker image that Coolify builds. It adds only new files
and edits no upstream file, so merging upstream never conflicts:

| File | Purpose |
| --- | --- |
| `Dockerfile.web` | Builds the Rust core to wasm and the Flutter web bundle, serves it with nginx |
| `.dockerignore` | Keeps local build outputs out of the build context |
| `docker/nginx.conf` | Cross-origin isolation headers, SPA fallback, cache policy |
| `docker/README.md` | This file |
| `test/web/nginx_cache_test.dart` | Holds the cache policy of `docker/nginx.conf` |
| `.claude/rules/fork.md` | How to work in this fork: upstream vs fork-only changes (Spanish; Claude Code loads it) |

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
| `FLUTTER_VERSION`, `RUST_VERSION`, `WASM_PACK_VERSION` | upstream's | Toolchain; keep equal to `.github/workflows/web-build.yml` |

A runtime environment variable on the container changes nothing: the app is static files, and
everything it knows was compiled in. That includes the Mostro node and relays, which are
upstream's defaults (`rust/src/config.rs`) — users choose their node in the app.

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

`main` of this fork is upstream's `main` plus the files above. To take a new upstream version:

```bash
git fetch upstream
git switch -c sync/upstream-YYYYMMDD origin/main
git merge upstream/main          # never conflicts while no upstream file is edited here
git diff --stat upstream/main...HEAD
```

Then compare the toolchain in upstream's `.github/workflows/web-build.yml` (`env:` block) and its
`flutter build web` flags with `Dockerfile.web`, update the `ARG`s if they moved, open a PR to
`main` and deploy it to staging before production. GitHub's **Sync fork** button does the merge
step too.

Upstream's workflows come along with its code. `deploy-pages.yml` publishes to GitHub Pages on
every push to `main` and `release.yml` signs APKs on a tag — neither is wanted here. Turn them off
in the fork's *Actions* settings rather than by editing them, which would conflict with every
merge.
