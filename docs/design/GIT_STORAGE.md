# OciDeck — Git-Repository Storage (Design)

> **Status: design proposal — not yet implemented.**
> This document describes a *future* storage backend and the architecture chosen
> for it. It is deliberately kept separate from the current-state contributor
> docs ([`ARCHITECTURE.md`](../ARCHITECTURE.md), [`SOURCE_MAP.md`](../SOURCE_MAP.md),
> [`FILE_FORMAT.md`](../FILE_FORMAT.md)) so that those keep describing what
> exists. When (parts of) this lands, fold the relevant sections into those docs
> and the [`USER_GUIDE.md`](../USER_GUIDE.md), and update the
> [`CHANGELOG.md`](../../CHANGELOG.md).
>
> It is written to be **picked up cold**: exact file paths, integration points,
> data shapes, invariants and open questions are spelled out so a later
> implementation session has everything it needs without re-deriving context.
>
> Sibling design doc: [`COLLABORATION.md`](COLLABORATION.md) (real-time
> co-authoring). Git storage and collaboration are complementary — a room is a
> disposable sync channel, a git repo is durable versioned storage — and share
> the principle *file = truth*.

---

## 1. Purpose & scope

OciDeck should be able to store decks in a **`.git` repository** in addition to
the existing backends (local files, `.ocideck` packages, WebDAV/Nextcloud). This
turns storage into **versioned storage**: every save is a commit, history and
branches become first-class, and *releasing* a presentation becomes a pull
request that is reviewed and merged.

The full existing feature set must keep working against this backend:

- **saving** a deck (→ commit + push),
- **opening / loading** a deck,
- **searching** decks (text) and **searching images**,
- **assets** (images, video) — with *deduplication* as an explicit goal, see §6,
- **exporting / releasing** — release becomes **branch → pull request → merge**,
- **offline authoring** — you must be able to write a presentation on a plane
  with no network and sync later (see §8).

Three hosting providers are in scope, in this order of priority:

1. **Forgejo** (and Gitea, its upstream — same REST surface),
2. **GitHub**,
3. **GitLab**.

### Non-goals (v1)

- Not a general-purpose git client (no arbitrary rebase/cherry-pick UI, no
  submodules, no LFS in v1 — see §12).
- OciDeck operates **no** server of its own. The user points at *their* forge,
  exactly as the WebDAV source lets them point at *their* storage.
- Not re-implementing the git smart-HTTP wire protocol in the online path — see
  the decision in §4.

---

## 2. Design principles (invariants)

These are non-negotiable. Every phase must preserve them.

- **P1 — OciDeck is a client, never a central dependency.** No OciDeck-operated
  server or account system. Same stance as `lib/services/webdav_service.dart`.
- **P2 — File = truth, forge = durable store, local mirror = working copy.** The
  durable artifact is the committed tree on the forge. The editor always writes
  to a **local working copy**; the `SyncEngine` reconciles it with the forge.
  Losing network never loses work.
- **P3 — A deck is a folder of real files, never an opaque blob.** `deck.md` +
  sidecars + *references* into a shared asset pool are committed as individual
  files so that diffs, `blame`, and history are meaningful. Committing an
  encrypted `.ocideck` package would defeat the entire point of versioning.
- **P4 — Assets are content-addressed and shared.** An image/video is stored once
  per repo under `assets/<hash>.<ext>` and referenced by many decks. This is the
  resource-efficiency goal (§6): the same asset never exists "dozens of times".
- **P5 — Every inbound `.md` passes the import gate.** Content pulled from a forge
  is untrusted exactly like a URL/package import: it goes through
  `MarkdownSafetyScanner.scan` (`lib/services/markdown_safety.dart`) fail-closed,
  and byte/entry caps apply. A forge is not more trusted than WebDAV.
- **P6 — Provider-agnostic core.** All save/open/search/release logic is written
  against a thin `GitForge` interface. Forgejo/Gitea, GitHub and GitLab are
  implementations behind it. No provider-specific code leaks into the editor or
  state layer.
