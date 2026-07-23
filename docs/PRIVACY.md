# OciDeck — Privacy & Data Handling

> **Status:** current-state description of what stays local and what leaves · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

A plain-language guide to what happens to your data in OciDeck: what stays on your
device, what leaves it and only when you ask, and the controls you have. For the
technical mechanisms behind these guarantees, see
[SECURITY_DESIGN.md](SECURITY_DESIGN.md).

## The short version

- **Your presentations stay on your device.** There is no OciDeck account, no
  server that holds your decks, and no telemetry. Nothing is uploaded in the
  background. *(Corrected 2026-07-22: this said "no OciDeck server", full stop.
  That is not true — the publisher runs one, `cveapi.librekat.nl`, for CVE
  lookups. It never sees a deck, it is off by default, and you can point the app
  somewhere else or use the offline database instead — but "no server" was an
  absolute claim and the exception belongs in the summary, not only in a table
  170 lines down. Extended 2026-07-23: there is a second one,
  `ocideck.librekat.nl`, the public web demo — a copy of the app served by the
  publisher, where your decks still stay in your tab but the origin is not
  yours. See [The servers the publisher runs](#the-servers-the-publisher-runs).)*
- **Almost everything that leaves your device is something you explicitly
  send** — by importing from a URL, saving to your own Nextcloud/git server, or
  turning on the AI assistant. Three paths are the exception, and two of them you
  do not choose in the moment: the **CORS fallback** on the web build (used
  automatically, without a separate prompt), an **embedded YouTube or Vimeo
  video** (the service is contacted when the slide plays), and the **CVE lookup**
  if you switch it on. The table below is complete; it has ten rows, not three.
  *(Corrected 2026-07-22: this bullet said "the only data … is data you
  explicitly send", which was already contradicted 170 lines further down. The
  summary is the paragraph most people actually read, so it was wrong exactly
  where it counted most.)*
- **You control sharing** through privacy scanning (OciWacht), redaction, and TLP
  classification before anything is exported.

## What stays local

Editing, previewing, presenting, and exporting all happen entirely on your
machine (desktop) or in your browser tab (web). This includes:

- The deck content, notes, and annotations.
- Imported images and media (kept in the project folder).
- Your settings and theme profiles.
- Autosave/recovery snapshots — written to a per-user application-support folder,
  removed the moment the deck is saved or the app is closed normally, and pruned
  after 7 days otherwise. The 7-day clock is checked while the app runs as well
  as at startup, so a machine that stays on for weeks does not keep a snapshot
  from an old crash. They are not encrypted; they rely on your operating-system
  account protections, just like your other files — and on Linux, where the
  application-support and temporary folders would otherwise be created readable
  by other local accounts, OciDeck restricts them to your own account at startup.
  A snapshot holds the deck text, your user notes and the drawings made on the
  slides, so everything you would want back after a crash is in there —
  including the parts that live beside the `.md` rather than in it. In the
  browser no snapshot is written at all, because there is no such folder.
  Settings → Security has a button that wipes them immediately.

  *Why not encrypt them?* A snapshot almost always holds a deck that also exists
  as an ordinary `.md` in your own project folder — unencrypted, on the same
  disk, with the same permissions. Encrypting the snapshot while the original
  sits unencrypted beside it would only protect the deck you have never saved,
  which is also the shortest-lived case. It would cost a full cryptography
  library in the dependency tree, and it would make recovery fail silently on a
  machine where the key is gone (a restore, a new laptop) — exactly when you
  need it. Bounding how long the plaintext exists, and making sure your account
  is really the only one that can read it, buys more here.
- **Unpushed git work in the browser.** With a git repository connected, the web
  build keeps your not-yet-pushed deck text, notes and annotations in the
  browser's own key/value storage, so a reload does not throw the work away.
  That is ordinary browser storage for the origin serving OciDeck, not a
  protected store: anything with access to that browser profile can read it.
  It holds your own document, never a password or token — those are refused
  outright in the browser (see *Secrets are stored in your OS keychain*). The
  entry is removed as soon as the work is confirmed on the forge, so what stays
  behind is only what has not been pushed yet. Two deliberate exceptions, both
  on the side of not losing your work: if the push fails, conflicts, or you are
  offline, the entry stays; and if you saved again while the push was running,
  the newer version stays too, because that version has not landed. On the
  desktop the equivalent is a real git clone in a per-user application-support
  folder — that one keeps its files, because it is what the editor reads the
  deck from and it carries the history.
- **Staged media.** A deck you have not saved yet has no project folder to keep
  its images in, so an image you insert is copied into a per-session folder under
  your operating system's temporary directory. That is what keeps the picture
  from breaking when you move or rename the original before saving — but it does
  mean a photograph can sit in the temp directory of a deck you never saved.
  Stale session folders are removed on startup after 7 days, on the same clock as
  the snapshots above, and saving the deck moves the files to the project folder.
- **Git working copies.** Connecting a git repository puts a real clone — full
  deck content and history — in a per-user application-support folder, plus a
  queue of commits that haven't been pushed yet. Unlike autosave snapshots these
  are **not** cleared after 7 days: a working copy is meant to persist. They are
  not encrypted either, and the queued commit *messages* you typed are stored in
  the ordinary settings file. If a repository's contents are sensitive, that
  sensitivity is on this disk too, not only on the server.

  **Removing the connection removes the clone.** Deleting a git connection in
  Settings also deletes the clone under `git_clone/<connection>/`, the draft
  store under `git_mirror/<connection>/` and the queued commits under the
  `git_outbox::` keys. The keychain secret stays — deliberately, because it
  belongs to the account rather than to this one connection, and a second
  connection to the same server still needs it.

  With one exception, and it is the important one: if that connection still has
  commits that were never pushed, they exist nowhere else. OciDeck will not throw
  them away without asking. It shows you which deck, which branch and which
  commit message is at stake; if you decline, the connection stays and so does
  the working copy. *Corrected 2026-07-22: until this release, removing a
  connection left all of the above on disk. The paragraph said so, but the
  behaviour was wrong, not the wording.*

- **Style-profile logos.** Importing a `.ocideckstyle` copies its logo into
  `style_logos/` in the application-support folder — often a client's corporate
  logo. Deleting the profile now deletes the logo with it, and orphans left by
  earlier versions are swept at startup.

- **Everything at once.** Settings → Security has *Reset everything to its
  initial state*: all settings, the recent list, the recovery snapshots, every
  git working copy and the passwords in your keychain. Your presentations are
  not touched — those are yours, not OciDeck's. If unpushed commits are waiting,
  the confirmation says how many before you go ahead.

- **The recent list.** OciDeck remembers the full path, the slide count and the
  TLP classification of the last ten decks you opened. Together that is a
  statement about what you are working on and for whom, so Settings → Security
  can clear the whole list in one action.

There is **no analytics, tracking, or usage reporting of any kind.**

### Face detection in slide images

When the privacy check is on, OciDeck looks at the images on your slides to see
whether a **recognisable face** appears in them — because an image in which
someone is recognisable is personal data, even with no name attached, and the
text scanner can never find that.

This runs entirely on your device with a bundled 232 KB model (YuNet, MIT). No
image, and no result, leaves your machine.

**It detects presence, never identity.** The model reports a box, five landmarks
and a score per face; OciDeck keeps only *the number* and discards the rest
immediately. Nothing is stored, no template is computed, and nothing is compared
against anything else. That distinction is deliberate and legal, not cosmetic:
under EDPB Guidelines 3/2019 (§74–76) an image becomes Article 9 *biometric* data
only when it is "specifically technically processed in order to contribute to the
identification of an individual". A privacy tool that built face templates in
order to warn you about face templates would create exactly the category of data
Article 9 protects most strictly.

It finds **faces, not people** — someone photographed from behind, in profile,
wearing a mask, or with their head outside the crop is missed, and the message
says "recognisable face" for that reason. Images in a format the check cannot
read (HEIC, for instance) are reported as *not checked* rather than as *nothing
found*.

This is the most expensive check OciDeck runs, so it has its own switch under
*Settings → Security*, separate from the main privacy switch.

**It does not run in the browser.** The detector is a native library reached over
FFI, and that does not exist on the web platform, so the web build checks text
only. This is a difference you have to know about rather than one you can notice:
the same deck that warns a desktop user about a face on slide 4 raises no image
warning at all in a browser.

OciDeck does not paper over it. The check reports that it is unsupported rather
than returning zero faces, and the panel listing which checks ran omits the image
check instead of showing it as passed — "we found nothing" and "nobody looked"
must never read the same. But the consequence is real: if your material contains
photographs of people, do that check on a desktop build. See
[HOSTING.md](HOSTING.md) §5 for the full list of what the web build leaves out.

## What leaves your device — and only when you ask

OciDeck makes network requests only for actions you initiate. Each is gated
against accessing internal/private network addresses.

| Action | What is sent | Where |
|---|---|---|
| **Import from URL** | An HTTP(S) request for the deck/asset you named | The URL you entered |
| **Import from URL — web fallback** | The same URL, as a query parameter, when the browser refuses the direct request on CORS grounds | `fetch-proxy` on the origin that served the app (see below) |
| **Save/Open — Nextcloud/WebDAV** | Your deck files | Your configured server |
| **Save/Open — S3** | Your deck files (objects) | Your configured endpoint (AWS S3, MinIO, or any S3-compatible service) |
| **Save/Open — Git** | Your deck files (commits) | Your configured forge (Gitea/Forgejo/GitLab/GitHub) |
| **AI assistant** (off by default) | The specific text/image you request help with | The endpoint you configured |
| **CVE lookup** (off by default, desktop only) | Your search term or CVE id | The CVE mirror in Settings — by default `cveapi.librekat.nl`, run by the publisher — and, when that yields nothing, ENISA's EU Vulnerability Database and MITRE (neither of those two is configurable) |
| **Local CVE database** (you start the download) | A request for the latest bulk release | `api.github.com`, then the release asset it points to |
| **Embedded YouTube video** | A request for the player page and the video itself; the service can see that the video is being played | `youtube-nocookie.com` (and its media/thumbnail hosts) — **not** `youtube.com` |
| **Embedded Vimeo video** | A request for that service's player script and the video itself; the service can see that the video is being played | `vimeo.com` |

Everything in the first six rows goes to servers **you** point it at — not to
OciDeck. The last four rows are the exceptions, and they are listed because
naming them is the only honest way to keep the sentence above true:

- The **fetch-proxy** exists because most servers send no CORS headers, so a
  browser will not let the app read them. It only forwards bytes and stores
  nothing, and it applies the same SSRF rules server-side that NetGuard applies
  on desktop — but the URL you typed does reach whoever operates that origin,
  and it is used automatically, without a separate prompt. On desktop the
  fallback never runs. If you host the web build yourself, §4 of
  [HOSTING.md](HOSTING.md) covers deploying (or deliberately not deploying) it.
- The **CVE lookup** is off by default and desktop-only, and the mirror address
  is a setting you can repoint at your own mirror. The ENISA and MITRE
  fallbacks are not settings; they are compiled in. This is the one destination
  in the table that belongs to the publisher, so it gets its own section below.
- **YouTube and Vimeo** load their player from their own service, which is
  inherent to embedding a video hosted there. Remote media is off by default
  (*Settings → Security → allow remote media*). For YouTube the player is a
  bare `youtube-nocookie.com` frame: no script is fetched from `youtube.com`,
  and the player's "Watch on YouTube" link is refused rather than followed, so
  a click during a presentation cannot swap the slide for the tracking origin.
  That is not the same as "nothing is observed" — YouTube still sees the
  request, and the video bytes still come from its media hosts.

### The servers the publisher runs

Everything above goes to a service you chose, or to a video platform you
embedded. Two destinations are different, and both are operated by **Stichting
LibreKAT**, the same foundation that publishes OciDeck: `cveapi.librekat.nl`,
the default mirror for CVE lookups, and `ocideck.librekat.nl`, the public web
demo. The first you reach from your own copy of the app; the second *is* a copy
of the app, served by the publisher.

#### `cveapi.librekat.nl` — the CVE mirror

**Why it deserves this much text.** What you look up is not neutral. Someone
searching for a specific vulnerability is usually working on a specific system,
often for a specific client, and often before the finding is public. The code
says so where the feature lives (`cve_picker.dart`): *wélk lek je opzoekt is
het gevoeligste dat je prijsgeeft*. A document that lists this in a table row
and moves on would be technically complete and practically useless.

**What the app sends.** One `GET` per lookup:

```
GET https://cveapi.librekat.nl/api/search?q=<your search term>&limit=25
GET https://cveapi.librekat.nl/api/cve/<CVE-id>          (exact-id lookups)
```

No account, no identifier, no deck content, no custom headers. But note where
the search term sits: **in the URL**, not in a request body. A URL query string
is the part every ordinary web server writes to its access log by default, next
to your IP address and a timestamp. Assume it is logged unless the operator says
otherwise.

**Who is responsible.** For this service, Stichting LibreKAT is the controller
under the GDPR — not you, and not "nobody". Questions, access or erasure
requests about it go to the address in [SECURITY.md](../SECURITY.md); for
everything else in OciDeck there is no controller because there is no
processing (see *Your rights and this tool*).

**What the operator states.** Which fields that server records, and for how
long, are properties of a deployment and not of the code, so this repository
cannot *prove* them. What it can do is record what the operator has said.
Stichting LibreKAT, as the operator, states two things (2026-07-23): it judges
the privacy impact of a CVE lookup to be **minor**, and it keeps what the
service receives **only for as long as it is needed to run the service** — the
storage-limitation principle of art. 5(1)(e), not a fixed schedule and not
indefinitely. There is no separate published retention table beyond that
statement; if a formal one is issued later it belongs on the foundation's site,
not in this repository. Two things do not depend on the operator, and this
document *can* prove them: the search term travels in the URL (logged by default
unless suppressed), and the foundation is the controller for the request. Treat
a term you send as disclosed, decide accordingly, and if the "minor" judgement
is not yours to make for a given engagement, use one of the routes below.

**How to avoid it entirely**, in increasing order of effort:

1. Leave the CVE lookup **off** — it is off by default, and nothing contacts
   this server until you switch it on and accept the outbound prompt.
2. Use the **local CVE database** instead (*Settings → Security → Local CVE database*). It downloads
   a bulk release once, from GitHub, and then searches offline. After that
   download, no lookup leaves your machine.
3. Point the mirror setting at **your own** instance, or at any NVD mirror you
   trust. The address is a plain setting.

The ENISA EU Vulnerability Database and MITRE fallbacks are a separate matter:
they are compiled in rather than configurable, and they are consulted only when
the mirror returns nothing. They are not run by the publisher.

*Added 2026-07-22 (#579). The summary at the top of this document said "no
OciDeck server" while this one existed and was described 170 lines further
down, and `COMPLIANCE.md` said the foundation does not host anything as a
service. Both were corrected in the same commit. A privacy document is the
first thing a critical reader checks, and it was wrong in the sentence most
people read.*

*Corrected 2026-07-21: this table previously listed only the five rows you
choose yourself, and the sentence "Nothing here goes to OciDeck" was true of
that shortened list rather than of the code.*

*Corrected 2026-07-22: the YouTube row named `youtube.com`, and it was right to
— the embed loaded its player script from there, so `YT.Player` put the player
on that origin too. The nocookie form was used everywhere else in the code. The
embed now loads no script at all; the row was split so the two services are not
described by one sentence that fits neither.*

#### `ocideck.librekat.nl` — the public web demo

The publisher serves a build of the web app at <https://ocideck.librekat.nl/>,
so anyone can try OciDeck without installing anything. It is the ordinary web
build ([what it does
less](KNOWN_LIMITATIONS.md#the-web-build-does-less-than-the-desktop-build)), not
a hosted edition with a backend: the editor, the privacy scan and every export
run in your tab, and **no deck is uploaded to that origin**. What the origin
does see is what any static web server sees — your IP address, a timestamp, and which files your browser
fetched. That is a processing operation, and Stichting LibreKAT is the
controller for it.

One path on that origin is not merely static. The demo carries the
[fetch-proxy](../server/fetch-proxy/README.md) that makes *Import from URL* work
for sources that do not allow CORS. When you use that import on the demo, the
publisher's server is what fetches the address you pasted — so it receives the
URL, and the bytes at that URL pass through it on the way to your browser. It is
same-origin and origin-checked (`/fetch-proxy` answers a request from anywhere
else with *"dit adres is alleen voor de OciDeck-app zelf"*), and it applies the
SSRF guard described in that README, but "your deck never touches the
publisher's server" stops being true the moment you import one there. On a
desktop build, or on a copy of the web build you host yourself, that path does
not exist.

**What the operator states.** Nothing yet. For the CVE mirror the operator
stated retention and a privacy judgement on 2026-07-23; for this host no such
statement has been made, and this repository does not invent one. What it can
establish is above: static serving with the access log that implies, plus the
proxy path when you import a URL. Until the operator says otherwise, assume the
ordinary access log.

**How to avoid it entirely.** Build the app yourself
([BUILD.md](BUILD.md)) or host the same web bundle on your own origin — it is a
static bundle, and the demo has no capability your own copy lacks. The demo is a
convenience for looking, not the intended way to work on a real deck; a deck you
would not open on someone else's computer is a deck to open in a build of your
own.

*Added 2026-07-23 (#589). The demo has existed for months, and this document —
like `COMPLIANCE.md` — said the publisher runs exactly one server. Linking the
demo from the README without writing this down first would have advertised a
publisher-run instance the privacy document denied the existence of.*

### Secrets are stored in your OS keychain

Passwords and tokens (your Nextcloud/WebDAV password, S3 secret access key, git
access token, and any AI API key) are stored in the operating-system keychain
(macOS Keychain, Windows Credential Manager, or the platform-appropriate secure
store) — never in a plain config file. Server URLs and usernames are ordinary
settings.

**Your own identity** — the name, e-mail address, phone number or domain you
enter under *Settings → Security → Your own details*, so the privacy scanner
stops flagging you as a finding — lives in the keychain too. It is not a
password, but it is the one setting that holds personal data about a real
person, and a tool that checks other people's decks for exactly that should not
keep its own copy in a plain settings file. Existing installations move the
value over on first start. *Corrected 2026-07-22: it used to sit in plain
preferences.*

Three boundaries of that sentence are worth naming, because "in the keychain" is
easy to over-read:

- For S3 it is the **secret** access key that is protected. The **access key ID**
  sits in the ordinary settings file alongside the endpoint and bucket name. It
  is an identifier rather than a password, but it is closer to a credential than
  a username is, and on its own it tells a reader of that file which account you
  use.
- The git token is stored in the keychain, but at the moment a push or fetch
  runs it is handed to the `git` process in its environment. It is deliberately
  kept out of the command line, out of the remote URL and out of `.git/config`,
  and the subprocess runs with a stripped environment — but for the life of that
  process the token exists outside the keychain.
- **In the browser there is no keychain, so the web build stores no secrets at
  all.** A browser has nowhere to put a secret that other scripts on the same
  page cannot reach: anything the app "encrypted" into browser storage would
  have to keep its key in that same storage, which protects nothing. Rather than
  make a promise the platform cannot keep, the web build refuses — the password,
  token and key fields are disabled there and say why on the spot. Sources that
  need no secret (a public URL, a local file) keep working. To use
  Nextcloud/WebDAV, S3, a git forge or an AI key, use the desktop build, where
  the sentence above holds.

*Corrected 2026-07-22: the web build previously wrote these secrets into browser
storage next to the key that encrypted them, which this section did not say and
which the sentence above did not describe. It now stores nothing.*

### The AI assistant is off by default and fail-closed

The optional AI assistant does nothing until you switch on its module card under
**Settings → Uitbreidingen (Extensions)**. Until you do, it has no tab of its own
in the settings sidebar at all. Switching the module on reveals a
**Settings → AI-assistentie** tab where you pick a backend — and even then
nothing is sent, because the default backend is *none*. Then:

- **Local model** — requests go only to a loopback address on your own machine;
  nothing leaves the device.
- **Self-hosted** — requests go to a server you explicitly mark as trusted
  internal.
- **Cloud** — requires **two** confirmations (the general outbound-privacy
  consent under *Settings → License and Privacy*, **and** a per-destination
  confirmation), and is **blocked entirely on the web build**.

If a request isn't clearly permitted by your settings, it is refused before any
network call is made. A request never sends your whole deck — only what the task
needs: one image for alt-text, or the single finding you are editing (all of its
fields, as grounding context) when the finding assistant drafts a field. And that
text context does not leave as you typed it: it is first run through the same
privacy projection every other outbound path uses, so anything the scanner flags
as personal data is redacted before it is sent. The technical identifiers a
finding needs to make sense — its CVSS vector, CWE and CVE ids — are not personal
data and are left intact.

**An image is a different matter, and the difference is not a gap.** The privacy
projection works by substituting characters, and a JPEG has none — so an image
*cannot* be run through it. That is precisely why OciDeck asks you to confirm
every single image before it goes, naming the destination and how many
recognisable faces it found in that image. For a penetration tester the evidence
screenshot is the most sensitive thing in the deck, and one click should not be
able to send a screenshot of an admin panel or a group photo to a third party.
*(Added 2026-07-22: this paragraph named image and text in one breath and applied
the safeguard only to text, so it read as though the image was equally
protected.)*

## Controls for sharing safely

### Privacy scanning (OciWacht)

OciDeck can scan your deck for personal and sensitive data and either flag it or
redact it. It detects, among others:

- Email addresses, phone numbers, postal addresses and postcodes
- IBAN/bank numbers (checksum-validated), BSN, and national identifiers for all
  27 EU member states, plus Iceland, Liechtenstein, Norway, Switzerland and two
  UK numbers
  (*corrected 2026-07-21: the count said 13, which was the state of
  `privacy_eu_rules.dart` before the second batch of European numbers landed;
  raised to 21 that same day, and to the full 27 on 2026-07-22 when Cyprus,
  Latvia, Luxembourg and Malta got their rules*)

  Four of those rules deliberately have no checksum. Two because none is
  published that we could verify: the Maltese identity card number and the
  Liechtenstein PEID. Two because the published one was withdrawn or never
  existed: the Danish CPR, whose mod-11 check was abandoned in 2007 and whose
  rule therefore validates only the date part, and the UK National Insurance
  number, which has a strict format and no check digit. All four only report
  when a matching label sits next to the number, and none ever rises above
  "likely".

  *(Corrected 2026-07-22: this said "Two", and named only Malta and
  Liechtenstein. Denmark and the UK were missing — `docs/design/OCIWACHT.md`
  already listed all four, and `privacy_checksums_eu.dart` says so in its own
  comments. The README made the matching claim that every EU number carries a
  checksum; that has been corrected in the same change.)* For Cyprus, the rule covers the tax
  identification code (which does carry a check character) and not the identity
  card number, which has no check digit at all. Guessing an algorithm would be
  worse than having none: it would reject genuine numbers and wave invented ones
  through.
- Secrets (API tokens, private keys, JWTs, plaintext passwords)
- GDPR Article 9 special-category keywords — **with three of them off by
  default**: ethnic origin, political opinion and sexual orientation. Not
  because they matter less, but because their keywords appear too often on
  ordinary business slides, and a check that cries wolf gets switched off
  wholesale. They are one tap away under **Settings → Security**, and anyone
  working in that corner should turn them on. *(Stated 2026-07-22: the setting
  screen presented this factory state as though the user had disabled them.)*
- Structural leaks such as tokens embedded in URLs or local file paths

Name detection is intentionally conservative — it flags names only where a
salutation or label makes them unambiguous, to avoid crying wolf.

### Redaction

- Wrap anything in double square brackets — `[[secret]]` — to redact it manually;
  it is removed from every surface that reaches someone other than you.
- Automatic redaction replaces sensitive content with a fixed-width block so its
  original length can't be reconstructed.
- Redaction is applied **before** the content reaches any preview, presentation,
  or export surface — not painted over afterwards.
- On a slide set to **redact**, the media goes too: image, video and audio are
  removed and a black redaction block takes their place, rather than the grey box
  that means "no picture chosen yet". This includes a picture typed into the
  running text of a rich-text body (`![…](…)`) — the path is emptied while the
  reference itself stays, so the text does not shift as if nothing had ever been
  there. *Added 2026-07-22: until then only the image, video and audio fields were
  cleared, so a redacted slide travelled to the screen and the export with the
  picture from its body intact.* The source file keeps its images; this is about
  what is shown and exported.
- Redaction is applied **before** the content reaches a presentation, an audience
  window or an export — not painted over afterwards. There is no unredacted copy
  behind the blocks for a recipient to recover.
- **Your own editor keeps showing your own text**, and that is the one deliberate
  exception. The preview, the thumbnails and the slide list are what you write
  in; blacking them out would leave you nothing to correct. On a slide set to
  *leave out of display and export* the preview says so and offers a switch to
  the recipient's version, so you can check it before anything is sent.

  *Corrected 2026-07-22. The first two entries read "always removed from previews
  and exports" and "before the content reaches any preview" — which claimed the
  editor was redacted too. It never was, and the wording promised more than the
  code does.*

### The redaction manifest, and the file that must stay home

An export that removes something writes two files beside it. `-redactions.json`
lists what was taken out — rule, slide, field, and a salted commitment, but no
values — and is meant to travel with the report, so a recipient can dispute a
specific redaction and you can prove what it hid without opening the rest.

`-redaction-keys.json` holds the salts, and it stays with the source. Without a
salt a commitment over a short, structured value is trivially reversible; with
the keys file in hand, every redaction in the accompanying document can be
recomputed. Sending it along would undo the redaction while the document still
looks redacted, which is worse than not redacting at all.

OciDeck names both files in the export dialog and repeats the warning inside
each file, but it cannot stop you from attaching one. That decision stays
yours — see USER_GUIDE, *The two manifest files*.

### Classification (TLP)

Tag a deck with a Traffic Light Protocol level — `CLEAR`, `GREEN`, `AMBER`,
`AMBER+STRICT`, or `RED`. You can set a release ceiling so exports above the
allowed level are blocked, and optionally stamp the classification as a watermark
on exported files.

### Exports can't phone home

HTML exports are sanitised and carry their own strict content-security policy, so
an exported file opened in a browser cannot run injected scripts or send data
anywhere. `.ocideck` packages can be password-encrypted. *Corrected 2026-07-22:
this heading also called an export "self-contained". It is not, in one respect:
the HTML export leaves slide images as relative references instead of embedding
them — the same overstatement corrected elsewhere on 2026-07-21.*

## Your rights and this tool

OciDeck is a **local tool**, not a service that processes your data on your
behalf, so there is no OciDeck-held copy of your decks to request or erase —
your files are yours, on your disk. When you use it with your own Nextcloud or
git server, the privacy terms of *those* services apply to what you store there.

**Two exceptions, and both are the publisher's.** If you switched on the CVE
lookup and left it pointed at the default mirror, then `cveapi.librekat.nl`
received your search terms. And if you used the public demo at
`ocideck.librekat.nl`, that origin received the ordinary web-server record of
your visit — plus, if you imported a deck from a URL there, the URL itself and
the bytes behind it. For both, Stichting LibreKAT is controller for whatever
those servers kept, and rights of access and erasure under articles 15 and 17
apply there, to the foundation — see
[The servers the publisher runs](#the-servers-the-publisher-runs), including
what that section can and cannot tell you. *(Added 2026-07-22: this paragraph
said there was nothing to request or erase, full stop, which was true of your
decks and untrue of that one service. Extended 2026-07-23, #589, for the demo
host.)*

Because OciDeck is open source (EUPL-1.2), you can verify every claim in this
document against the code.

### Who is controller, and who is not

Most of this document is about *your* data. But a deck routinely holds data
about **other people**: a pentest report names the employee who clicked, a
screenshot carries a colleague's mailbox, a finding carries the account it was
found on. Under the GDPR someone answers for that data, and it is worth writing
down who — because the promise this tool makes rests on that division, and it
has so far been stated nowhere.

- **You are the controller for what is in your deck — unless your assignment
  makes you something else.** Normally you chose to put those people's data in
  it, for your purpose, and you decide who receives it. But if you test on a
  client's instructions, and it was the client who decided this data would be
  processed at all, you may be that client's **processor** instead, or the two
  of you joint controllers under art. 26. Which of the three it is follows from
  the assignment, not from this tool. It matters here for one concrete reason:
  a processor may not engage another processor without the controller's prior
  authorisation (art. 28(2)). If that is your position, the third bullet is
  something you clear with your client *before* you switch it on — arranging it
  yourself is not enough. And if you use OciDeck as an employee, "you" in this
  section is your employer (art. 29).
- **Stichting LibreKAT is not a processor for it, and offers no processing
  agreement.** Not as a refusal, but because there is nothing to cover: the
  publisher receives no deck. OciDeck runs on your device, and every storage
  location in the table above is a server *you* pointed it at. If a client's
  procurement asks you for an art. 28 agreement with the publisher of your
  editing tool, the accurate answer is that no processing takes place that such
  an agreement could describe — the same answer you would give for the text
  editor you write in. Two paths sit outside this bullet and are named below:
  the CVE lookup reaches a server the publisher runs, and on the **public demo**
  the publisher is also the one serving the app and proxying a URL import. Both
  make the foundation a controller in its own right rather than your processor
  — but if you work on a client's deck, note that the demo is the publisher's
  computer, not yours. That is a decision to make before you open the deck
  there, not after.
- **The parties you switch on are yours to arrange.** An AI endpoint, an S3
  bucket, a WebDAV server or a git forge does receive your content, and if that
  content holds personal data, that party processes it on your behalf. The
  art. 28 agreement is between you and them — unless the server is your own, in
  which case there is no second party and nothing to agree. If that party sits
  outside the EEA, art. 28 is only half of it: a transfer also needs a basis
  under Chapter V, such as standard contractual clauses or an adequacy decision.
  Each of these is off until you configure it, and each is named in the table
  above precisely so you can see what you have to arrange before you turn it on.

One thing does not fit this division, and it should not be smoothed over: the
**CVE lookup**. Its first stop is a mirror the publisher runs itself
(`cveapi.librekat.nl`), so a search term you send there is a search term the
publisher receives — and for that one path Stichting LibreKAT is not your
processor but a controller in its own right, for the request it receives. The
operator keeps what that server receives only for as long as it needs to run the
service (art. 5(1)(e); no fixed schedule is published), and judges the privacy
impact minor — see [The servers the publisher runs](#the-servers-the-publisher-runs)
for the full statement. Either way, treat a search term you send there as
disclosed.

Two limits on the mitigations, because the setting reads more reassuring than it
is. **Emptying the mirror field does not point the lookup at nothing** — it
restores the publisher's address. The switch that sends nothing is the CVE
lookup itself, and it is off until you turn it on. **Repointing at your own
mirror does not close the path either:** when a lookup yields nothing, ENISA's
EU Vulnerability Database and MITRE are contacted next, and those two addresses
are compiled in rather than configurable. The one arrangement in which a search
term never leaves your machine is the **local CVE database**: with it installed,
the online cascade is not used at all — not even when the local search finds
nothing.

*Added 2026-07-22. This section did not exist. The document treated the reader
solely as a data subject — "your files are yours" — and never as the controller
they are the moment a deck holds someone else's name. For a tool that is
marketed for penetration-test reports, that was the most predictable gap a
reader with GDPR knowledge would find.*

## See also

- [SECURITY_DESIGN.md](SECURITY_DESIGN.md) — the mechanisms behind these guarantees
- [FAQ.md](FAQ.md) — common privacy/security questions
- [design/OCIWACHT.md](design/OCIWACHT.md) — the privacy scanner's design
