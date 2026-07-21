# OciDeck — Privacy & Data Handling

A plain-language guide to what happens to your data in OciDeck: what stays on your
device, what leaves it and only when you ask, and the controls you have. For the
technical mechanisms behind these guarantees, see
[SECURITY_DESIGN.md](SECURITY_DESIGN.md).

## The short version

- **Your presentations stay on your device.** There is no OciDeck account, no
  OciDeck server, and no telemetry. Nothing is uploaded in the background.
- **The only data that leaves your device is data you explicitly send** — by
  importing from a URL, saving to your own Nextcloud/git server, or turning on
  the AI assistant. Each of those is described below.
- **You control sharing** through privacy scanning (OciWacht), redaction, and TLP
  classification before anything is exported.

## What stays local

Editing, previewing, presenting, and exporting all happen entirely on your
machine (desktop) or in your browser tab (web). This includes:

- The deck content, notes, and annotations.
- Imported images and media (kept in the project folder).
- Your settings and theme profiles.
- Autosave/recovery snapshots — written to a per-user application-support folder,
  kept for 7 days, then removed. They are not encrypted; they rely on your
  operating-system account protections, just like your other files.
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

  **Removing the connection does not remove the clone.** Deleting a git
  connection in Settings takes the connection out of the settings file and
  nothing else: the clone under `git_clone/<connection>/`, the draft store under
  `git_mirror/<connection>/` and the queued commits under the `git_outbox::`
  keys all stay where they are. The keychain secret stays too — deliberately,
  because it belongs to the account rather than to this one connection. If you
  need that content gone, delete those folders yourself. *Corrected 2026-07-21:
  this paragraph used to say the working copy "stays until you remove the
  connection", which reads as a promise that removing it cleans up. It does
  not.*

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
| **Embedded YouTube / Vimeo video** | A request for that service's player script and the video itself; the service can see that the video is being played | `youtube.com` / `vimeo.com` |

Everything in the first six rows goes to servers **you** point it at — not to
OciDeck. The last three rows are the exceptions, and they are listed because
naming them is the only honest way to keep the sentence above true:

- The **fetch-proxy** exists because most servers send no CORS headers, so a
  browser will not let the app read them. It only forwards bytes and stores
  nothing, and it applies the same SSRF rules server-side that NetGuard applies
  on desktop — but the URL you typed does reach whoever operates that origin,
  and it is used automatically, without a separate prompt. On desktop the
  fallback never runs. If you host the web build yourself, §4 of
  [HOSTING.md](HOSTING.md) covers deploying (or deliberately not deploying) it.
- The **CVE lookup** is off by default and desktop-only, and the mirror address
  is a setting you can repoint at your own spiegel. The ENISA and MITRE
  fallbacks are not settings; they are compiled in.
- **YouTube and Vimeo** load their player from their own service, which is
  inherent to embedding a video hosted there. Remote media is off by default
  (*Settings → Security → allow remote media*).

*Corrected 2026-07-21: this table previously listed only the five rows you
choose yourself, and the sentence "Nothing here goes to OciDeck" was true of
that shortened list rather than of the code.*

### Secrets are stored in your OS keychain

Passwords and tokens (your Nextcloud/WebDAV password, S3 secret access key, git
access token, and any AI API key) are stored in the operating-system keychain
(macOS Keychain, Windows Credential Manager, or the platform-appropriate secure
store) — never in a plain config file. Server URLs and usernames are ordinary
settings.

Two boundaries of that sentence are worth naming, because "in the keychain" is
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

### The AI assistant is off by default and fail-closed

The optional AI assistant does nothing until you enable it under
**Settings → AI Assistant**. Then:

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

## Controls for sharing safely

### Privacy scanning (OciWacht)

OciDeck can scan your deck for personal and sensitive data and either flag it or
redact it. It detects, among others:

- Email addresses, phone numbers, postal addresses and postcodes
- IBAN/bank numbers (checksum-validated), BSN, and national identifiers for 21
  EU member states, plus two UK ones and Swiss and Norwegian numbers
  (*corrected 2026-07-21: the count said 13, which was the state of
  `privacy_eu_rules.dart` before the second batch of European numbers landed*)
- Secrets (API tokens, private keys, JWTs, plaintext passwords)
- GDPR Article 9 special-category keywords
- Structural leaks such as tokens embedded in URLs or local file paths

Name detection is intentionally conservative — it flags names only where a
salutation or label makes them unambiguous, to avoid crying wolf.

### Redaction

- Wrap anything in double square brackets — `[[secret]]` — to redact it manually;
  it is always removed from previews and exports.
- Automatic redaction replaces sensitive content with a fixed-width block so its
  original length can't be reconstructed.
- Redaction is applied **before** the content reaches any preview, presentation,
  or export surface — not painted over afterwards.

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

### Exports are self-contained and can't phone home

HTML exports are sanitised and carry their own strict content-security policy, so
an exported file opened in a browser cannot run injected scripts or send data
anywhere. `.ocideck` packages can be password-encrypted.

## Your rights and this tool

OciDeck is a **local tool**, not a service that processes your data on your
behalf, so there is no OciDeck-held copy of your data to request or erase — your
files are yours, on your disk. When you use it with your own Nextcloud or git
server, the privacy terms of *those* services apply to what you store there.

Because OciDeck is open source (EUPL-1.2), you can verify every claim in this
document against the code.

## See also

- [SECURITY_DESIGN.md](SECURITY_DESIGN.md) — the mechanisms behind these guarantees
- [FAQ.md](FAQ.md) — common privacy/security questions
- [design/OCIWACHT.md](design/OCIWACHT.md) — the privacy scanner's design
