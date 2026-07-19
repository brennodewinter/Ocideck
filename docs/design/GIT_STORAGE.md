# OciDeck — Git-Repository Storage (Design)

> **Status: Phases 0 and 1 landed; the rest is still a design proposal.**
> Opening a deck read-only from a Forgejo/Gitea repository works today, pooled
> images and all — see [`../SOURCE_MAP.md`](../SOURCE_MAP.md) for what exists
> (`lib/services/git/`, `lib/state/git_provider.dart`,
> `lib/state/tabs_provider_git.dart`) and [`../USER_GUIDE.md`](../USER_GUIDE.md)
> for how to use it. Everything from Phase 2 on — writing, native git, releases —
> is still design. Each phase folds its part into the current-state docs as it
> lands.
>
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
> co-authoring). The two are complementary and split along a clean seam:
> **git is asynchronous collaboration** (clone, branch, review, merge, release),
> **Matrix is synchronous collaboration** (live co-editing and presenting in one
> session). A room is a disposable sync channel; a git repo is durable versioned
> storage. Both share the principle *file = truth*.

---

## 1. Purpose & scope

OciDeck should be able to store decks in a **`.git` repository** in addition to
the existing backends (local files, `.ocideck` packages, WebDAV/Nextcloud). This
turns storage into **versioned storage**: every save is a commit, history and
branches become first-class, *releasing* a presentation is a reviewed pull
request plus a tag, and multiple authors can work on the same deck
asynchronously.

The full existing feature set must keep working against this backend:

- **saving** a deck (→ commit, pushed when there is connectivity),
- **opening / loading** a deck,
- **searching** decks (text) and **searching images**,
- **assets** (images, video) — with *deduplication* as an explicit goal, see §6,
- **offline authoring** — you must be able to write a presentation on a plane
  with no network and sync later (see §8),

and the backend adds three genuinely new capabilities:

- **versions of the same presentation** — `v1.0` and `v2.0` of one deck coexist
  and are both retrievable, as annotated **tags** (§9.4),
- **release as review** — a pull request against the default branch, gated by the
  existing classification/TLP policy (§9.4),
- **asynchronous collaboration** — clone, branch, review, merge (§9.6).

Three hosting providers are in scope, in this order of priority:

1. **Forgejo** (and Gitea, its upstream — same REST surface),
2. **GitHub**,
3. **GitLab**.

### Non-goals (v1)

- Not a general-purpose git client. OciDeck exposes the operations a deck author
  needs (commit, branch, merge, tag, PR); it is not a rebase/cherry-pick UI.
- OciDeck operates **no** server of its own. The user points at *their* forge,
  exactly as the WebDAV source lets them point at *their* storage.
- OciDeck **bundles no git binary and links no git library** — see the decision
  in §4.3. Native git is used *if present*, never shipped.
- No Git-LFS in v1 (§14, D5).

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
  and byte/entry caps apply. A forge is not more trusted than WebDAV. **Native
  git does not change this** — a clone is an import, not a blessing.
- **P6 — Provider-agnostic core.** All save/open/search/release logic is written
  against a thin `GitForge` interface. Forgejo/Gitea, GitHub and GitLab are
  implementations behind it. No provider-specific code leaks into the editor or
  state layer.
- **P7 — Reuse, don't re-derive.** The deck→`{path: bytes}` mapping
  (`buildPackageMembers`), image hashing (`image_dedup_service`), SSRF hardening
  (`net_guard`), secret storage (`secret_store`), per-tab origin tracking
  (`WebdavOrigin` → `GitOrigin`), per-tab provider scope and the capability
  pattern in `lib/platform/` already exist. The git backend is assembled from
  them, not built beside them.
- **P8 — Release is gated.** Opening a release PR **and creating a release tag**
  are subject to the existing classification/TLP enforcement
  (`ExportService.export()` policy), fail-closed. You cannot push a deck past its
  allowed classification ceiling by routing it through git.
- **P9 — Native git is an enhancement, never a requirement.** Every feature has a
  defined behaviour when `git` is absent (§4.2). The app must never dead-end
  because a user has no git installed, and must never bundle one to avoid the
  question (§4.3).

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
| **Platform capability with real stubs** | conditional import + `impl.*` getters | `lib/platform/platform_features.dart` |
| **A network deck source that web deliberately does not get** | `supportsNetworkDeckSources == false` on web | `lib/platform/platform_features_web.dart` |

The last two rows matter for §4. The codebase already models "this platform can
do less, and that is a designed answer, not a bug" — and it already has one
network deck source (WebDAV) that is switched **off** on web, for SSRF and CORS
reasons spelled out in `platform_features.dart:23-31`. Git storage takes a
different route (it *is* offered on web, §11), and the doc owes an explicit
reason why; see §4.4.

The genuinely new things are a **`GitForge` REST client** per provider, a
**`DeckMirror`** with two implementations, and a **`SyncEngine`**. Everything
else is wiring.

---

## 4. Key decision: two data planes, one forge plane

### 4.1 The split

Talking to a git host is two unrelated problems, and conflating them is what
makes this design look harder than it is.

- **The data plane** moves commits, trees and blobs: `clone`, `fetch`, `push`,
  `commit`, `merge`, `tag`, `log`. This is git proper.
- **The forge plane** is everything git has no concept of: pull requests,
  reviews, merge buttons, repo discovery, server-side code search. This is
  **always provider-specific REST**, on every platform, no matter how the data
  plane works. A pull request cannot be expressed in the wire protocol.

So the forge plane is settled: `GitForge` over hardened HTTP with a PAT (§7).
The only real question is the data plane.

### 4.2 The data plane: native where possible, REST otherwise

| | `git` present (desktop) | no `git`, or web |
|---|---|---|
| Save | real local commit, offline | draft + outbox, commit synthesised via REST |
| Offline history | **many real commits** | one pending draft |
| Merge | real `git merge`, conflict resolution | non-fast-forward → reload |
| Tag | real annotated tag, offline | tag via REST |
| Cross-deck search | local, cheap, over a full clone | REST search + lazy index |
| Pull request | REST | REST |

**Both columns ship.** The REST data plane is not a consolation prize — web needs
it regardless, so it gets built either way. That is the decisive point: because
the REST path exists anyway, **native git costs nothing to make optional**.
"No git installed" is not a dead end, it is a degradation to the path the web
build uses full-time (P9).

What native git buys, and why it is worth having as the preferred path:

- **True offline history.** The REST plane can only ever flush *one* commit's
  worth of work per reconnect, because it has nowhere to record intermediate
  states. Native git gives the airplane scenario what it actually wants: a dozen
  real commits, pushed as a dozen commits.
- **Real merges.** The REST plane's answer to a concurrent edit is "someone else
  moved the ref, reload". Native git can actually merge, and can present a
  conflict for resolution.
- **Cheap local reads.** Cross-deck and image search over a clone is a filesystem
  walk, not N REST round-trips.
- **Interoperability.** The repo is a plain git repo. Any other tool — a CI job
  rendering decks, `git blame`, a reviewer's own client — reads it without
  OciDeck. That is the whole point of choosing git over a bespoke store.