- **P7 — Reuse, don't re-derive.** The deck→`{path: bytes}` mapping
  (`buildPackageMembers`), image hashing (`image_dedup_service`), SSRF hardening
  (`net_guard`), secret storage (`secret_store`), per-tab origin tracking
  (`WebdavOrigin` → `GitOrigin`) and per-tab provider scope already exist. The git
  backend is assembled from them, not built beside them.
- **P8 — Release is gated.** Opening a release PR is subject to the existing
  classification/TLP enforcement (`ExportService.export()` policy), fail-closed.
  You cannot push a deck past its allowed classification ceiling by routing it
  through git.

---

## 3. Precedent already in the codebase

The git backend is **the WebDAV source with versioning semantics added**. Almost
every building block exists:

| Need | Existing precedent | File |
|---|---|---|
| Network deck source | WebDAV/Nextcloud client | `lib/services/webdav_service.dart` |
| SSRF hardening + trusted-server opt-in | `NetGuard.safeResolveTrusted(host, allowPrivate:)` | `lib/utils/net_guard.dart` |
| Secret in OS keychain | WebDAV password store | `lib/services/secret_store.dart` |
| Per-tab remote origin | `WebdavOrigin {baseUrl, username, remotePath}` | `lib/models/webdav_settings.dart` |
| Deck → `{path: bytes}` map | `buildPackageMembers(deck)` | `lib/services/parts/file_service_package.dart` |
| Content hashing of images | md5 worker in isolate | `lib/services/image_dedup_service.dart` |
| Import safety gate (fail-closed) | `scanForUnsafeMarkdown` / `MarkdownSafetyScanner` | `lib/services/parts/file_service_import.dart`, `lib/services/markdown_safety.dart` |
| Open from bytes (web / remote) | `openDeckFromBytes` | `lib/state/tabs_provider.dart` |
| Per-tab provider overrides | `ProviderScope` overrides per tab | `lib/widgets/app_shell.dart` |
| Same-origin fetch-proxy (web CORS) | `/fetch-proxy?url=` | `lib/services/parts/file_service_net.dart` |
| Classification/quality gate | policy evaluate, fail-closed | `lib/services/export_service.dart` |

The one genuinely new thing is a **`GitForge` REST client** per provider and a
**`SyncEngine`**. Everything else is wiring.

---

## 4. Key decision: forge REST APIs, not the git wire protocol

There are three ways to talk to a git host. The constraint that decides it is
**web is a first-class target** and there are six platforms total.

| Approach | Works on web? | Effort | PR/merge |
|---|---|---|---|
| A. Native git (`libgit2` / `git` CLI) | ❌ no | high (two code paths) | still needs per-forge REST |
| B. Git smart-HTTP protocol in pure Dart (packfiles, ref negotiation) | ⚠️ CORS + huge | very high | still needs per-forge REST |
| C. **Forge REST APIs** (Gitea/Forgejo, GitHub, GitLab) | ✅ yes | moderate, uniform | ✅ native in the API |

**Decision: C for the online path.** The forge *is* the git server; history and
branches already live there. Committing, branching, and opening a PR are all
plain authenticated REST calls. This is uniform across providers, works on web,
and is the direct generalisation of the WebDAV client already in the tree. A pull
request is inherently a server-side, forge-specific concept anyway — the wire
protocol has no notion of it — so B/A would not save that work.

**Offline is handled by a local mirror + sync, not by the wire protocol** (§8).
On desktop that mirror *may* later be a real local git repo for true offline
history; that is an optional enhancement behind the same interface, never a
divergent second behaviour (§12, OQ-4).

The multi-file commit primitive is the only part where providers differ
materially (§7.2); the adapter hides it.

---

## 5. Architecture overview

Four layers. The editor and state layer never see anything below `LocalMirror`.

