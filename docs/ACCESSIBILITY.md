# OciDeck — Accessibility

> **Status:** current-state description of what is and is not accessible · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

What OciDeck does for accessibility, and — the longer half of this document —
what it does not do. Both halves are here on purpose. A tool that only lists its
accessibility features leaves the reader to discover the gaps at the worst
possible moment, which is usually the moment the deck has already been sent.

The short version: **the editor is built to be usable with a keyboard and a
screen reader and to survive being scaled up; the exports are not accessible
documents.** PDF and PPTX come out of OciDeck as pictures.

## What is in place

**Text scaling up to 200%.** *Settings → General → Accessibility* scales all
interface text between 100% and 200%, on top of whatever the operating system
already asks for (`uiTextScale` in `AppSettings`). This is the WCAG 1.4.4
resize-text requirement. The slide canvas is deliberately excluded: a slide is a
fixed 16:9 design surface, so what you see stays what you present and export.
The documentation reader has its own **A− / A+** control on top of that, because
reading a guide and operating an editor want different sizes.

**Screen-reader labels where the interface is not text.** Slide thumbnails carry
a composed label ("Slide 3/12: <title>", plus skipped state, whether the slide is
withheld by its TLP classification and at which level, and whether it has notes)
rather than being announced as an unnamed image. Both reasons a slide will not
reach the audience are spoken, and spoken separately, because the dimming and the
two coloured flags that carry the same message on screen are of no use here. Charts expose their
data as a text alternative (`_semanticsLabel` in `chart_preview.dart`), so a
chart is readable and not merely present. Icon-only buttons carry a name.

**A test that fails the build.** `test/accessibility_labels_test.dart` walks the
interface and asserts that every button has an accessible name (WCAG 4.1.2). It
was written after an audit and immediately found three real defects — buttons
wrapped in a `Tooltip` widget instead of carrying `IconButton(tooltip:)`, which
attaches the name to the surrounding row rather than to the button. That test is
the reason this claim is a claim rather than a hope.

**Alt-text as a first-class field.** The image, two-images and bullets-with-image
editors have an **Alt-tekst** field separate from the visible caption. A screen
reader announces the alt-text when set, falls back to the caption, and then to a
generic "image"; the slide-quality check nudges until one of the two is present.
Alt-text is stored in the Markdown, so it survives a round trip.

**Slide-change announcements while presenting**, so a screen-reader user
following a presentation is told which slide is up.

**Keyboard operation of the parts that are easy to miss.** The panel divider
between the slide list and the editor takes focus with `Tab` and resizes with
`←`/`→`. The add-slide dialog is fully keyboard-operable, and tabbing between the
type cards also drives the explanation below the grid, so the keyboard reaches
the same information the mouse does. General navigation and the shortcuts are in
[SHORTCUTS.md](SHORTCUTS.md).

**Explanations attached to the control, not only beside it.** Each card in the
add-slide dialog carries its type's explanation as a screen-reader hint, because
the strip below the grid is a separate widget that a reader walking the cards
never passes. The same reasoning puts the save-progress message on the status-bar
chip as a live region: it is a statement about what is happening, so it is
announced without moving the focus to it.

**A menu bar on macOS.** `PlatformMenuBar` gives the system menu bar the app's
actions — file, edit (including cut/copy/paste), presentation, window and help.
A menu bar is a surface that can be walked end to end to find out what a program
can do, instead of hunting a toolbar for icons. Items that need an
open presentation grey out rather than disappearing, so the list a user learns
stays the same list. Windows and Linux get their menu from the desktop
environment; the browser build has none.

