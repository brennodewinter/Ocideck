# OciDeck — Rotating a picture without changing it

*The one operation in the image dialog that edits the user's file. What it would
take to stop, and the three shapes that could replace it.*

> **Status:** decided 2026-08-30 — **Option A**, not yet built · **Status last reviewed:** 2026-08-30 · **Published by:** Stichting LibreKAT

> **This is a design doc, not shipping behaviour.** What ships today is described
> under [§2](#2-what-happens-today) and, since 2026-08-30, warned about in the
> dialog itself. When a decision lands, [`FILE_FORMAT.md`](../FILE_FORMAT.md),
> [`USER_GUIDE.md`](../USER_GUIDE.md) and the
> [`CHANGELOG.md`](../../CHANGELOG.md) carry the truth.

> Origin: found while checking `USER_GUIDE.md` against the code on 2026-08-30
> (PR #1870). The guide claimed the dialog "never rewrites the image file"; the
> rotate buttons do. The documentation is corrected — this document is about the
> behaviour.

---

## 1. The question

Can rotation become a stored value in the `.md`, the way the crop already is, so
the source file is left alone?

**Short answer: yes, and there are two ways to get there — one of which needs no
format change at all.** The rest of this document is the evidence, the cost per
surface, and the decisions that are the owner's rather than the implementer's.

---

## 2. What happens today

Verified 2026-08-30 against `origin/main` @ `3bfcd3a67`, in
`lib/widgets/slides/image_crop_dialog.dart`.

The dialog offers three operations that look alike and are not:

| Operation | Where the result is stored | Touches the file? |
|---|---|---|
| **Drag** (focal point) | `imageFocalX` / `imageFocalY` on the slide → `<!-- ocideck_image_focus: x,y -->` | no |
| **Zoom** (slider) | `imageZoom` on the slide → `<!-- ocideck_image_zoom: N -->` | no |
| **Linksom / Rechtsom** | nowhere — baked into the pixels | **yes** |

`_rotate(int quarterTurns)` decodes the bytes, calls `img.copyRotate`, and
re-encodes in the source format. `_writeRotatedBytes()` writes those bytes back
over the original path when the author presses **Klaar**; **Annuleren** does not
write. `_canRotate` excludes bundled assets and URLs, so this only ever touches
a file the user owns.

Three consequences, none of them visible from the dialog:

1. **The original is gone.** There is no undo, and no copy is kept. For a photo
   the author did not shoot themselves, that is the only copy they had.
2. **It changes everywhere at once.** One image file can back several slides and
   several decks, and OciDeck actively pushes in that direction: the image
   picker's *find duplicates* action (`ImageDedupService` +
   `image_carousel_picker_actions.dart`) counts how many slides across the decks
   on disk point at each copy and consolidates onto the most-referenced file.
   The more that tool is used, the further an in-place rotation reaches — and
   rotating in deck A rotates it in deck B.
3. **A write failure is swallowed** by design (a full disk must not block the
   crop). That is why "rotating does nothing" survived two releases on Windows;
   `lastRotationWriteFailure` exists solely so a test can see the cause.

### Why it is like this

Not an oversight. The importers face the same problem from the other side and
solve it the same way: `bakeImportGeometry` in `lib/utils/image_resize.dart`
bakes PPTX/ODP/Keynote rotation, flips and crops into the pixels, *because the
OciDeck format carries no geometry for an image beyond focal point and zoom*. The
standalone `rotateImageBytes` was removed when that landed. Baking is the
established convention; the crop dialog follows it.

That convention is sound for the importers — a source deck can rotate a picture
by 7°, and no quarter-turn field can express that. It does not follow that the
*editor's* quarter-turn button must bake too.

---

## 3. Why it is worth changing

LibreKAT value 3, sovereignty: **the user's work must not change silently.** A
deck is a description of how to show pictures; the pictures are the user's own
files and OciDeck is a reader of them everywhere else. This is the one place the
editor writes to a file the user did not ask it to write to.

Value 1 puts safety first, and safety here points the same way: the failure is
silent, unrecoverable, and reaches files outside the deck being edited.

It is also the one asymmetry in the dialog that a user cannot deduce. Drag, zoom
and rotate sit in one box, in one visual style, behind one **Klaar** button. Two
of the three are promises about a slide; the third is an edit to disk.

---

## 4. Option A — copy on rotate *(no format change)*

**Rotate writes a new file and points the slide at it. The original is never
touched.**

`photo.jpg` rotated a quarter turn becomes a sibling asset (say
`photo.r90.jpg`); the slide's `imagePath` moves to it. Other slides and other
decks still reference `photo.jpg` and are unaffected.

**What this costs**

- The write path in `image_crop_dialog.dart`: instead of overwriting `resolved`,
  allocate a new asset path and return it to the caller alongside
  `ImageCropResult`. The five editors that open the dialog set `imagePath` from
  it.
- Rotating twice must replace the derived copy rather than chain from it, or a
  deck accumulates `photo.r90.r90.jpg`. Track "this asset is a rotation of that
  one" for the lifetime of the dialog and re-derive from the original each time —
  the dialog already holds `_originalBytes` and a cumulative
  `_rotationQuarterTurns`, so this is nearly free.
- On the web build the same thing happens in `WebAssetStore` with a new
  `mem:` key instead of `replace()` on the existing one.
- Asset cleanup and the package budget: the deck now carries two near-identical
  pictures where it carried one. The *find duplicates* action will not merge
  them — it compares md5, and the bytes genuinely differ.

**What it does not cost**: nothing in the format, nothing in any export route,
nothing in the collaboration layer, nothing in the callout geometry. The pixels
still carry the rotation, so every surface that draws an image keeps working
unchanged.

**What it does not solve**: rotation is still a property of a *file*, so two
slides cannot show the same picture at two different angles. Nobody has asked
for that.

---

## 5. Option B — a stored quarter-turn field *(format change)*

**A `imageRotation` value beside `imageFocalX`/`imageZoom`, applied at draw
time.** The file is never written at all.

### 5.1 Where it would live

`<!-- ocideck_image_rotation: 90 -->`, and `…_rotation2` for the second image of
a two-images slide — the same carrier and the same "written only when not
default" rule as the existing focus and zoom comments (FILE_FORMAT §8). Values
`90`, `180`, `270`; absent means none.

### 5.2 The one clean insertion point

`lib/services/image_viewport_geometry.dart` — the Flutter-free geometry contract
from #1825 — is already the single place that turns *(intrinsic size, slot size,
focal, zoom)* into a painted rectangle, and the single place that maps a callout
target from image space into slot pixels. Flutter, LaTeX, the editor's
hit-testing and the quality analyser all call it, and the CSS surface is held
against it by a shared vector table (§4.2).