### 4.3 How native git is obtained: the `git` CLI, not a bundled library

**Decision: invoke the user's `git` binary as a subprocess. Bundle nothing.**

The obvious alternative — bundle libgit2 and bind it via `dart:ffi` — was
investigated and rejected. The reasons are ordered by how decisive they are.

1. **It collides head-on with this project's licence policy.**
   [`LICENSE_COMPLIANCE.md`](../LICENSE_COMPLIANCE.md) states that accepted
   licence families are MIT, BSD, Apache-2.0, MPL-2.0, ISC, Zlib, BSL-1.0,
   Unlicense, OFL-1.1 and CC0, and that *"anything else — in particular
   GPL/AGPL/LGPL — is flagged for review before it can be added"*. libgit2 is
   GPLv2-with-linking-exception. The exception genuinely permits linking from
   EUPL-1.2 code without copyleft reaching OciDeck, and EUPL-1.2 is
   GPLv2-compatible besides — so this is **not a legal problem**. It is a policy
   and tooling problem: `tool/license_detect.dart` classifies any text containing
   "gnu general public" as `GPL`, with no notion of an exception, so `make
   licenses` — and therefore `make check-full` and CI — would fail. Adopting
   libgit2 means consciously amending the policy *and* teaching the classifier
   about linking exceptions. That is a real decision with a real cost, taken for
   a dependency we do not need.
2. **It would be the first native binary in the tree.** There is today no
   `dart:ffi`, no `Process.run`, and no bundled native library anywhere in
   `lib/`. Bundling libgit2 adds ~37 MB of prebuilt binaries, an SBOM entry per
   platform, and a build story per platform — permanently.
3. **The available binding is not solid enough to bet on.** `libgit2dart` is
   discontinued and its repository was archived in February 2023. Its de-facto
   successor `git2dart` is actively maintained but has a bus factor of 1, ships a
   macOS dylib that is **arm64-only** (no Intel), ships a Linux `.so` whose
   `libssl.so.3`/`libssh2.so.1` dependencies are *not* bundled with it, and only
   stabilised its network transport in mid-2026. Certificate trust on desktop is
   the sharpest edge: OpenSSL is statically linked without SecureTransport, so
   verification falls back to a CA path baked in on the build machine.

The CLI's own cost is honest and bounded: `git` must be installed, and a
subprocess is a security surface. §10.2 hardens the subprocess. P9 and §4.2
handle the absence. Both are cheaper than the three problems above.

**libgit2 remains the documented escape hatch.** If telemetry-free reality shows
that too many users lack git, it can be adopted later *behind the same
`DeckMirror` interface* (§8.1) — a dependency swap, not a redesign. That is
precisely why the interface exists.

### 4.4 Why not the wire protocol in Dart, and why web still gets git

Re-implementing git's smart-HTTP protocol (packfile negotiation, ref discovery)
in pure Dart would give a uniform data plane on all six platforms. It is
rejected: it is by far the most work, it hits CORS against self-hosted Forgejo
anyway, and the surveyed pure-Dart implementations (`dart_git` and relatives)
implement packfile *parsing* only — none does network git at all.

That leaves the question §3 raises: WebDAV is switched **off** on web, so why is
git switched **on**? Because the two obstacles that stop WebDAV do not apply the
same way. WebDAV's client is `dart:io`-based with its own SSRF pinning that has
no browser equivalent, and WebDAV needs server-side CORS configuration that an
administrator must consciously make. The git forge plane is plain HTTPS+JSON that
the browser sandbox already contains, GitHub and GitLab send CORS headers for
token auth, and the self-hosted-Forgejo gap has an existing answer in the
same-origin `/fetch-proxy` (§11). Web git is therefore offered, with the honest
limitation that it is the REST data plane only (§8.3).

---

## 5. Architecture overview

Five layers. The editor and state layer never see anything below `DeckMirror`.

```
   ┌────────────────────────────────────────────────────────────┐
   │ Editor / state (deck_provider, tabs_provider)               │
   │   save() / open() / search — unchanged surface              │
   └───────────────┬────────────────────────────────────────────┘
                   │ writes/reads a deck as files
                   ▼
   ┌────────────────────────────────────────────────────────────┐
   │ DeckMirror (interface)  — the working copy, always available │
   │   NativeGitMirror   desktop + `git` on PATH → a real clone   │
   │   DraftMirror       web, or desktop without git → outbox     │
   └───────────────┬────────────────────────────────────────────┘
                   │ reconcile: push/pull, or drain the outbox
                   ▼
   ┌────────────────────────────────────────────────────────────┐
   │ SyncEngine         — reconciles mirror ↔ forge              │
   │   native: git push/fetch      REST: outbox, baseSha guard   │
   └───────┬─────────────────────────────────┬──────────────────┘
           │ data plane (native only)        │ forge plane (always)
           ▼                                 ▼
   ┌──────────────────────┐   ┌─────────────────────────────────┐
   │ GitCli               │   │ GitForge (interface)            │
   │  hardened Process.run │   │  tree · commit · branch · tag   │
   │  argv, clean env      │   │  pull request · search          │
   └───────┬──────────────┘   │  GiteaForge·GitHubForge·GitLab… │
           │                  └───────────────┬─────────────────┘
           │ https (git's own)                │ hardened HTTP (NetGuard, PAT)
           ▼                                  ▼
                     Forgejo / GitHub / GitLab
```

Cross-cutting: `AssetPool` (content-addressed dedup, §6) sits beside the mirror
and feeds both reads (resolve `repo:` references) and writes (add only new
blobs).

Note that `GitForge` is *not* bypassed on the native path. Native git replaces
the **data** plane only; pull requests, review and code search still go over
REST. A desktop user with git installed uses both planes at once.

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

**A repo is a trust boundary, and that is what decides its granularity.** Forge
access control is all-or-nothing: everyone who can read the repo reads *every*
deck in it. So a repo holds many decks — the asset pool needs that (P4) — but it
holds decks that **share an audience**: one repo per client, per engagement, or
per classification level. Do not put a TLP:RED pentest report and a public deck
in one repo and expect the forge to keep them apart. It cannot, and the shared
pool would straddle the boundary as well: an asset is reachable by anyone who can
read the repo, whatever the classification of the deck that introduced it.
OciDeck does not enforce this — the forge's permissions do (§14, D6).

Why this satisfies the goal:

- **Filename = content hash.** Two decks using the same image both reference
  `assets/<hash>.png`. Physically it exists once. This *enforces* de-duplication
  rather than hoping for it.
- **…and the hash is verified on read, not assumed.** A hash-named path proves
  nothing on its own: a forge is untrusted (P5) and can serve whatever it likes
  under `assets/<hash>.png`. Because pooled blobs are cached — and a
  content-addressed cache is naturally shared *across* repos, since the key is
  the content — an unverified read would let one hostile repository poison the
  bytes an honest one later gets. So `AssetPool` re-hashes every fetched blob
  and fails closed on a mismatch. Content-addressed storage that never checks
  the address is just a filename.
