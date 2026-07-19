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

## What leaves your device — and only when you ask

OciDeck makes network requests only for actions you initiate. Each is gated
against accessing internal/private network addresses.

| Action | What is sent | Where |
|---|---|---|
| **Import from URL** | An HTTP(S) request for the deck/asset you named | The URL you entered |
| **Save/Open — Nextcloud/WebDAV** | Your deck files | Your configured server |
| **Save/Open — Git** | Your deck files (commits) | Your configured forge (Gitea/Forgejo/GitLab) |
| **AI assistant** (off by default) | The specific text/image you request help with | The endpoint you configured |

Nothing here goes to OciDeck — it goes to servers **you** point it at.

### Secrets are stored in your OS keychain

Passwords and tokens (your Nextcloud/WebDAV password, git access token, and any
AI API key) are stored in the operating-system keychain (macOS Keychain, Windows
Credential Manager, or the platform-appropriate secure store) — never in a plain
config file. Server URLs and usernames are ordinary settings.

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
network call is made. Requests send only the specific item you asked about (for
example, one image for alt-text), not your whole deck.

## Controls for sharing safely

### Privacy scanning (OciWacht)

OciDeck can scan your deck for personal and sensitive data and either flag it or
redact it. It detects, among others:

- Email addresses, phone numbers, postal addresses and postcodes
- IBAN/bank numbers (checksum-validated) and BSN / ~30 EU national identifiers
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