Rotation belongs there, and it is small:

- **Painted rectangle** — for an odd quarter turn, swap `imageW` and `imageH` on
  the way in. The cover/zoom maths is untouched.
- **Target mapping** — a stored target must be turned into display space before
  the existing mapping runs. For a clockwise quarter turn *q*, a point *(x, y)*
  becomes:

  | *q* | point | region *(x, y, w, h)* |
  |---|---|---|
  | 90° | `(1-y, x)` | `(1-y-h, x, h, w)` |
  | 180° | `(1-x, 1-y)` | `(1-x-w, 1-y-h, w, h)` |
  | 270° | `(y, 1-x)` | `(y, 1-x-w, h, w)` |

  (Checked by hand against the corners: at 90° the stored top-left `(0,0)` must
  land top-right `(1,0)`, and `(1-0, 0)` does.)

Every consumer of the contract then inherits rotation — including the callout
markers, which is the part that would be easy to get wrong if rotation were
bolted onto each surface separately.

### 5.3 What each surface still needs

| Surface | Work |
|---|---|
| Flutter previews, presenter, beamer, thumbnails | a `RotatedBox` around the image; the contract supplies the geometry |
| **PDF, PPTX, ODP** | none — they raster through the same Flutter renderer |
| HTML export | `transform: rotate()` on the imgslot plus swapped `--iw`/`--ih` (`marp_html_service_css.dart` §130) |
| LaTeX/Beamer | `\includegraphics[angle=…]`, and the callout rail maths follows the contract |

### 5.4 What makes this the expensive option

- **It is a format change, and this repo requires a design round with the owner
  before code** for exactly that reason: a released format cannot be taken back.
  Hence this document rather than a patch.
- **A new field on an existing slide type touches roughly eighteen places** —
  model, serialiser, parser, collab codec, collab diff, `deck_op`, and the
  `check-collab-field-parity` gate, which fails until the field is either in
  `SlideField` (syncs on edit) or in `deliberatelyNotSynced` with a written
  reason.