```
   ┌───────────────────────────────────────────────────────────┐
   │ Editor / state (deck_provider, tabs_provider)              │
   │   save() / open() / search — unchanged surface             │
   └───────────────┬───────────────────────────────────────────┘
                   │ writes/reads a deck as files
                   ▼
   ┌───────────────────────────────────────────────────────────┐
   │ LocalMirror        — the working copy (always available)   │
   │   desktop/mobile: on-disk working tree under app support   │
   │   web:            IndexedDB draft + in-memory WebAssetStore │
   └───────────────┬───────────────────────────────────────────┘
                   │ reconcile (commit/push/pull), queue when offline
                   ▼
   ┌───────────────────────────────────────────────────────────┐
   │ SyncEngine         — reconciles mirror ↔ forge             │
   │   pending-commit outbox, baseSha conflict detection        │
   └───────────────┬───────────────────────────────────────────┘
                   │ REST
                   ▼
   ┌───────────────────────────────────────────────────────────┐
   │ GitForge (interface)   — commitFiles, tree, branch, PR      │
   │   GiteaForge · GitHubForge · GitLabForge                    │
   └───────────────┬───────────────────────────────────────────┘
                   │ hardened HTTP (NetGuard, HTTPS, caps, PAT)
                   ▼
             Forgejo / GitHub / GitLab
```

Cross-cutting: `AssetPool` (content-addressed dedup, §6) sits beside `LocalMirror`
and feeds both reads (resolve `repo:` references) and commits (add only new
blobs).

---

## 6. Repo layout & the shared, content-addressed asset pool

The resource-efficiency requirement — *an asset must not exist dozens of times* —
is met by a **content-addressed pool shared across all decks in the repo**.

```
repo/
  assets/
    3f9a1c8e….png        # filename = hash of the bytes
    b27e0433….mp4
  decks/
    kwartaalcijfers/
      deck.md            # references  repo:assets/3f9a1c8e….png
      deck.annotations   # sidecar (ink strokes)
      deck.notes         # sidecar (speaker notes)
    jaarplan/
      deck.md            # references  repo:assets/3f9a1c8e….png  ← same blob
  themes/                # optional shared theme CSS
    librekat.css
```

Why this satisfies the goal:

- **Filename = content hash.** Two decks using the same image both reference
  `assets/<hash>.png`. Physically it exists once. This *enforces* de-duplication
  rather than hoping for it.
- **The hashing machinery exists.** `image_dedup_service.dart` already hashes
  images in an isolate (md5). Reuse it, but standardise the pool on **SHA-256**
  for collision resistance (md5 stays fine for the existing in-session dedup UI).
- **Git de-duplicates again, for free.** A git blob is itself content-addressed,
  so a repeated asset does not grow the pack/history either.
- **Commit only what is new.** Before committing, check the HEAD tree for
  `assets/<hash>`; if present, commit only the changed `deck.md`, not the asset.

### 6.1 The `repo:` reference scheme

Assets are referenced with a new logical scheme alongside the existing
`mem:` / `asset:` / plain-path schemes:

```
repo:assets/<sha256>.<ext>
```

- Resolved against the **repo root**, not the deck subfolder. (A relative
  `../../assets/…` would be rejected by `resolveProjectRelative` in
  `lib/utils/project_path.dart`, which fail-closes on `..` traversal — correctly.)
- Its own guard: a `repo:` target must normalise to a path under `assets/` and
  must not traverse out of it.
- `markdown_service.dart` must serialise/parse this scheme **round-trip-safely**.
  Respect the existing escaping edge cases (caption-pipe sentinel, decimal video
  seconds, note `--\>`, cell `\<br>`) documented for that file.
- On **web** a `repo:` asset resolves to the in-memory `WebAssetStore` after the
  blob is fetched once; on desktop it resolves to the on-disk pool file.

### 6.2 Garbage collection (deliberately manual)