- **The hashing machinery exists.** `image_dedup_service.dart` already hashes
  images in an isolate (md5). Reuse it, but standardise the pool on **SHA-256**
  for collision resistance (md5 stays fine for the existing in-session dedup UI).
- **Git de-duplicates again, for free.** A git blob is itself content-addressed,
  so a repeated asset does not grow the pack/history either.
- **Commit only what is new.** Before committing, check the HEAD tree for
  `assets/<hash>`; if present, commit only the changed `deck.md`, not the asset.
  On the native path this is what git does anyway; on the REST path it is an
  explicit tree check that saves an upload.

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
  blob is fetched once; on a native clone it resolves to the on-disk pool file
  directly — no fetch at all.

### 6.2 Garbage collection (deliberately manual)

When no deck references an asset any more, its blob becomes an orphan in the
working tree. A **manual** "clean unused assets" sweep (scan every `deck.md`
across the repo, delete unreferenced `assets/*`) reclaims it. It is *not*
automatic: in a versioned store an asset unreferenced on `main` may still be used
by another branch, an older commit, **or a release tag** (§9.4), and silent
deletion would be wrong (P2 — never lose durable content without intent).

---

## 7. The forge abstraction

### 7.1 Interface

```dart
abstract class GitForge {
  // read
  Future<List<RepoEntry>> listTree(String ref, String path, {bool recursive});
  Future<Uint8List>       readBlob(String ref, String path);
  Future<String>          headSha(String branch);

  // write (REST data plane: save = commit + push in one server-side operation)
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

  // releases
  Future<void>          createTag(String name, String ref, String message);
  Future<List<TagRef>>  listTags();

  // review
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
`baseUrl` + `owner` (§10.1).

### 7.2 The multi-file commit primitive (where providers differ)

On the REST data plane, one save = one atomic commit of the changed file set.
This is the only place providers diverge materially; each adapter hides it behind
`commitFiles`:

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
as reload — the git equivalent of the WebDAV atomic-write guard. On the native
data plane this whole primitive is unused: `git push` performs the same check
server-side, and a rejection can be *merged* rather than reloaded (§8.2).

---

## 8. The mirror and the SyncEngine (offline authoring)

Requirement: author on a plane, sync later. The forge is therefore **never the
direct editing target**; a `DeckMirror` is, and the `SyncEngine` reconciles.

```
Editor ──writes──▶ DeckMirror ──SyncEngine──▶ forge (when connectivity returns)
                   (offline-capable)
```

### 8.1 `DeckMirror` — one interface, two implementations

```dart
abstract class DeckMirror {
  /// Write the deck's file set into the working copy. Always succeeds offline.
  Future<void> writeDeck(String deckDir, Map<String, List<int>> files);

  /// Record a durable local checkpoint. Real commit natively; queued otherwise.
  Future<void> checkpoint(String deckDir, String message);

  /// Reconcile with the forge. Push/pull natively; drain the outbox otherwise.
  Future<SyncResult> sync();

  Future<List<CommitInfo>> history(String deckDir);
  Future<void> tagRelease(String name, String message);

