OciDeck @VERSIE@ — a presentation tool where the content, not the canvas, is
the document. Decks are Marp Markdown: plain text you can read, diff and keep.

**Try it without installing:** <https://ocideck.librekat.nl/> runs this same
version in your browser. Your deck stays in the tab; nothing is uploaded.

## Downloads

| Platform | File |
| --- | --- |
| macOS (Apple Silicon + Intel) | `ocideck-macos-@VERSIE@.zip` |
| Windows (x64) | `ocideck-windows-x64-@VERSIE@.zip` |
| Linux (x64) | `ocideck-linux-x64-@VERSIE@.tar.gz` |
| Web bundle (self-hosting) | `ocideck-web-@VERSIE@.tar.gz` |

Also attached: the Software Bill of Materials in CycloneDX
(`ocideck-@VERSIE@.cdx.json`) and SPDX (`ocideck-@VERSIE@.spdx.json`), and
`SHA256SUMS` over every file above.

## Opening the download on each platform

The macOS build is signed and notarised; Windows and Linux are not, so those two
warn on first launch. Verify the checksum below, then:

**macOS.** Signed with a Developer ID and notarised by Apple — it opens with a
normal double-click, no workaround needed. (Check with `spctl -a -t exec
OciDeck.app`: it reports `source=Notarized Developer ID`.)

**Windows.** SmartScreen shows "Windows protected your PC". Choose **More
info**, then **Run anyway**.

**Linux.** Unpack and run `./ocideck`. The bundle needs GTK 3 and
`libsecret-1`; on Debian/Ubuntu: `sudo apt install libgtk-3-0 libsecret-1-0`.

## Verifying what you downloaded

```
sha256sum --ignore-missing -c SHA256SUMS
```

(macOS: `shasum -a 256 -c SHA256SUMS --ignore-missing`.)

`SHA256SUMS` tells you that you have the bytes that were published here. It is
**not** a signature: on its own it proves nothing about who published them. The
macOS build additionally carries an Apple notarisation, which does attest the
publisher; for Windows and Linux, if you need that guarantee, build from source
— every artifact above comes from a workflow in this repository that you can
read, and `make check-toolchain` pins the exact Flutter release used.

## What is in it

See [CHANGELOG.md](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/tag/@TAG@/CHANGELOG.md)
for the full list, and
[docs/USER_GUIDE.md](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/tag/@TAG@/docs/USER_GUIDE.md)
to get started. Both links point at this tag, not at `main`, so they keep
describing the version you just downloaded.

Licensed under the EUPL-1.2. Published by Stichting LibreKAT. Security
findings: <security@librekat.nl> — see
[SECURITY.md](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/tag/@TAG@/SECURITY.md).