When no deck references an asset any more, its blob becomes an orphan in the
working tree. A **manual** "clean unused assets" sweep (scan every `deck.md`
across the repo, delete unreferenced `assets/*`) reclaims it. It is *not*
automatic: in a versioned store an asset unreferenced on `main` may still be used
by another branch or an older commit, and silent deletion would be wrong (P2 —
never lose durable content without intent).

---

## 7. The forge abstraction

### 7.1 Interface

```dart
abstract class GitForge {
  // read
  Future<List<RepoEntry>> listTree(String ref, String path, {bool recursive});
  Future<Uint8List>       readBlob(String ref, String path);
  Future<String>          headSha(String branch);

  // write (save = commit + push in one server-side operation)
  Future<CommitResult> commitFiles({
    required String branch,
    required String message,
    required Map<String, List<int>> upserts, // path -> bytes
    required List<String> deletes,
    required String baseSha,                  // optimistic concurrency
  });

  // branches / versions
  Future<void>            createBranch(String from, String name);
  Future<List<BranchRef>> listBranches();
  Future<List<CommitInfo>> history(String ref, String path); // deck timeline

  // release
  Future<PullRequest> openPullRequest({
    required String head, required String base,
    required String title, String? body,
  });
  Future<void> mergePullRequest(int number, MergeMethod method);

  // search (server-side where available, §9.3)
  Future<List<SearchHit>> searchCode(String query);
}
```

Config and per-tab origin mirror the WebDAV models:

```dart
class GitRepoConfig {           // persisted (non-secret) in settings
  final GitProvider provider;   // gitea | github | gitlab
  final String baseUrl;         // e.g. https://git.example.org
  final String owner;           // user / org / group path
  final String repo;
  final String defaultBranch;   // usually "main"
  final bool trustedInternal;   // SSRF opt-in for self-hosted, see §10
}

class GitOrigin {               // per-tab, sits next to TabInfo.webdavOrigin
  final GitRepoConfig config;
  final String branch;
  final String deckDir;         // e.g. "decks/kwartaalcijfers"
  final String baseSha;         // last commit this tab is based on
}
```

The PAT is **never** in `GitRepoConfig`; it lives in `secret_store` keyed by
`baseUrl` + `owner` (§10).

### 7.2 The multi-file commit primitive (where providers differ)

One save = one atomic commit of the changed file set. This is the only place the
providers diverge materially; each adapter hides it behind `commitFiles`:

- **GitLab** — `POST /projects/:id/repository/commits` with an `actions[]` array
  (`create`/`update`/`delete`). One call, atomic.
- **Forgejo / Gitea** — `POST /repos/{owner}/{repo}/contents` (modify-multiple-
  files) with a files array. One call, atomic.
- **GitHub** — no multi-file Contents API. Use the **Git Data API**:
  1. create a blob per changed asset/file,
  2. create a tree from `baseSha`'s tree + the changes,
  3. create a commit with parent `baseSha`,
  4. update the branch ref (`PATCH .../git/refs/heads/{branch}`) — reject if not
     fast-forward.
  Four calls, but the adapter presents the same single `commitFiles` result.

Concurrency: `commitFiles` sends `baseSha`; if the server ref has moved (someone
else committed), it returns a **non-fast-forward conflict**, surfaced to the user
as reload/rebase — the git equivalent of the WebDAV atomic-write guard.

---

## 8. Local-first & the SyncEngine (offline authoring)

Requirement: author on a plane, sync later. The forge is therefore **never the
direct editing target**; a `LocalMirror` is, and the `SyncEngine` reconciles.

```
Editor ──writes──▶ LocalMirror ──SyncEngine──▶ GitForge (commit/push/PR)
                   (offline-capable)            (when connectivity returns)
```

### 8.1 Desktop / mobile

- The mirror is an on-disk working directory under the app-support path:
  `decks/…` + `assets/…`, i.e. exactly the repo layout of §6.