**Markings that do not rest on colour alone.** Where the app points at part of a
text, it pairs the colour with a shape. The correction after a typed question
answer strikes through what was there too much and underlines what was missing,
so the two lines still read apart for anyone who tells red and green apart
poorly. On an image-pair question the two pictures carry an **A**/**B** badge
that becomes a ✓ or ✗, rather than only a green or red border.

**Contrast checking of the deck you are making.** The slide-quality panel checks
body text, titles, table text and headers, code colours and the accent colour
against their backgrounds at WCAG 2.1 AA, and flags what fails. This helps the
*audience* of your deck rather than you — but it is the check most presentation
tools do not do at all.

## What is not in place

**PDF and PPTX exports are images.** This is the largest limitation in this
document and the one most likely to matter. `export_service.dart` renders each
slide to a bitmap and then wraps it: the PDF is one full-bleed `pw.Image` per
page, and the PPTX is one `<p:pic>` per slide. Consequences, stated plainly:

- there is **no text layer**, so nothing can be selected, searched, or read by a
  screen reader;
- there is **no alt-text** in the output, including for the images you carefully
  gave alt-text to in the editor;
- there is **no structure** — no headings, no reading order, no tags, no
  table semantics;
- a chart's data alternative, which the editor exposes, does not survive.

If the recipient needs an accessible document, the honest routes today are the
**Markdown** (which is text, keeps its headings and carries the alt-text) or the
**HTML export** (real text in a browser, though it was not built against WCAG
either). PPTX speaker notes are real text and do travel.

**The HTML export is not audited for accessibility.** It produces genuine text
and headings, which is already a great deal more than the bitmap formats, but
nobody has checked its colour contrast, focus order or landmark structure.

**Roughly fifty editor labels are not translated.** Field labels and hints in the
slide editors reach the localisation layer indirectly, so the translation gate
never sees them and they display their Dutch source text whatever language you
selected — 'Titel (H1)' and 'Aanbeveling' among them. For a user who does not
read Dutch this is an accessibility problem and not only a cosmetic one. A few
blocking messages (classification-policy refusals, the export-failure text) are
built in Dutch for the same reason.

**Left-to-right only, and that governs your content too.** No
direction-sensitive layout primitive is in use anywhere — `EdgeInsetsDirectional`,
`AlignmentDirectional` and `BorderDirectional` appear zero times in `lib/`,
against twenty-nine physical `EdgeInsets.only(left:`/`right:`. Of the thirteen
places that mention `TextDirection`, eleven hard-code `TextDirection.ltr`,
including a `Directionality` wrapper around the **entire slide canvas** in
`slide_preview.dart` (counted 2026-07-22).

That none of the 32 interface languages is right-to-left is a scope choice. The
sharper consequence is the canvas: an author who puts an Arabic or Hebrew
paragraph on a slide gets the wrong base direction — left-aligned, punctuation
on the wrong side — regardless of the interface language they chose. Nothing
warns them, so it is discovered on the projector. Nothing is being built for
this yet; it is written down here so it is a known limitation rather than a
surprise, and so the day someone wants RTL the starting point is already
mapped. *(Added 2026-07-22.)*

**Wider WCAG conformance is not claimed.** Contrast ratios inside the
*application interface*, focus order across the whole app, and reading order are
a programme of work rather than a test file. What exists is the guard rail above
and the defects it caught. OciDeck does not claim WCAG 2.1 conformance at any
level, has no accessibility conformance report, and has not been tested with
users of assistive technology.

**Not verified with real screen readers.** The labels are asserted through
Flutter's semantics tree in tests. Nobody has run OciDeck end to end under
VoiceOver, NVDA, JAWS or Orca, so "carries a semantic label" is proven and
"works well in practice" is not.

**The privacy check's image scan is unavailable on the web build**, which is a
capability gap rather than an accessibility one, but it lands in the same place:
see [PRIVACY.md](PRIVACY.md) and [HOSTING.md](HOSTING.md) §5.

**The interface and the slide canvas are left-to-right only.** None of the 32
interface languages is right-to-left, which is a scope choice. The sharper point
is that it also governs the *content*: `lib/widgets/slides/slide_preview.dart`
wraps the whole canvas in `Directionality(textDirection: TextDirection.ltr)`, so
an author who puts a Hebrew or Arabic paragraph on a slide gets the wrong base
direction — left-aligned, with punctuation on the wrong side. That affects
authors regardless of the language they read the interface in. There are also no
direction-aware layout primitives in use (`EdgeInsetsDirectional`,
`AlignmentDirectional` and `BorderDirectional` appear zero times in `lib/`,
against 29 physical `EdgeInsets.only(left|right`), so supporting RTL later is a
change to layout code and not a translation job. *(Added 2026-07-22: this was
true but written down nowhere, so it was something you discovered on the
projector.)*

## If you rely on this

- Author in the editor with text scaling turned up if you need it; the deck is
  unaffected by that setting.
- Fill in **Alt-tekst** for every image even though PDF and PPTX drop it — the
  Markdown keeps it, and that is where an accessible version would start.
- Hand over the **Markdown** or the **HTML** when the recipient needs to read
  rather than look.
- Report what does not work. The issue tracker is in
  [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md); an accessibility defect
  is an ordinary defect here, not a feature request.

---

*Written 2026-07-21, from the code rather than from intent. The README used to
summarise accessibility in a single line that mentioned keyboard operation and
screen-reader labels without mentioning that the two most-used export formats
carry neither; this document exists so that the limitation has somewhere to
live.*
