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

**The app's own colours, and the bar it applies to your slides.** *(Audit
completed 2026-07-23, #606; first measured 2026-07-22.)* OciDeck measures the
contrast of your deck against WCAG AA and reports what falls short, so its own
interface had better hold to that. It did not, and the fix turned out to be less
about recolouring than about telling two things apart.

**The split is chrome versus content, not light versus dark.** Text you read *in
the app* follows the app's appearance. Ink that lands *on a slide* does not — it
cannot, because a slide has to render identically in the on-screen preview and
in a headless export isolate where the appearance setting does not exist. A
theme-following colour there would produce two different PDFs of one deck
(PENTEST_MIAUW §11).

So each of the roughly two hundred uses was read as one or the other:

- **Interface text and icons moved to mode-aware tokens.** `accent`
  (`#2563EB`), `navy` (`#1C2B47`) and `teal` (`#2E7D64`), plus the red and green
  of the severity and status palettes, were painting text in dialogs, editors,
  panels and the shell — where on a dark surface the blue reaches 3.3:1 and the
  navy all but disappears. They now use `accentFg`, `brandFg`, `tealFg`,
  `dangerFg` and `successFg`, each of which meets 4.5:1 in the mode it paints.
- **The fixed colours themselves did not change.** They still fill surfaces,
  draw borders, paint gradients and render inside slides. The golden tests
  confirm it: every slide renders byte-identically to before.

**And the measurement was wrong, which flattered nobody.** The first pass
measured every fixed token against `AppTheme.paper` — the *interface* surface —
and recorded seventeen dark-mode failures. But a finding's severity colour is
read on a **slide**, which is white. Measured against the surface it is actually
on, and at the bar that actually applies:

- fourteen tokens are slide **text** (checklist, scope and scorecard status
  labels) — all clear 4.5:1 on white;
- two are never text at all. `severityHigh` (`#EA580C`) and `severityMedium`
  (`#D97706`) appear as a 6% tint behind a finding's header card, as the border
  stripe beside it, and as the fill of a badge whose label is white, bold and
  about 30px on a 1280-wide slide. For a graphical object (WCAG 1.4.11) and for
  large text (1.4.3) the bar is 3:1, and they clear it at 3.6 and 3.2.

So there is **no contrast baseline left** — not because the debt was written
off, but because most of it was a category error and the rest is fixed. Saying
that plainly matters more than the number: a baseline that records debt which
does not exist makes the entries that do exist unbelievable.

**And the rule cuts the other way too, which the visual review caught.** The
slide previews painted their greys with the *mode-aware* slate scale — on a
canvas that stays white. In dark mode `slate700` came out at **1.3:1** and
`slate500` at 2.1:1, so the text of a checklist, a scope matrix and a findings
summary all but vanished. That is the plainest form of the thing this document
is about: the app failing, on the user's own slides, the bar it applies to them.

Worse than unreadable, it **diverged from the export**. The HTML export runs
without a theme and always writes the light values; the export dialog promises
that the export uses exactly what the editor shows. In dark mode that was
untrue. Slide previews now use fixed ink (`slideInk`, `slideInkMuted`,
`slideInkSoft`, …) — the same values, no longer moving.

`test/app_theme_contrast_test.dart` now checks seven things, and the guards are
what keep this from being a one-off: the mode-aware tokens meet 4.5:1 in both
modes; the slide text tokens meet 4.5:1 on white; the two accent tokens meet
3:1; the slide ink is identical in both modes; and two source checks reject
**a fixed brand or severity colour used as text outside slide-rendering code**
and **a mode-aware grey used inside a slide preview**. Those two read the
source, so the next `AppTheme.navy` in a dialog — or `AppTheme.slate600` on a
slide — fails the build instead of quietly returning.

*Three smaller things the visual review turned up, now fixed: the export
dialog had been migrated on its success branch but not its failure branch, so
"the export failed" sat at 3.1:1 in dark mode while "exported to…" shone; the
user-notes heading was a fixed blue that had become weaker (2.4:1) than its own
subtitle beneath it; and `dangerFg`'s light value was pale enough that on the
scorecard chip — which tints its own background — it dropped to 4.2:1, under
AA, for the one colour that means alarm.*

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