- Saving writes files **locally and immediately** (this is how desktop already
  works — a real `filePath`), then enqueues a **pending commit** in an outbox.
- The `SyncEngine` drains the outbox when a connectivity/`NetGuard` check passes:
  each pending commit becomes a `commitFiles` call (or, if the desktop native-git
  option of OQ-4 is enabled, a local `git commit` now + `git push` later, giving
  true offline history).
- Conflict on push → `baseSha` mismatch → present reload/merge.

### 8.2 Web

- No persistent filesystem. The mirror is an **IndexedDB draft** plus the existing
  in-memory `WebAssetStore` for asset bytes.
- Offline you keep editing a single **draft version**; on reconnect it is flushed
  as one real commit via REST.
- Honest limitation: full multi-commit offline *history* is not realistic on web
  — it is "one pending draft, synced on return", not an offline commit log. This
  is acceptable because the airplane scenario is a desktop/mobile install; web is
  the online-first surface.

### 8.3 What the SyncEngine guarantees

- **Never lose local work** (P2): the outbox is durable (on disk / IndexedDB) and
  survives restart.
- **At-most-one authority per deck tab** for pushes; a queued commit references
  the `baseSha` it was authored against.
- **Idempotent flush**: a commit that already landed (same tree, advanced ref) is
  detected and skipped rather than duplicated.

---

## 9. Mapping the existing features onto git

### 9.1 Saving → commit + push

`DeckNotifier.save()` writes the deck's `{path: bytes}` set (from
`buildPackageMembers`, re-pathed into the §6 layout, assets replaced by `repo:`
pointers) to the `LocalMirror`, then enqueues a commit. Message defaults to a
concise auto-message (`Update <deck title>`), editable. Push is the SyncEngine
draining the outbox — from the user's point of view, **save = commit + push**.

### 9.2 Opening / loading

`listTree` the deck dir → `readBlob` `deck.md` and sidecars → resolve `repo:`
assets from the pool (fetch blobs lazily, cache in `AssetPool`/`WebAssetStore`) →
**run the import gate** (`MarkdownSafetyScanner`) on the `.md` bytes → parse via
`markdown_service.parseDeck` → `openDeckFromBytes`-style placement into a tab with
a `GitOrigin` attached.

### 9.3 Searching (text) and searching images

- **Within the current deck**: unchanged (`DeckNotifier.countMatches`).
- **Cross-deck / image search over the repo**:
  - prefer **server-side search** where the provider offers it (Gitea, GitHub and
    GitLab all expose code/repository search endpoints) — cheap, no bulk download;
  - fall back to a **local index** built from `listTree` + lazily fetched blobs,
    cached, refreshed on branch change. Image search enumerates `assets/*` and the
    `repo:` references that point at them (so "which decks use this image" is a
    reverse-index over the pool — a natural by-product of §6).

### 9.4 Releasing → branch → pull request → merge

- Author on a working branch (per deck or per session — OQ-3).
- **Release** = `openPullRequest(head: workBranch, base: defaultBranch, …)`,
  **gated by the classification/TLP policy** (`ExportService` enforcement) —
  fail-closed *before* the PR is created (P8).
- Optional `mergePullRequest` with the chosen merge method once approved. Branch
  protection / required reviews are the forge's job, not OciDeck's.

### 9.5 Versions & branches

History and branch lists come from `history()` / `listBranches()`. The UI gets a
branch picker and a per-deck commit timeline (reusing the `history(ref, deckDir)`
call). No local plumbing required for the online path.

---

## 10. Security

- **Auth**: a **Personal Access Token** per repo, stored in `secret_store`
  (`flutter_secure_storage` / OS keychain), keyed by `baseUrl`+`owner` — the same
  pattern as WebDAV passwords and the project's own Forgejo admin token. Never in
  settings/prefs. (OAuth device-flow is a later nicety — OQ-2.)
