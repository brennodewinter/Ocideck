OciDeck @VERSIE@ — a presentation tool where the content, not the canvas, is
the document. Decks are Marp Markdown: plain text you can read, diff and keep.

**Try it without installing:** <https://ocideck.librekat.nl/> runs this same
version in your browser. Your deck stays in the tab; nothing is uploaded.

## Downloads

| Platform | File |
| --- | --- |
| macOS (Apple Silicon + Intel) | `ocideck-macos-@VERSIE@.zip` |
| Windows — installer | `ocideck-windows-x64-setup-@VERSIE@.exe` |
| Windows — portable zip | `ocideck-windows-x64-@VERSIE@.zip` |
| Linux — AppImage (most distributions) | `ocideck-linux-x86_64-@VERSIE@.AppImage` |
| Linux — Debian / Ubuntu / Mint | `ocideck-linux-amd64-@VERSIE@.deb` |
| Linux — Fedora / openSUSE | `ocideck-linux-x86_64-@VERSIE@.rpm` |
| Linux — portable tarball | `ocideck-linux-x64-@VERSIE@.tar.gz` |
| Web bundle (self-hosting) | `ocideck-web-@VERSIE@.tar.gz` |

Also attached: the Software Bill of Materials in CycloneDX
(`ocideck-@VERSIE@.cdx.json`) and SPDX (`ocideck-@VERSIE@.spdx.json`),
`SHA256SUMS` over every file above, and `SHA256SUMS.minisig` — a minisign
signature over that list.

## Opening the download on each platform

The macOS build is signed and notarised; the Windows and Linux builds are not
code-signed. Only Windows warns on first launch — a Linux tarball does not.
Verify the download below, then:

**macOS.** Signed with a Developer ID and notarised by Apple — it opens with a
normal double-click, no workaround needed. (Check with `spctl -a -t exec
OciDeck.app`: it reports `source=Notarized Developer ID`.)

**Windows.** Two ways in, both the same build — pick one.

- **Installer** (`ocideck-windows-x64-setup-@VERSIE@.exe`) — installs to Program
  Files with a Start menu shortcut, registers `.ocideck` (and adds OciDeck to
  *Open with…* for `.md`), and uninstalls through *Apps & features*. Without
  administrator rights, choose the per-user install when it asks.
- **Portable zip** (`ocideck-windows-x64-@VERSIE@.zip`) — unpack and run
  `ocideck.exe`. Nothing is written outside the folder, and no rights are needed.

Neither checks for updates or contacts a server; a new version reaches you the
way every other change does — from the repository.

Both are unsigned, so SmartScreen shows "Windows protected your PC": choose
**More info**, then **Run anyway**. The installer additionally asks for
elevation as *Unknown publisher*. Check the download against `SHA256SUMS` (and
`SHA256SUMS.minisig`) before you run either — that signature, not a certificate,
is what attests where these files came from.

**Linux.** Four packagings of the same build — pick what fits your distribution.
None is sandboxed or store-signed; each wraps the same bundle listed above.

- **AppImage** — `chmod +x ocideck-linux-x86_64-@VERSIE@.AppImage`, then run it. One
  file, no installation, works on most distributions.
- **Debian / Ubuntu / Mint** — `sudo apt install ./ocideck-linux-amd64-@VERSIE@.deb`.
- **Fedora / openSUSE** — `sudo dnf install ./ocideck-linux-x86_64-@VERSIE@.rpm`
  (or `sudo zypper install ./ocideck-linux-x86_64-@VERSIE@.rpm`).
- **Any distribution** — unpack `ocideck-linux-x64-@VERSIE@.tar.gz` and run
  `./ocideck`.

All four need GTK 3, `libsecret-1` and `liblzma5`; the `.deb` and `.rpm` pull
them in, and any GTK desktop already has them. For the AppImage or tarball on a
minimal system: `sudo apt install libgtk-3-0 libsecret-1-0` (Debian/Ubuntu).

## Verifying what you downloaded

First check that the checksum list vouches for your files:

```
sha256sum --ignore-missing -c SHA256SUMS
```

(macOS: `shasum -a 256 -c SHA256SUMS --ignore-missing`.)

`SHA256SUMS` on its own tells you only that you have the bytes it lists — not who
published them. The list itself is therefore signed. Verify that signature with
[minisign](https://jedisct1.github.io/minisign/) and the project's public key
([`minisign.pub`](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/tag/@TAG@/minisign.pub)):

```
minisign -Vm SHA256SUMS -p minisign.pub
```

The key's ID is `CF0BCBD82CFD5B85`. Since the key and the signature come from the
same host as this download, cross-check that ID against an independent copy — the
[source repository](https://pawprint.vigilis.online/LibreKAT/Ocideck) or the
[GitHub mirror](https://github.com/brennodewinter/Ocideck) — before you trust it.

Because `SHA256SUMS` covers every file above, one verified signature over the
list anchors the whole release: tampering with any *listed* artifact breaks its
checksum, and the signed list is what vouches for those checksums. The macOS build
additionally carries an Apple notarisation attesting its publisher; for the
strongest guarantee on any platform, build from source — every artifact above
comes from a workflow in this repository that you can read, and `make
check-toolchain` pins the exact Flutter release used.

## What is in it

See [CHANGELOG.md](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/tag/@TAG@/CHANGELOG.md)
for the full list, and
[docs/USER_GUIDE.md](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/tag/@TAG@/docs/USER_GUIDE.md)
to get started. Both links point at this tag, not at `main`, so they keep
describing the version you just downloaded.

Licensed under the EUPL-1.2. Published by Stichting LibreKAT. Security
findings: <security@librekat.nl> — see
[SECURITY.md](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/tag/@TAG@/SECURITY.md).