  /// False for DraftMirror: callers must not promise multi-commit offline history.
  bool get hasRealHistory;
}
```

`hasRealHistory` is the honest seam. UI that offers "commit" as a distinct act
from "save" is only shown when it is true; otherwise the user sees a single
"save, syncs when online". Never present a queued draft as if it were history.

### 8.2 `NativeGitMirror` — desktop with `git` on PATH

- The mirror is a **real clone** under the app-support path. The working tree is
  exactly the repo layout of §6, because it *is* the repo.
- Cloned with `--filter=blob:none` — a **partial clone**, so blobs are fetched
  only when a deck actually needs them. This matters because a full clone would
  otherwise pull every video in the repo's entire history to open one deck: 4 GB
  of media would cost 4 GB to open a text file. With the filter, opening costs
  megabytes and blobs arrive on demand, which is the same lazy-fetch shape the
  REST plane already has. Requires git ≥2.19 and forge support — Forgejo, GitHub
  and GitLab all have it (§14, D5).
- Saving writes files locally and immediately (as desktop already works — a real
  `filePath`), then `git add` + `git commit`. Offline, this is a complete,
  durable, real commit. Ten commits on a plane stay ten commits.
- `sync()` is `git fetch` then `git push`. A rejected push means the branch moved;
  the user is offered a **real merge**, with conflicts surfaced per file.
- `tagRelease()` is `git tag -a`, offline-capable, pushed on the next sync.
- `history()` is `git log -- <deckDir>` — local, instant, no REST.

### 8.3 `DraftMirror` — web, or desktop without git

- No local git. On desktop without git the mirror is a plain directory plus an
  on-disk outbox. On web there is no filesystem either — but note what actually
  needs storing before reaching for a mechanism.
- **A deck's working copy is text, all of it.** `deck.md` is markdown;
  `AnnotationCodec.encode` and `UserNotesCodec.encode` both return a `String`
  (JSON). There is no binary member. So the web draft is **a handful of strings
  in the browser's key/value store** (`shared_preferences`, already a dependency,
  already mocked in ~50 test files) — not IndexedDB.
  An earlier version of this document specified an IndexedDB draft. That was
  pattern-matching "durable storage on the web" onto the heaviest available
  mechanism without asking what the payload is: a binary object database to hold
  markdown. It also had a cost that only showed up when building — this repository
  runs every test on the Dart VM and has no browser target, so the interop would
  have been the one untested piece of the backend. A text store has no such
  problem, because the repo already tests one.
- **Asset bytes are not the draft's problem.** A pooled asset is content-addressed
  and lives on the forge; a *new*, not-yet-pushed image lives in the existing
  in-memory `WebAssetStore`, which is already explicitly ephemeral (its own doc:
  a saved `.md` with `mem:` references loses its images on reload). The git draft
  inherits that limitation rather than adding one — and still improves on today,
  where nothing survives a reload at all.
- **The one real constraint**: the browser store is roughly 5 MB per origin, while
  `FileService.maxDeckMarkdownBytes` is 32 MiB. That ceiling is a hostile-input
  guard, not a realistic deck size, so the answer is a cap with an honest message
  when a deck genuinely will not fit — not an object database bought to cover a
  case that does not occur.
- Saving updates the draft and enqueues a **pending commit** carrying the
  `baseSha` it was authored against.
- `sync()` drains the outbox via `GitForge.commitFiles` once a
  connectivity/`NetGuard` check passes.
- Offline you keep editing a single **draft version**; on reconnect it is flushed
  as one real commit. Honest limitation: this is "one pending draft, synced on
  return", **not** an offline commit log — hence `hasRealHistory == false`. This
  is acceptable because the airplane scenario is a desktop install, which is
  exactly where native git is available.
- Conflict on flush → `baseSha` mismatch → present reload. No merge is possible
  here; that asymmetry is the main functional reason to prefer §8.2.

### 8.4 Capability detection (and the macOS trap)

`supportsNativeGit` cannot be a compile-time constant like its neighbours in
`lib/platform/platform_features.dart`, because it depends on the user's machine,
not the build. It is a **runtime probe**, cached for the process lifetime, and
therefore belongs in a provider (`gitCapabilityProvider`) rather than a getter:

- probe `git --version` with `Process.run` and require a **minimum version**, so
  that plumbing behaviour cannot drift under us and so that `--filter=blob:none`
  (§8.2) is actually available. Below that version the native plane is refused
  **wholesale** and the repo falls back to REST — never feature-by-feature, which
  would multiply into a test matrix nobody can hold (§14, D8),
- `kIsWeb` short-circuits to `false` before any `dart:io` access — the ordering
  gotcha already documented at `lib/services/open_file_channel.dart:22`
  (`Platform.isMacOS` is a throwing stub on web).

**The macOS trap, which must not be got wrong:** on a Mac without Xcode Command
Line Tools, `/usr/bin/git` is a *shim*. Running it does not fail — it **pops a
system GUI dialog** offering to install the tools. A naive probe at startup would
therefore ambush a user who has never touched git with an OS install prompt they
did not ask for. Mitigations, both required:

1. Never probe eagerly at startup. Probe **lazily**, the first time the user
   actually configures or opens a git repo.
2. On macOS, check `xcode-select -p` (exit code 0 = tools present) *before*
   invoking `git`, so the shim is never triggered by us.

### 8.5 What the SyncEngine guarantees

- **Never lose local work** (P2): a native commit is durable by construction; the
  outbox is durable (on disk on desktop, the browser key/value store on web —
  see §8.3 on why that suffices) and survives restart.
- **At-most-one authority per deck tab** for pushes; a queued commit references
  the `baseSha` it was authored against.
- **Idempotent flush**: a commit that already landed (same tree, advanced ref) is
  detected and skipped rather than duplicated.

---

## 9. Mapping the existing features onto git

### 9.1 Saving → commit (+ push)

`DeckNotifier.save()` writes the deck's `{path: bytes}` set (from
`buildPackageMembers`, re-pathed into the §6 layout, assets replaced by `repo:`
pointers) to the `DeckMirror`, then checkpoints it. Message defaults to a concise
auto-message (`Update <deck title>`), editable. Push is the SyncEngine — from the
user's point of view, **save = commit, and it reaches the forge when the network
does**.

### 9.2 Opening / loading

Native: clone or fetch, then read from the working tree. REST: `listTree` the
deck dir → `readBlob` `deck.md` and sidecars → resolve `repo:` assets from the
pool (fetch blobs lazily, cache in `AssetPool`/`WebAssetStore`). Both paths then
converge: **run the import gate** (`MarkdownSafetyScanner`) on the `.md` bytes
(P5) → parse via `markdown_service.parseDeck` → `openDeckFromBytes`-style
placement into a tab with a `GitOrigin` attached.

### 9.3 Searching (text) and searching images

- **Within the current deck**: unchanged (`DeckNotifier.countMatches`).
- **Cross-deck / image search over the repo**:
  - with a native clone, search the working tree directly — a filesystem walk,
    no network, and `git grep` is available for text;
  - otherwise prefer **server-side search** where the provider offers it (Gitea,
    GitHub and GitLab all expose code/repository search endpoints);
  - fall back to a **local index** built from `listTree` + lazily fetched blobs,
    cached, refreshed on branch change.
  - Image search enumerates `assets/*` and the `repo:` references that point at
    them (so "which decks use this image" is a reverse-index over the pool — a
    natural by-product of §6).

### 9.4 Releasing → PR to merge, tag to release

Release is **two acts, both gated** (P8), and the distinction is the point:

1. **Review** — author on a working branch, then
   `openPullRequest(head: workBranch, base: defaultBranch, …)`. Reviewers comment
   on a real diff of `deck.md`. Merge with `mergePullRequest` once approved.
   Branch protection and required reviews are the forge's job, not OciDeck's.
2. **Release** — an **annotated tag** on the merge commit marks the version that
   was actually presented. `v1.0` and `v2.0` of the same deck coexist and are
   both retrievable, which is what "releases van dezelfde presentatie" asks for.

Both are fail-closed against the classification/TLP policy (`ExportService`
enforcement), evaluated *before* the PR is opened and *before* the tag is
created. A tag is a durable, advertised pointer — it must not be able to publish
a deck past its classification ceiling any more than an export can.

**The branch is generated, not authored** (§14, D3). Each editing round starts a
fresh branch off current `main`, named
`decks/<naam>/<datum>` — so every release PR is a clean diff against an
up-to-date base, and there is no long-lived branch drifting away from `main` that
someone must remember to back-merge. The user never types a branch name and, in
the normal flow, never sees one: the UI speaks of a **concept** (the open branch)
and an **uitgebrachte versie** (the tag). Stale merged branches are the forge's
to prune, and the UI offers it after a merge.

**Tag names are deck-scoped** (§14, D9). A repo holds many decks (§6), so a flat
`v1.0` would be ambiguous; tags are `decks/<naam>/v1.0`. Git permits `/` in tag
names, the form groups readably in forge UIs, and tag-protection patterns like
`decks/*/v*` fall out naturally — which matters, because a release tag is gated
under P8 and therefore deserves protecting. Git's D/F conflict (a ref `a/b`
cannot coexist with a ref `a`) does not bite here: `decks/<naam>` is itself never
a tag.

The UI surfaces tags as a **version picker**: open `v1.0` of a deck read-only,
diff it against `v2.0`, or branch a new revision from it.

### 9.5 Versions & branches

History and branch lists come from `DeckMirror.history()` / `listBranches()` —
`git log` on a clone, REST otherwise. The UI gets a branch picker, a per-deck
commit timeline, and the tag-based version picker of §9.4.

### 9.6 Asynchronous collaboration

This falls out of the design rather than being built: a repo is shared, so two
authors clone it, work on branches, and review each other's decks as pull
requests. What OciDeck must add is small but real:

- **Attribution** — commits carry an author identity. OciDeck needs a name/email
  setting per repo (it must not silently reuse a global `user.name` it did not
  set, nor invent one).
- **Signing** — **SSH commit signing, optional, native plane only** (§14, D11).
  SSH is chosen over GPG deliberately: a key plus an `allowed_signers` file, no
  keyring to manage. It is *optional* because of an asymmetry that cannot be
  engineered away: on the REST plane the forge builds the commit server-side, so
  there is nothing client-side to sign with. Presenting signing as a property of
  "a deck in git" would therefore be a lie on web. It is a property of a commit
  made on a machine that has your key, and the UI must say exactly that — a
  signed-commit badge on the history entry, never a claim about the deck.
- **Awareness** — show that `main` has moved, and whose branch is open, from
  `listBranches`/`fetch`. Not presence, just freshness.
- **Sidecar conflicts** — `.notes` merges as text; `.annotations` unions (§14,
  D7). See §9.7.

The boundary with [`COLLABORATION.md`](COLLABORATION.md) is deliberate and should
stay crisp: **git is for authors who are not in the room at the same time**;
Matrix is for those who are. Git has no opinion on live cursors; the Matrix room
has no opinion on last year's version. A future session may combine them (a room
whose participants share a repo), but neither doc depends on the other landing.

### 9.7 Sidecar merge semantics

"Sidecars merge poorly" flattened a distinction worth keeping: the two sidecars
are not the same kind of file, and each has its own right answer (§14, D7).

- **`.notes` — speaker notes are text.** Git's ordinary text merge applies. No
  special case, no custom driver. Two authors editing different slides' notes
  merge cleanly, and a genuine same-line collision produces a conflict a human
  can actually read and resolve.
- **`.annotations` — ink strokes are additive.** Two people who drew on the same
  slide did not disagree; they both drew. The merge is a **union of the stroke
  sets**, keyed per slide and deduplicated by stroke identity. That is
  semantically right rather than merely convenient: no ink is lost and there is
  nothing for the user to arbitrate. It requires the annotation format to carry a
  stable per-stroke identity — check this when wiring it up, and add one if it is
  missing (`FILE_FORMAT.md`).

On the native plane this is a **git merge driver** (`merge=ocideck-ink` in
`.gitattributes`, registered in the clone's own config — never the user's global
config, per §10.2), so `git merge` resolves it without OciDeck mediating. Two
consequences must be respected rather than discovered later:

- **A clone made by another tool has no driver.** The union must therefore also
  be reproducible in-app, for when git hands back a file it could not merge.
- **Union has one real failure mode: erasure.** If one side deletes a stroke and
  the other keeps it, the union resolves to "kept" — the erase silently loses.
  For ink that is usually the safe direction (P2: never lose content without
  intent), but it *is* a semantic loss and it must be a conscious one. If erasure
  needs to survive a merge, model it as a tombstone rather than an absence. Decide
  this when the annotation format is pinned down; the choice belongs to that
  format, not to this document.

---

## 10. Security

### 10.1 Network, auth and untrusted content

- **Auth**: a **Personal Access Token** per repo, stored in `secret_store`
  (`flutter_secure_storage` / OS keychain), keyed by `baseUrl`+`owner` — the same
  pattern as WebDAV passwords. Never in settings/prefs. (OAuth device-flow is a
  later nicety — D2.)
- **SSRF / self-hosted Forgejo**: on the REST plane, reuse
  `NetGuard.safeResolveTrusted` with the `trustedInternal` opt-in and socket
  pinning against DNS-rebind, exactly as `webdav_service.dart` does. HTTPS
  enforced unless the user has explicitly marked the server trusted-internal.
  **Note the honest gap:** the native plane's HTTPS is git's own, so `NetGuard`
  cannot pin it. The trusted-internal opt-in therefore governs *whether the
  origin may be used at all*, and the origin is validated before it is ever
  handed to `git`.
- **Import gate on every inbound `.md`** (P5), fail-closed, on both planes. A repo
  is untrusted input; cloning it does not make it trusted.
- **Path-traversal guards** on tree entries and on `repo:` resolution — reject any
  entry that escapes the repo root / the `assets/` pool (zip-slip-equivalent for
  trees).
- **Caps**: reuse the package limits (max bytes per blob, max entries per tree
  listing) against oversize/zip-bomb-equivalent responses. On a clone, cap by
  repo size before fetching.
- **Token scope guidance** in the UI: recommend a least-privilege PAT scoped to
  the single repo where the provider supports it (GitHub fine-grained tokens,
  GitLab project access tokens, Gitea scoped tokens).

### 10.2 Subprocess hardening (the native plane)

This is new surface for this codebase — `lib/` contains no `Process.` call today
— so the rules are explicit. All of it lives in one place, `lib/services/git/
git_cli.dart`, and nothing else in the tree may spawn a process.

- **argv array, never a shell.** `Process.run('git', [...], runInShell: false)`.
  No string interpolation into a command line, ever.
- **User data is an operand, never an option.** Branch names, tags, messages and
  paths are attacker-influencable (they can come from a repo). Pass them after
  `--end-of-options` where git supports it, reject any value starting with `-`,
  and validate refs against `git check-ref-format` rules before use.
- **Never put the PAT in the remote URL.** It would land in `.git/config` in
  plaintext and in the reflog. **Never pass it in argv either** — process
  arguments are world-readable via `ps` on Linux and macOS. Supply it through the
  child's environment (`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n`
  with `http.extraHeader`), which is not exposed in `ps` to other users, and
  never persist it to disk. See §14, OQ-10 — this deserves a second look during
  implementation.
- **A clean, closed environment.** `GIT_TERMINAL_PROMPT=0` so git can never block
  forever waiting for a credential prompt that has no terminal to appear on.
  `GIT_CONFIG_NOSYSTEM=1` and a controlled `HOME` so the user's global gitconfig
  cannot change our behaviour — aliases, `core.fsmonitor` and `core.pager` are all
  code-execution or hang vectors we do not want inherited.
- **No hooks.** Point `core.hooksPath` at an empty directory for every invocation.
  Hooks are not cloned, but this closes the door rather than trusting that.
- **Timeouts and bounded output.** Every invocation has a deadline and a cap on
  captured stdout/stderr; a wedged `git` must not wedge the app.
- **Never construct a repo path from untrusted input.** The clone location is
  derived from the config, under app-support, and is validated to stay there.

---

## 11. Web specifics

- Web is the **REST data plane only** (§8.3). `supportsNativeGit` is `false`.
- **CORS**: GitHub and GitLab APIs send CORS headers for token auth; a
  self-hosted Forgejo may not. Reuse/extend the existing same-origin
  `/fetch-proxy` (`lib/services/parts/file_service_net.dart`) for those origins,
  or document the required CORS configuration. (URL-import failures on web are
  usually CORS.)
- **The proxy is for public repositories only — a request carrying a token never
  goes through it.** The fetch-proxy fetches server-side, so it would receive the
  PAT and forward it on the user's behalf. That directly contradicts §10.1 ("the
  token lives in the keychain, nowhere else"): it would put the secret in a
  second place, on a host the user did not authenticate to. So the fallback
  applies only when the request carries no credential; with a token, the honest
  answer is to tell the user CORS must be configured on the forge. This is a
  Phase 0 finding, not part of the original design — the transport enforces it
  (`git_transport_web.dart`) and a test pins it.
- **No SSRF pinning on web** — the browser sandbox handles it; `NetGuard`'s
  network checks are a no-op there, as they already are for media URLs.
- Offline degrades to the §8.3 draft model.
- The **CSP is a hard constraint**, not an afterthought: `web/index.html` ships a
  strict policy and CI enforces it (`make check-web`). Any forge origin the app
  must reach has to fit `connect-src`, or go through the proxy. This is a design
  input for Phase 0, not a Phase 5 surprise.

---

## 12. Phased roadmap

Each phase is shippable and preserves the invariants.

> **A phase must land with its caller, not before it.** The original roadmap was
> written machinery-first — Phase 1 builds the mirror, Phase 2 uses it; Phase 1
> builds the reverse index, Phase 6 uses it. That cannot land here:
> `make check-dead-code` refuses any `lib/` file unreachable from an entrypoint,
> and it is right to. Discovered twice, in Phase 0 and Phase 1, so the phases
> below have been re-cut around it: each one now carries the wiring that makes
> its own machinery reachable. Where that forced a move, the entry says so.
> Do not answer this by allowlisting — the allowlist is for deliberate dynamic
> entrypoints, and code with no caller is a different thing wearing the same
> clothes.

### Phase 0 — Foundation (provider-agnostic, read-only, REST)
- `GitForge` interface, `GitRepoConfig`/`GitOrigin` models, PAT storage in
  `secret_store`, HTTP client reusing `NetGuard` + HTTPS/caps.
- `GiteaForge` first (targets the project's own Forgejo).
- **Open a deck read-only** from a repo through the import gate. No writing yet.
- Tests: interface contract tests + a fake in-memory forge.
- Deliberately REST-first: it is the path both platforms share, so it de-risks
  the interface before a second implementation exists.

### Phase 1 — The asset pool, wired into opening
- The `repo:` scheme + its guard (`GitRepoLayout.assetRef` / `assetPathOf`).
  `markdown_service` needs **no** change: a path is opaque to it, so `repo:`
  already round-trips — pinned by a regression test rather than defended by code.
- `AssetPool`: SHA-256 naming, fetch-once cache, `existing()` for Phase 2's
  commit. **Every fetched blob is re-hashed** — see §6.
- Its caller, which is what makes the phase land: `openDeckFromGit` resolves a
  deck's pooled images and rewrites the slide paths (§9.2). Before this, a deck
  from a repo opened with every picture broken.
- *Moved out:* the reverse index went to Phase 6 and `DeckMirror` to Phase 2 —
  each now sits with the caller that gives it a reason to exist.

### Phase 2 — Writing (commit + push, offline)
- `DeckMirror` interface + `DraftMirror` as the editing target (§8.1, §8.3) —
  moved here from Phase 1, because *this* is where it acquires a caller.
- `commitFiles` in `GiteaForge` (multi-file), the `SyncEngine` + durable outbox,
  `baseSha` conflict detection.
- "Save to git" beside "Save to Nextcloud"; offline queue + flush-on-reconnect.
- Web writes too: the draft is text, so it goes in the browser key/value store
  (§8.3). No browser test target needed — that requirement was an artefact of the
  IndexedDB choice, not of the web.
- At this point the feature is complete on every platform, on the REST plane.

### Phase 3 — Native git on desktop
- `GitCli` with the §10.2 hardening; `gitCapabilityProvider` with the lazy probe
  and the macOS `xcode-select` guard (§8.4).
- `NativeGitMirror implements DeckMirror` — partial clone (D5), commit, fetch,
  push, merge, log, tag. Real offline history; real merges.
- The `.annotations` union merge driver + `.gitattributes` in the clone (§9.7).
- **Prove OQ-10** (token delivery) on macOS, Windows and Linux before this phase
  is called done; §10.2 is provisional until then.
- Verify: same `DeckMirror` contract tests pass against both implementations.
  That equivalence is the phase's actual deliverable.

### Phase 4 — Releases: branches, PR, merge & tags (gated)
- `createBranch`, `history`, `openPullRequest`, `mergePullRequest`, `createTag`,
  `listTags`.
- Wire both PR-open and tag-create to the classification/TLP gate (fail-closed).
- Generated per-round branches (D3); tag names per D9.
- Branch picker, commit timeline, and the tag-based version picker.
- Per-repo author identity for attribution, and optional SSH commit signing on
  the native plane (D11).

### Phase 5 — GitHub & GitLab adapters — **done**
- `GitHubForge` and `GitLabForge` alongside `GiteaForge`, all four implementations
  (those three plus the reference `FakeForge`) driven through the *same* contract
  suite. That shared suite is the deliverable: it is what turns "the interface is
  provider-agnostic" from a claim into something that fails loudly when it stops
  being true. It caught two real bugs on first run.
- The roadmap called this "adapter work only". That undersold it, in one specific
  way: **the three forges disagree about how a multi-file commit works, and that
  is also where the concurrency guard lives.**
  - *Gitea* — one `POST /contents`, guarded by `last_commit_id`.
  - *GitHub* — no such endpoint. A commit is four round-trips through the Git
    Data API (blob → tree → commit → move the ref), and the guard is that the
    final ref update is non-forcing: it only succeeds as a fast-forward.
  - *GitLab* — one call again, but an `actions[]` list that must name `create`
    vs `update` vs `delete` per file, guarded by `start_sha`.
  Three shapes, one meaning. Each fake transport models its own guard for real,
  because a fake that always accepts a commit would let the conflict half of the
  contract pass without ever being exercised.
- Also unlike each other: auth headers (`token` / `Bearer` / `PRIVATE-TOKEN`),
  the API host (GitHub's differs from the web host), project addressing (GitLab
  uses one URL-encoded `owner/repo` segment), annotated tags (two calls on
  GitHub), branch pruning on merge (a flag on Gitea and GitLab, a separate
  `DELETE` on GitHub), and merge-request numbering (GitLab's per-project `iid`).
- One genuine capability gap, recorded rather than hidden: **GitLab's tree
  listing carries no file size.** Supplying it would cost a request per file, and
  no caller reads the field — so the contract takes a `reportsBlobSize` flag and
  asserts the absence explicitly, instead of a test that quietly passes either
  way.
- The native plane is untouched, as predicted: it never knew which forge it was
  talking to.
- **Not verified against a live github.com or gitlab.com.** Both adapters are
  built from documentation; Forgejo had a real server to check against. That is
  the largest remaining risk in this phase.

### Phase 6 — Cross-deck search & polish

**Shipped: `AssetIndex` and its viewer.** The reverse index over the pool moved
here from Phase 1 because this is where it finally has a caller. One pass over
the repo — every `deck.md`, then the pool — inverted into asset → users, behind
*Afbeeldingen in de repository…*.

- References are found by **scanning the raw markdown**, not by parsing it. A
  slide type the parser skips would otherwise hide a reference, and a missed
  reference marks an asset as unused. That error is the expensive one.
- **Release tags count as users.** An image pulled from the current text is
  usually still in the version presented last quarter, and that version has to
  keep rendering. So `unusedAssets()` always scans the tags too — never the
  cheaper branch-only pass. `build(includeReleases: false)` stays for image
  search, which does not need them and would pay a read per tag.
- The split the index has to keep: **image search may answer from an incomplete
  index; "nothing uses this" may not.** Whoever the search lists really is a
  user, so a deck that failed to read only shortens that answer. But an
  unreadable deck — or an unreadable release — could be the *one* user of an
  asset, and deleting is irreversible (P2). So an incomplete round makes
  `unusedAssets()` throw, and the viewer shows what could not be read instead of
  a candidate list.
- Even a complete list is a **proposal, not a verdict**: the round covers one
  branch, and another branch may still use what looks orphaned here. The viewer
  says so where the number is.
- **Deletion is not built.** The index names candidates; removing them is the
  irreversible half and is deliberately still §6.2's manual job.

**Shipped: cross-deck text search.** `DeckSearch` — the text twin of the asset
index, same one pass over the repo, behind *Zoeken in alle decks…*.

- **The opposite failure direction from the asset index, on purpose.** There the
  answer is "nothing uses this" and an irreversible deletion follows, so an
  unreadable deck makes it refuse. Here every hit shown is true whatever else
  failed to read, so a partial answer beats no answer — as long as the screen
  says which deck it could not read. Silently short is the bad outcome, not
  short.
- Hits are attributed to a **slide**, using the parser's own fence-aware
  `splitSlideBlocks`. A naive `split('---')` would treat a `---` inside a YAML
  or diff code block as a slide boundary and point the user at the wrong slide.
  The splitter, not the full parse: search has to work on a deck that does not
  currently parse.
- Truncation means **a real match went unreported** — not "the list happens to
  be full". A cap that quietly drops matches would make search lie by omission.
- Opening a hit goes through the **existing** open-from-git path (`_openFromGit`
  gained an optional `deckDir`), so it passes the same import gate and the same
  native/REST choice as the browser instead of growing a second open path.

**Open:** server-side search per provider (the forges can do this far cheaper
than N reads), native `git grep` on a clone, and token-scope guidance UI.

### Coverage against the requirements
| Requirement | Delivered by |
|---|---|
| Opening / loading | Phase 0 |
| Image dedup (shared pool) | Phase 1 |
| Saving = commit (+ push) | Phase 2 |
| Offline (one draft, any platform) | Phase 2 |
| Offline (real history, airplane) | Phase 3 |
| Real merges | Slide-level three-way merge, both planes |
| Release = reviewed PR | Phase 4 |
| Versions of one deck = tags | Phase 4 |
| Async collaboration | Phase 4 (falls out of PR + attribution) |
| Forgejo / GitHub / GitLab | All three, behind one `GitForge` (Phase 5) |
| Text + image search | Both: `AssetIndex` + `DeckSearch` (Phase 6) |

> **On "real merges".** This row said *Phase 3* until it was corrected: Phase 3
> shipped the native clone and durable local commits, but merging a concurrent
> edit was left out of it, and Phase 4 did not pick it up. It exists now on the
> **REST plane** (`deck_merge.dart`), and the shape of it is worth recording.
>
> The merge is **per slide, not per line**. Git's own answer would be a three-way
> text merge over `deck.md`, but a conflicted `deck.md` carries `<<<<<<<`
> markers and then no longer parses — so at exactly the moment the user has to
> choose, there would be nothing to show them. A slide is also the unit they
> think in. So slides are paired (the two-pass alignment of `diffDeckVersions`),
> and only genuinely competing edits become a conflict.
>
> What it decides by itself: one side changed, both changed identically, both
> deleted, each added something, or one side merely reordered (a move does not
> collide with an edit). What it refuses to decide: two different edits to the
> same slide, and delete-against-edit. Those come back as `SlideConflict` and the
> user picks per slide.
>
> Two deliberate fail-safes. A conflicted slide provisionally keeps **our** side
> in the result, never silently theirs. And the deck's classification becomes the
> **stricter** of the two — otherwise a merge would quietly discard someone
> else's TLP escalation, which is the one direction this path must never fail in.
>
> **Both planes** do this. They differ in one honest way: the REST plane has to
> take the tab's recorded `baseSha` for the common ancestor, while the native
> plane can ask git for the real one (`git merge-base`). Native also lets git
> merge the rest of the tree — the pool blobs are content-addressed and simply
> come along — and resolves only `deck.md` itself, then records a true merge
> commit with two parents so the next push fast-forwards. When the slide merge
> does *not* come out clean, native still makes that merge commit locally (so the
> branch stops diverging and the next attempt cannot collide on the same point)
> but does not push it until the user has chosen.
>

---

## 13. Implementation reference (paths & integration points)

New:
- `lib/services/git/git_forge.dart` — interface + shared value types.
- `lib/services/git/gitea_forge.dart`, `github_forge.dart`, `gitlab_forge.dart`.
- `lib/services/git/deck_mirror.dart` — the `DeckMirror` interface.
- `lib/services/git/native_git_mirror.dart` — desktop clone (Phase 3).
- `lib/services/git/draft_mirror.dart` — the text draft + outbox (Phase 2).
- `lib/services/git/git_cli.dart` — **the only** `Process.run` site; §10.2 lives
  here.
- `lib/services/git/git_cli_stub.dart` — web stub, wired by conditional import
  exactly as `lib/platform/native_window.dart` does it.
- `lib/services/git/sync_engine.dart`, `lib/services/git/asset_pool.dart`.
- `lib/models/git_settings.dart` — `GitRepoConfig`, `GitOrigin`, `GitProvider`.
- `lib/state/git_provider.dart` — `gitForgeProvider`, `deckMirrorProvider`,
  `gitCapabilityProvider` (the lazy probe of §8.4), family providers for
  tree/history/tags (mirrors `lib/state/webdav_provider.dart`).

Touch points (integrate, don't fork):
- `lib/services/parts/file_service_package.dart` — reuse `buildPackageMembers`;
  add a re-path step to the §6 layout + `repo:` asset substitution.
- `lib/services/markdown_service.dart` — `repo:` scheme round-trip.
- `lib/utils/project_path.dart` — repo-root resolution for `repo:` (with guard).
- `lib/services/image_dedup_service.dart` — SHA-256 hashing for pool names.
- `lib/state/deck_provider.dart` — `save()`/open routed via `DeckMirror`.
- `lib/state/tabs_provider.dart` — `GitOrigin` on `TabInfo`; open-from-git path.
- `lib/models/webdav_settings.dart` — `GitOrigin` mirrors `WebdavOrigin`.
- `lib/widgets/app_shell.dart` — per-tab provider overrides already support this.
- `lib/services/export_service.dart` — reuse the classification gate for PR open
  **and tag create**.
- `lib/utils/net_guard.dart`, `lib/services/secret_store.dart` — reused as-is.
- `lib/platform/platform_features.dart` — note in the doc comment that native git
  is a *runtime* capability and therefore deliberately not a getter here (§8.4).

Docs to update when it lands: `ARCHITECTURE.md`, `SOURCE_MAP.md`,
`FILE_FORMAT.md` (the repo layout + `repo:` scheme), `USER_GUIDE.md`,
`CHANGELOG.md`. `LICENSE_COMPLIANCE.md` and the SBOM need **no** change — which
is a deliberate consequence of §4.3, and worth checking still holds at merge time.

---

## 14. Decisions

These were open questions; all but one are now decided. **The numbering is
deliberately unchanged** (OQ-*n* → D-*n*), so references from the review
discussion still resolve.

- **D1 — Hash algorithm & pool naming.** **SHA-256** for pool filenames. The
  existing **md5 stays** in the in-session dedup UI: that comparison is ephemeral
  and never written to a durable name, so collision resistance is not what it is
  for. No migration.
- **D2 — Auth.** **PAT** for v1, in `secret_store` (§10.1). OAuth device-flow is a
  later per-provider nicety, not a v1 blocker.
- **D3 — Branch strategy.** A **fresh, generated branch per editing round**, cut
  from current `main` and named `decks/<naam>/<datum>`. No long-lived per-deck
  branch, so nothing drifts from `main` and nobody has to remember a back-merge.
  The user never types or sees a branch name in the normal flow (§9.4).
- **D4 — Native git on desktop.** The user's **`git` CLI as a runtime-detected
  capability**, REST as the fallback; **nothing bundled**. libgit2 (`git2dart`)
  stays documented as the escape hatch behind `DeckMirror` if git-absent proves
  common (§4.3).
- **D5 — Large media.** **Partial clone** (`--filter=blob:none`) plus a size
  warning. No hard cap — telling a presentation author their video is too large
  is a bad answer from a tool that supports video — and **no Git-LFS in v1**
  (§8.2).
- **D6 — Repo granularity.** **Many decks per repo**; the shared asset pool
  requires it. A repo whose root is a single deck is **not** supported — one
  layout, no detection. The governing rule is that **a repo is a trust boundary**:
  one per client, engagement or classification level, because forge access is
  all-or-nothing and the pool cannot straddle a boundary the forge does not
  enforce (§6).
- **D7 — Sidecar conflicts.** **Per type**: `.notes` is text and takes git's
  ordinary text merge; `.annotations` is ink and **unions** the stroke sets via a
  merge driver, because two people drawing on one slide did not disagree. Manual
  resolution only where both fail (§9.7). Erasure-vs-union and per-stroke identity
  are consequences that belong to the annotation file format, not to this document.
- **D8 — Minimum git version.** Required, and enforced by the probe. Below it the
  native plane is refused **wholesale** and the repo falls back to REST — never
  feature-by-feature. `--filter=blob:none` (D5) puts the floor at **≥2.19**; pin
  the exact number when Phase 3 starts (§8.4).
- **D9 — Tag namespacing.** **`decks/<naam>/v1.0`**. Groups readably in forge UIs,
  makes tag-protection patterns (`decks/*/v*`) natural for a ref that is gated
  under P8, and avoids git's D/F conflict because `decks/<naam>` is never itself a
  tag (§9.4).
- **D11 — Identity & signing.** **Name/email per repo**, never a silently
  inherited global `user.name`. **SSH commit signing, optional, native plane
  only** — SSH over GPG for the lighter key story, and optional because the REST
  plane builds commits server-side and has nothing to sign with. The UI presents
  signing as a property of a *commit*, never of a deck (§9.6).

### The one still open

- **OQ-10 — Token delivery to the `git` subprocess.** Not a design choice but a
  **verification task for Phase 3**. §10.2 proposes `GIT_CONFIG_*` env vars with
  `http.extraHeader`, avoiding argv, the remote URL and `.git/config`. Validate it
  against each forge, and confirm the token cannot leak into a reflog, a trace
  (`GIT_TRACE`), a credential cache or a crash report. Do not consider §10.2 final
  until this is proven on all three desktop platforms.
  - **Status.** The `GIT_CONFIG_*`/`http.extraHeader` delivery is implemented in
    `native_git_mirror_io.dart`. The token is never in argv (unit-tested in
    `git_cli_test.dart`), never written to `.git/config`, and — verified by a
    byte-level scan of the whole clone after a token-carrying commit — appears
    nowhere on disk in the working copy, so not in a reflog, credential cache or
    stray trace file either (`native_git_mirror_test.dart`).
  - **One gap this verification actually found and closed.** The subprocess was
    started with Dart's default `includeParentEnvironment: true`, so the
    environment was *not* closed despite the code and docs claiming it was: the
    user's own shell came along. That matters here specifically, because the
    token travels as an `Authorization:` header — a `GIT_TRACE_CURL=1` together
    with `GIT_TRACE_REDACT=0` in the user's environment would have written it out
    verbatim. The same inheritance also carried `GIT_ASKPASS`,
    `GIT_SSH_COMMAND`, `GIT_PROXY_COMMAND`, `GIT_EXTERNAL_DIFF` (each names a
    command git executes) and `GIT_CONFIG_PARAMETERS` (arbitrary config
    injection). The environment is now built from an explicit **allowlist** —
    deliberately an allowlist, since a denylist rots the moment git adds a new
    `GIT_*` — carrying only what a process needs to start (`PATH`, plus the
    Windows essentials, plus `SSL_CERT_*` so distributions that point at their CA
    bundle that way keep working).
  - **What is proven, and where.** The properties above are asserted by the test
    suite itself rather than by a one-off manual check, so running
    `flutter test test/git_cli_test.dart test/native_git_mirror_test.dart` on a
    platform proves them *on that platform*. Done on **macOS**.
  - **Still open.** (a) Running that suite on **Windows and Linux** — nobody has;
    the allowlist's Windows entries are reasoned from what Git for Windows needs,
    not observed. If it is wrong, `probe()` fails and the app falls back to the
    REST plane, so the failure is graceful but quiet. (b) A **live Basic-auth
    handshake** against a real Forgejo/GitHub/GitLab, which no offline test can
    stand in for. §10.2 stays provisional until both are done.

### What awaits a live test environment

Moved to [`VERIFICATION.md`](VERIFICATION.md), which collects the same debt for
the MIAUW work as well. Keeping two lists was how it got scattered in the first
place; items 1–5 there are this phase's.

---

## 15. Summary

Store decks in a git repo by treating the **forge as a versioned network deck
source** — the WebDAV pattern plus commit/branch/PR/tag semantics. The design
splits along one seam: the **forge plane** (pull requests, review, search) is
always provider REST behind a `GitForge` interface, because git has no notion of
a PR; the **data plane** is native `git` on desktop when the user has it, and the
same REST calls otherwise. Because web needs the REST plane regardless, native
git costs nothing to make optional — so OciDeck detects the user's `git`, uses it
for real offline history and real merges, and **bundles nothing**, keeping the
tree free of FFI, native binaries and the GPL-classified dependency its own
licence policy would flag.

A deck is a **folder of real files** so history and diffs mean something; assets
live once in a **content-addressed shared pool** (`repo:assets/<hash>`) so nothing
is duplicated. Editing always targets a **`DeckMirror`** and a **`SyncEngine`**
reconciles it with the forge, so authoring works offline and syncs later. Saving
is a commit; **releasing is a classification-gated pull request to merge and an
annotated tag to mark the version**, so `v1.0` and `v2.0` of the same presentation
both remain retrievable. Asynchronous collaboration then falls out of the model:
clone, branch, review, merge — with live co-editing left to
[`COLLABORATION.md`](COLLABORATION.md), on the other side of a deliberate seam.

Almost every dependency — `buildPackageMembers`, `image_dedup_service`,
`net_guard`, `secret_store`, per-tab origins, provider scope and the
`lib/platform/` capability pattern — already exists; the new code is the forge
clients, the two mirrors and the sync engine.