- **SSRF / self-hosted Forgejo**: reuse `NetGuard.safeResolveTrusted` with the
  `trustedInternal` opt-in and socket pinning against DNS-rebind, exactly as
  `webdav_service.dart` does. HTTPS enforced unless the user has explicitly marked
  the server trusted-internal.
- **Import gate on every inbound `.md`** (P5), fail-closed. A repo is untrusted
  input.
- **Path-traversal guards** on tree entries and on `repo:` resolution — reject any
  entry that escapes the repo root / the `assets/` pool (zip-slip-equivalent for
  trees).
- **Caps**: reuse the package limits (max bytes per blob, max entries per tree
  listing) against oversize/zip-bomb-equivalent responses.
- **Token scope guidance** in the UI: recommend a least-privilege PAT scoped to
  the single repo where the provider supports it (GitHub fine-grained tokens,
  GitLab project access tokens, Gitea scoped tokens).

## 11. Web specifics

- **CORS**: GitHub and GitLab APIs send CORS headers for token auth; a
  self-hosted Forgejo may not. Reuse/extend the existing same-origin
  `/fetch-proxy` (`lib/services/parts/file_service_net.dart`) for those origins,
  or document the required CORS configuration. (Memory: URL-import failures on web
  are usually CORS.)
- **No SSRF pinning on web** — the browser sandbox handles it; `NetGuard`'s
  network checks are a no-op there, as they already are for media URLs.
- Offline degrades to the §8.2 draft model.

---

## 12. Phased roadmap

Each phase is shippable and preserves the invariants.

### Phase 0 — Foundation (provider-agnostic, read-only)
- `GitForge` interface, `GitRepoConfig`/`GitOrigin` models, PAT storage in
  `secret_store`, HTTP client reusing `NetGuard` + HTTPS/caps.