- **An older reader loses it.** A slide-level HTML comment is skipped by a 0.x
  reader and *not written back on save*, so a deck that round-trips through an
  older OciDeck comes back un-rotated. The existing `ocideck_image_focus` and
  `ocideck_image_zoom` carry exactly the same exposure today, so this is not a
  new class of risk — but it is a real one, and the only *guaranteed* carrier
  across readers is an unknown front-matter key with a nested block
  (FILE_FORMAT §3.0), which is what the callout format chose.
- **EXIF is already in play.** `img.decodeImage` bakes the EXIF orientation into
  the pixels and clears the tag, and Flutter honours EXIF when it decodes. "The
  intrinsic size" therefore already means the EXIF-corrected size; a stored
  rotation composes on top of that and must not try to re-read the tag. See the
  import geometry rules for the trap.

---

## 6. Option C — keep baking, and say so

**Shipped 2026-08-30**, as the interim: the dialog now states, above the rotate
buttons and before anything is clicked, that rotating changes the image file
itself unlike cropping and zooming, and that a picture used by other slides or
decks turns there too.

This does not make the behaviour right. It makes it *known*, which is the
minimum a user needs to decide for themselves — and it is the only part of this
document that required no decision from the owner.

---

## 7. Decision

**The owner chose Option A on 2026-08-30.** Rotation writes a derived copy and
leaves the user's file alone; the format is not touched. §7.1 is the values
argument that was put to them, §7.2 the trade against B, and §8 the two
follow-on choices that came with the decision.

### 7.1 The values, weighed

The bewaker questions, applied to the three options.

**Sovereignty (value 3) is the whole reason this document exists**, and it
separates the options cleanly: A and B both stop OciDeck writing over a file the
user owns; C does not, it only says so out loud.

**The conflict is interchangeability against the richer model, and it decides
against B — for now.** B keeps the picture untouched *and* makes rotation a
property of the slide, which is the better model. But it puts the rotation in
the `.md` as a slide-level comment, and a slide-level comment is dropped by any
reader that does not know it — including an older OciDeck, which will not write
it back on save. A deck that visits an older reader comes back un-rotated, and
nothing reports it. Option A has no such exposure: the rotation is in the
pixels, so every Marp tool, every OciDeck version and every export shows the
picture the way the author left it.

The house rule is to look for the form in which the function still fits plain
Markdown rather than to extend the format. **Option A is that form** — it needs
no new syntax at all, because "which picture does this slide point at" is
already expressible.

None of the three touches storage, a dependency, or outbound traffic.

### 7.2 Why A rather than B

**Option A** removes the actual harm — an unrecoverable edit to a file the user
owns, propagating to decks they are not looking at — for a change confined to one
dialog and five call sites, with no format change, no migration, no export work
and no old-reader exposure. After it, nothing OciDeck does writes over the user's
picture.

**Option B is the better model and the worse trade right now.** It is where this
belongs eventually — rotation is a display decision, and display decisions live
in the deck. But it buys, over and above A, only the ability to show one picture
at two angles on two slides, and nobody has asked for that. It costs a format
change, an eighteen-place field, three export surfaces and an old-reader gap.

**What would reopen it.** If someone asks to show one picture at two angles on
two slides, A cannot do it and B must be taken — *after* A, not instead of it,
and with a front-matter block rather than a slide comment as the carrier. A
leaves the file untouched, which is the property that matters, and B can then
replace the copy with a field without any user-visible regression.

---

## 8. What the decision settled

1. **Option A**, as above. C's warning stays in place until A ships, and stays
   afterwards in the reduced form the behaviour then warrants.
2. **The derived copy lands in the deck's own `images/` folder**, not beside the
   original. A deck project already has that layout — `asset_staging.dart` stages
   media into `images/` and `media/`, and `copyImagesToProject` lifts it into the
   project on save — so a rotated copy is an ordinary deck asset that travels in
   the package and the git plane like any other. Writing it next to the source
   would put an OciDeck artefact in the user's own photo folder, which is the
   sovereignty problem again in a smaller shape.
3. **Chained rotations re-derive from the original**, not from the previous copy,
   so a second quarter turn produces `…r180` and never `…r90.r90`.

---

## 9. Open, not decided here

- Whether rotating should offer "apply to every slide using this picture". Under
  A that becomes a real choice rather than the silent default it is today.
- Whether the swallowed write failure (§2) should surface to the user. Under A
  a failed write no longer destroys anything, which lowers the stakes but does
  not answer it.
- Flips. The importers read them; the editor offers none, and nobody has asked.
