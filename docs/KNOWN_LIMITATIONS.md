# OciDeck — Known limitations

> **Status:** current-state list of what is not there yet · **Status last reviewed:** 2026-07-31 · **Published by:** Stichting LibreKAT

This page exists so you do not have to assemble it yourself. Every item below
was already written down somewhere in this repository; they were spread across
five documents, which meant a reader met them one surprise at a time. Nothing
here is new — the pointers say where the full account lives.

For an alpha, this list is a feature. Read it before you decide whether OciDeck
fits what you are doing.

## Releases are alpha and unsigned

Releases are tagged (latest `0.1.1`, 2026-07-27) and every release carries the
app for all four platforms — macOS, Windows, Linux and web — plus both SBOM
formats and a `SHA256SUMS` list. That list is itself signed with minisign
(`SHA256SUMS.minisig`, public key `minisign.pub` in the repository root), so the
checksum chain has a verifiable anchor — one signature over the list covers every
artifact it names (#1014). The macOS build is signed with a Developer ID
and notarised by Apple, so it opens normally; the **Windows and Linux builds are
unsigned**, so Windows warns on first launch. Windows ships two ways in — a
portable zip and an installer (#1208/#1583) — and *both* are unsigned, so the
installer additionally asks for elevation as "Unknown publisher"; neither
contacts a server or updates itself. The release notes explain how to open each
one. Building from source remains the route where you do not have
to trust our build machine — the toolchain is pinned, and `make check-web`
asserts on your bundle what we assert on ours. → [BUILD.md](BUILD.md),
[FAQ.md](FAQ.md#is-ocideck-free-to-use)

**Windows staying unsigned is a weighed decision, not an oversight** (#1013,
closed 2026-07-31). Authenticode signing was assessed and declined. Since March
2024 no certificate type — neither OV nor EV — grants instant SmartScreen trust:
reputation is earned only through download volume, so signing would not remove
the warning up front. And every paid route costs either a hardware token the
maintainer must hold or a signing secret living in the release runner, which the
project's least-privilege stance rules out. The minisign-signed `SHA256SUMS`
plus building from source stay the provenance guarantee — and that covers the
installer as much as the zip: it is fetched into the release before the manifest
is computed, so it is one of the files that signature names. If download volume ever turns the
SmartScreen warning into a real barrier, the fallback is an OV certificate signed
by hand on a local machine — the same manual model as the macOS notarisation —
never a secret in CI. Linux artifact signing is handled a level up — by the
minisign signature over `SHA256SUMS` (#1014) — so a per-binary certificate is not
needed there either. →
[BUILD.md](BUILD.md#signing-status-of-the-published-artifacts),
[SECURITY.md](../SECURITY.md#release-artifact-integrity-and-signing)

*(Corrected 2026-07-28: this section said "Nothing is released" and described a
scope decision where only a web bundle would ship. Releases have included all
four platforms since `0.1.0` on 2026-07-25. The signing and notarisation points
remain true — the Windows and Linux binaries are unsigned, macOS is notarised —
but the claim that no binary exists is stale.)*

## A presentation's exports are pictures, not documents

A **deck's** PDF and PPTX are one bitmap per slide: no text layer, no alt-text,
no reading order, no selectable text. Hand over the Markdown or the HTML export
when the recipient needs to *read* rather than *look*. No WCAG conformance is
claimed, and nothing has been tested with a real screen reader. →
[ACCESSIBILITY.md](ACCESSIBILITY.md)

*(Narrowed 2026-08-20: this holds for a presentation. A **document** exports to a
PDF that is typeset rather than photographed — real text, selectable, searchable
and readable aloud, with the headings as a bookmark tree. Its own limits are
below.)*

## A document's PDF falls back to source when a drawing cannot be made

Formulas, Mermaid diagrams and charts are **drawn** into the PDF as vector art.
Where that fails, the PDF prints the block's **source** in a monospaced box with
a line above saying what it is — rather than leave an empty space, whoever needs
the diagram at least sees what should be there. It happens in four cases: a
chart whose numbers live in an external `data/*.json` that did not travel; a
diagram or formula the renderer could not produce; a drawing the PDF's own SVG
reader cannot parse; and **Windows and Linux**, where the hidden renderer that
draws Mermaid and formulas has no implementation. Charts are drawn in Dart and do
travel on every platform. Export to HTML for all three rendered in a browser, or
to LaTeX for typeset maths. *(Added 2026-08-20; narrowed the same day from
"always shows source" once the drawings landed, and corrected again once the
platform limits were actually measured.)*

## Exporting a document does not work on the web build

Not the PDF and not the other three formats either. The browser file dialog
cannot be asked for a save location the way the desktop one can — it wants the
bytes up front — so the export reports that it did not succeed and leaves the
document untouched. It used to hang on a spinner instead, saying nothing. Making
it work would mean handing the finished bytes to the browser as a download; that
is a separate change. *(Added 2026-08-20.)*

## A document's PDF is set in a standard face, not in your document's font

The PDF picks a serif or a sans depending on which one the style profile uses,
but not the exact typeface — the same line the LaTeX export draws, which leaves
the font to the compiler. What travels is the structure and the page setup, not
the typography of the screen. Characters outside Latin-1 fall back to a bundled
font that covers Latin Extended, Greek and Cyrillic; anything beyond that (CJK,
Arabic, Hebrew) has no shape available. That is not silent: the export names the
characters it could not set and points at HTML or LaTeX, which handle them.
*(Added 2026-08-20.)*

## A raster logo can print grainy, and the PDF says so rather than fixing it

The style profile's logo goes into the PDF at the size the profile asks for. A
small PNG blown up to that size shows its own pixels on paper, and no export can
repair that — the file does not hold more image. What the export does instead is
say so after writing, naming the file's pixel size, the resolution it works out
to, and the width that would suffice (150 dpi where the logo lands). A vector
logo would sidestep this entirely, but only the HTML export renders one: the
document view on screen and the PDF both read raster images only, and an SVG
logo is left out of the PDF rather than breaking the export. *(Added 2026-08-21.)*

## Footnotes in the HTML export sit at the back, never at the foot of a page

A document can ask for its footnotes at the foot of the page the reference falls
on, and the **Pagina's** view and the **LaTeX** export do exactly that. The
single-file **HTML** export cannot: an HTML page is one continuous flow with no
pages in it, and the only standard that could place a note on a printed sheet —
`float: footnote` from CSS Paged Media — is implemented by no browser. The HTML
export therefore always puts the notes at the end of the document, numbered, with
a link to each note and back again. The numbers are the same ones as on screen,
so nothing is lost or renumbered; only the position differs. Printing that HTML
to PDF keeps them at the back, and so does the built-in **PDF** export: which
note lands on which sheet only becomes clear after the layout, and by then the
sheet is set. If you need notes truly at the foot of the sheet, use the LaTeX
(`.tex`) export. *(Added 2026-08-18; the built-in PDF export added 2026-08-20.)*

## A printed HTML document has no page numbers

Print the document-mode HTML export — or choose *Save as PDF* — and the style's
header and footer band repeat on every sheet, with the text below them, not
underneath them. The **page number** in that footer is the one part that stays
behind. A browser will not tell the page it is printing to the content on it:
`counter(page)` only resolves inside an `@page` margin box, which no browser
implements, and used to print a literal `0` on every sheet. Rather than print a
wrong number, the export prints none. On screen the document is one continuous
page and the number reads 1, which is true there. When the recipient needs
numbered pages, use the **LaTeX (`.tex`)** export, whose engine counts pages
itself. *(Added 2026-08-20.)*

## The web (HTML) export leaves off the on-slide overlays

The app draws a layer of chrome *over* each slide: the footer (its text,
position and the `N / total` page number), the logo, the diagonal
classification watermark, the per-slide TLP badge and the personal-data
(PrivacyKat) badge. The editor preview, the presenter and the **PDF/PPTX**
exports all draw that layer, because they render through OciDeck's own slide
renderer. The single-file **HTML** export reproduces only the logo among these:
it is laid on each slide that shows it as an embedded image, in the same corner
and size as in the app. The rest it leaves off — it embeds each slide's Markdown
for an in-browser renderer together with the theme's colours and font, and
carries the deck's classification as its own banner across the top of the
document instead of the per-slide badge. So a footer such as
`www.chateau-it.nl`, the page number, the watermark and the TLP/PrivacyKat
badges are simply absent from the `.html` — that overlay layer is a property of
OciDeck's rendering, not of the deck Markdown, and there is nothing in the
exported file to reproduce it from. When the recipient needs the footer or page
numbers in a shared file, hand over the **PDF** (or **PPTX**) export, which
keeps them. *(Added 2026-08-07 — the classification banner travels as a top
banner; the logo now travels on each slide too, since 2026-08-13; #1330.)*

## Importing a presentation is a conversion, not a copy

A PowerPoint, Keynote or Impress file can be imported, but OciDeck's slide model
is deliberately simpler than the sources': fixed layouts, one chart or one table
per slide, no free positioning. Animations, transitions, merged table cells,
audio and the source's own colours and fonts do not come across, and free-placed
text boxes are merged into reading order. What was dropped is written onto a
note slide beside the slide it came from rather than left for you to discover,
and no data is ever thinned out to make a slide fit — but you do have to check
the result. Keynote is the weakest of the three: its content is a binary format
whose meaning lives in Apple's application, so a `.key` that cannot be
reconstructed falls back to its preview image plus salvaged text.

Importing one file lets you decide per losing slide between carrying it over as
completely as possible, keeping only the pictures it already contained, and
skipping it with the note that says why; the queue for several files at once
does not ask and always carries everything over. Note what "keeping only the
pictures" is not: OciDeck cannot render a source slide to an image. That would
mean driving an external office suite, which the import deliberately does not
do, so a slide whose meaning lived in its layout cannot be preserved as a
picture of itself. *(Added 2026-07-24.)*

The "not converted" note slides and the import's error messages are written in
the user's own language and stored that way, since the note is content that
lives in the file (#806). One thing stays untranslated on purpose: the per-slide
progress line "Slide 3/10" shown while a file is being read. It is transient and
almost entirely a number, and localising it would need a separate progress seam;
the note content and the failure messages, which the user actually keeps or acts
on, are localised like the rest of the interface. *(Added 2026-07-24.)*

Separately: the importers have only ever been run against archives the test
suite builds itself. No file written by PowerPoint, Impress or Keynote has been
through them. → [USER_GUIDE.md](USER_GUIDE.md#importing-presentations-powerpoint-keynote-impress),
[design/VERIFICATION.md](design/VERIFICATION.md) item 11 *(added 2026-07-24)*

## Left-to-right only

The interface and the slide canvas are left-to-right. None of the 32 interface
languages is right-to-left, and no direction-sensitive layout primitives are in
use. This also governs your *content*: an Arabic or Hebrew paragraph on a slide
gets the wrong base direction. → [ACCESSIBILITY.md](ACCESSIBILITY.md)

## The translations have not been reviewed

Roughly 71,500 translations across 32 languages, produced during AI-assisted
development and never reviewed word by word by a native speaker. A build gate
catches a *missing* string, not a wrong one. Separately, about fifty field
labels in the slide editors and a handful of blocking messages still show their
Dutch source text whatever your language setting. →
[README.md](../README.md#contributing)

## The web build does less than the desktop build

No local video, no local CVE database, no WebDAV browsing, and a URL import that
the browser blocks on CORS grounds is retried through a proxy on the host that
served the app — so that host sees the address you typed. The first visit
downloads a large bundle. → [HOSTING.md](HOSTING.md), section *Web build
limitations to communicate*

## Marp CLI compatibility is unverified

The saved `.md` is designed to be processed by the Marp CLI and the VS Code Marp
extension. That has not been tested against the real tools — there is no Node
tooling in this repository and no test that runs one. →
[FILE_FORMAT.md](FILE_FORMAT.md)

## Much of it has never met a real server

A worklist of what is built, passes its own tests, and has never been exercised
against a real forge, a second operating system or a real report is kept
deliberately. It is in Dutch. →
[design/VERIFICATION.md](design/VERIFICATION.md)

## The privacy check is an aid, not a guarantee

It reduces the chance that personal data leaks out unintentionally. It does not
promise that everything is found, and image scanning cannot see what a
photograph is *of*. → [PRIVACY.md](PRIVACY.md),
[USER_GUIDE.md](USER_GUIDE.md#privacy-check)

## Screenshots are in the root README

*(Corrected 2026-07-28: this said "There are no screenshots" — the root
[`README.md`](../README.md) now carries screenshots of the editor, presenter,
charts, cockpit, timeline, quiz, TLP marking, dark mode, the privacy panel and
the export dialog, and `docs/images/` holds twelve images.)*

---

*This page replaces the roadmap section that used to sit in
[FAQ.md](FAQ.md) — a roadmap nobody maintains is worse than none. What is
planned is decided in the issue tracker, in the open.*