- `GiteaForge` first (targets the project's own Forgejo).
- **Open a deck read-only** from a repo through the import gate. No writing yet.
- Tests: interface contract tests + a fake in-memory forge.

### Phase 1 — Asset pool + local mirror
- `AssetPool` (SHA-256, `repo:` scheme, resolve on desktop + web), `repo:`
  round-trip in `markdown_service`, reverse-index for image search.
- `LocalMirror` (on-disk desktop / IndexedDB web) as the editing target.

### Phase 2 — Writing (commit + push, offline)
- `commitFiles` in `GiteaForge` (multi-file), the `SyncEngine` + durable outbox,
  `baseSha` conflict detection.
- "Save to git" beside "Save to Nextcloud"; offline queue + flush-on-reconnect.

### Phase 3 — Branches, PR & merge (release), gated
- `createBranch`, `history`, `openPullRequest`, `mergePullRequest`.
- Wire release to the classification/TLP gate (fail-closed). Branch picker +
  commit timeline UI.

### Phase 4 — GitHub & GitLab adapters
- Implement `GitHubForge` (Git Data API multi-file) and `GitLabForge`
  (`actions[]`). The interface and everything above are already exercised by
  `GiteaForge`, so this is adapter work only.

### Phase 5 — Cross-deck search & polish
- Server-side code/image search per provider with the local-index fallback;
  manual asset GC; token-scope guidance UI.

### Coverage against the requirements
| Requirement | Delivered by |
|---|---|
| Saving = commit + push | Phase 2 |
| Opening / loading | Phase 0 |
| Text search | Phase 5 (within-deck already works) |
| Image search + dedup | Phase 1 (pool) + Phase 5 (search) |
| Release = PR + merge | Phase 3 |
| Offline (airplane) | Phase 2 (mirror + outbox) |
| Forgejo / GitHub / GitLab | Phase 0/2/3 (Forgejo) → Phase 4 (the others) |

---

## 13. Implementation reference (paths & integration points)

New:
- `lib/services/git/git_forge.dart` — interface + shared value types.
- `lib/services/git/gitea_forge.dart`, `github_forge.dart`, `gitlab_forge.dart`.
- `lib/services/git/sync_engine.dart`, `lib/services/git/local_mirror.dart`.
- `lib/services/git/asset_pool.dart` (or fold into an existing asset service).
- `lib/models/git_settings.dart` — `GitRepoConfig`, `GitOrigin`, `GitProvider`.
- `lib/state/git_provider.dart` — `gitForgeProvider`, family providers for
  tree/history (mirrors `lib/state/webdav_provider.dart`).

Touch points (integrate, don't fork):
- `lib/services/parts/file_service_package.dart` — reuse `buildPackageMembers`;
  add a re-path step to the §6 layout + `repo:` asset substitution.
- `lib/services/markdown_service.dart` — `repo:` scheme round-trip.
- `lib/utils/project_path.dart` — repo-root resolution for `repo:` (with guard).
- `lib/services/image_dedup_service.dart` — SHA-256 hashing for pool names.
- `lib/state/deck_provider.dart` — `save()`/open routed via `LocalMirror`.
- `lib/state/tabs_provider.dart` — `GitOrigin` on `TabInfo`; open-from-git path.
- `lib/models/webdav_settings.dart` — `GitOrigin` mirrors `WebdavOrigin`.
- `lib/widgets/app_shell.dart` — per-tab provider overrides already support this.
- `lib/services/export_service.dart` — reuse the classification gate for PR open.
- `lib/utils/net_guard.dart`, `lib/services/secret_store.dart` — reused as-is.

Docs to update when it lands: `ARCHITECTURE.md`, `SOURCE_MAP.md`,
`FILE_FORMAT.md` (the repo layout + `repo:` scheme), `USER_GUIDE.md`,
`CHANGELOG.md`.

---

## 14. Open questions (decide before/while implementing)

- **OQ-1 — Hash algorithm & pool naming.** SHA-256 recommended for pool
  filenames; keep the existing md5 for the in-session dedup UI, or migrate that
  too? (Leaning: SHA-256 for the pool, md5 stays for the ephemeral UI.)
- **OQ-2 — Auth.** PAT for v1 (decided). Add OAuth device-flow later per provider?
- **OQ-3 — Branch strategy.** One long-lived work branch per deck, or a fresh
  branch per editing session/release? Affects how "release" picks `head`.
- **OQ-4 — Native git on desktop.** Add a real-git `LocalMirror` (via `git` CLI
  where present, or a Dart git lib) for genuine offline commit history, behind the
  same interface — or keep the REST-outbox model everywhere for uniformity?
- **OQ-5 — Large media / LFS.** Videos can be large. Do we cap asset size, warn,
  or integrate Git-LFS (provider-dependent) in a later phase?
- **OQ-6 — Multiple decks per repo vs one repo per deck.** The §6 layout assumes a
  repo holds many decks (best for asset sharing). Do we also support pointing at a
  repo whose root *is* a single deck?
- **OQ-7 — Sidecar conflicts.** `.annotations`/`.notes` merge poorly. On a
  non-fast-forward, do we prefer local, prefer remote, or force a manual resolve
  for sidecars specifically?

---

## 15. Summary

Store decks in a git repo by treating the **forge as a versioned network deck
source** — the WebDAV pattern plus commit/branch/PR semantics — reached through a
provider-agnostic `GitForge` interface (Forgejo/Gitea first, then GitHub and
GitLab) over hardened HTTP. A deck is a **folder of real files** so history and
diffs mean something; assets live once in a **content-addressed shared pool**
(`repo:assets/<hash>`) so nothing is duplicated. Editing always targets a
**local mirror** and a **SyncEngine** reconciles it with the forge, so authoring
works offline and syncs later. Saving is a commit+push; releasing is a
classification-gated pull request and merge. Almost every dependency —
`buildPackageMembers`, `image_dedup_service`, `net_guard`, `secret_store`,
per-tab origins and provider scope — already exists; the new code is the forge
clients and the sync engine.
