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

**A test that fails the build — and exactly how much of the app it sees.**
`test/accessibility_labels_test.dart` asserts that every button has an
accessible name (WCAG 4.1.2). It works two ways, and the difference matters:

- it **pumps six editors** (bullets, table, timeline, two-images, sign-off,
  video) and inspects the real semantics tree. That is six of the 26 editors,
  none of the 41 dialogs, and not presentation mode. Whatever it does not pump,
  it does not see;
- it **scans the source** of all of `lib/` for one specific mistake:
  `Tooltip(message: …, child: IconButton(…))`. That reads like a named button
  and is not one — a `Tooltip` around a button attaches no semantic label to it;
  only `IconButton(tooltip:)` does. This half is cheap and covers everything,
  including the code nobody pumps.

*Corrected 2026-07-22 (#586). This entry said the test "walks the interface" and
that it had found three defects. Both were too generous. It pumps six widgets,
and behind them the very fault it guards against stood **23 more times** —
seven in the main layout, four in the preview panel, four in the presenter
overlays including the button you press to leave a presentation, and the whole
three-button drawing toolbar. Someone using a screen reader heard "button" on
the exit control. The 23 are fixed and the source scan is what keeps the
twenty-fourth from arriving; but the honest summary of the coverage is the two
bullets above, not "walks the interface".*

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

**The app's own colours do not all meet the bar it applies to your slides.**
*(Added 2026-07-22, #606.)* OciDeck measures the contrast of your deck against
WCAG AA and reports what falls short — and its own interface did not hold to
that everywhere. Measured against the surface each mode actually paints on
(`AppTheme.paper`, white or `#181B21`), and counting only tokens the interface
uses as *text*:

- **dark mode: 17 tokens below 4.5:1.** The worst are the red used for a
  critical finding, a checklist anomaly and an unreachable scope object
  (`#B91C1C`, 2.67:1), the neutral grey for "no severity" (`#475569`, 2.28:1),
  and the green for a tested item (`#15803D`, 3.44:1);
- **light mode: 2 tokens below 4.5:1** — the orange and amber of the high and
  medium severity bands (`#EA580C` 3.6:1, `#D97706` 3.3:1). The issue that
  raised this measured dark mode only and treated light as fine; it is not.

The exact list lives in `test/app_theme_contrast_test.dart` as a ratchet, so the
number is in the repository rather than in a reviewer's notebook, and it can
only go down: the test fails both when a new token drops below the bar and when
one that has been fixed is left in the baseline.

Three call sites are corrected — the seal indicator in the status bar, the
asset-overview warning, and the error colour in the quality panel now use the
mode-aware `dangerFg`/`successFg` instead of the fixed `danger700`/`success700`.
The rest is not done. It is not a matter of flipping the tokens: the fixed ones
are fixed **on purpose**, because a finding must render identically in the
preview and in a headless export isolate, and a colour that moves with the app's
appearance would break that. So each of the roughly two hundred uses has to be
read as either slide content (leave it) or interface chrome (make it
mode-aware), and that audit is still open.

**A few blocking messages are still built in Dutch.** *(Rewritten 2026-07-22.)*
This entry used to say that roughly fifty editor labels showed their Dutch
source text. That is no longer true: those labels are translated, the gate now
fails on every violation rather than counting down to a ceiling, and the keys
that reach the layer indirectly are checked for coverage in every language.

What is left is narrower and structural. The translation layer is keyed on
literal Dutch source text, so a string that *interpolates* a value has no
literal to key on and cannot be looked up at all. A classification refusal names
the level in its own sentence, so it reaches you in Dutch whatever language you
chose. For someone who does not read Dutch that is an accessibility problem and
not a cosmetic one, and it is worst where it hurts most: these are the messages
that stop you from doing something. Tracked in #576.

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
