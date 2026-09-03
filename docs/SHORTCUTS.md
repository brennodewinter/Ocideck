# OciDeck — Keyboard shortcuts

> **Status:** reference, current · **Status last reviewed:** 2026-08-30 · **Published by:** Stichting LibreKAT

`Ctrl` is shown for Windows/Linux; use `Cmd` (⌘) on macOS.

## Editor (app-wide)

| Shortcut | Action |
| --- | --- |
| `Ctrl/Cmd + K` | Open the command palette (searchable list of actions) |
| `Ctrl/Cmd + O` | Open a presentation (in the dialog: `Ctrl/Cmd`-click or `Shift`-click rows to open several at once) |
| `Ctrl/Cmd + W` | Close the active tab (asks first when it has unsaved work) |
| `Ctrl/Cmd + S` | Save the active tab — a presentation or a document (*corrected 2026-08-08: it saves a document too, in every mode, not only a deck*) |
| `Ctrl/Cmd + Z` | Undo |
| `Ctrl/Cmd + Shift + Z` | Redo |
| `Ctrl + Y` | Redo (alternative) |
| `Ctrl/Cmd + F` | Find (presentation: dialog in Visual, in-editor bar in Markdown; document: in-editor bar regardless of where the tab has focus) |
| `Ctrl/Cmd + H` | Find & replace (presentation: dialog in Visual, in-editor bar in Markdown; document: in-editor bar regardless of where the tab has focus) |
| `Ctrl/Cmd + V` (in a table cell) | Paste a spreadsheet/CSV/markdown selection as a table (also `Shift + Insert`) |
| `Ctrl/Cmd + +` · `Ctrl/Cmd + -` (document mode) | Zoom the writing surface in · out |
| `Ctrl/Cmd + 0` (document mode) | Back to actual size |
| `←` `→` (in a table cell) | Move the cursor through the cell text; at its edge, jump to the neighbouring cell |
| `↑` `↓` (in a table cell) | One row up · down, once the cursor is on the cell's first · last line |
| `Tab` to the panel divider, then `←` / `→` | Resize the slide panel |
| `←` `↑` `Page Up` · `→` `↓` `Page Down` (click the preview first) | Previous · next slide, stepping through the pages of a long rich-text slide or an overflowing finding before moving on |

*Added 2026-07-22: `Ctrl/Cmd + F` was bound app-wide but only listed under
Markdown mode, so in visual mode it looked as though there was no find key.*

*Added 2026-09-02: `Ctrl/Cmd + W` was bound app-wide since 0.5.0 but only
listed for the presenter, so closing a tab by keyboard was undocumented.*

The shortcuts in this table act on the editor behind whatever is in front of
it, so they do nothing while a dialog, the documentation reader or the
presentation screen is on top — press `Esc` first. Before 2026-09-02 they fired
straight through, and pressing `Ctrl/Cmd + O` twice in quick succession left two
"Open presentation" dialogs stacked on each other (#1927).

In the **add-slide dialog**, `Tab` moves between the type cards, `Enter` picks
the focused one, and `Esc` cancels. The card that has focus also drives the
explanation strip below the grid, so tabbing through the types reads out what
each one is for.

## macOS menu bar

On macOS the app carries a real menu bar. It is the only surface that shows what
OciDeck can do without knowing where to look, so it repeats the shortcuts above
rather than adding a second set. Two accelerators exist **only** there:
`Cmd + ,` for the settings and `Cmd + N` for a new tab. Windows and Linux get
their window menu from the desktop environment and the browser build has none, so
this bar is not built outside macOS.

| Menu | Items |
| --- | --- |
| **OciDeck** | About · Settings (`Cmd + ,`) · Hide, Hide others, Show all · Quit |
| **File** | New presentation (`Cmd + N`, opens a new tab on the welcome screen) · Open… (`Cmd + O`) · Save (`Cmd + S`) · Export · Properties |
| **Edit** | Undo (`Cmd + Z`) · Redo (`Cmd + Shift + Z`) · Cut, Copy, Paste, Select all (`Cmd + X/C/V/A`) · Find (`Cmd + F`) · Find & replace (`Cmd + H`) |
| **Presentation** | Present · Full-deck preview · Commands… (`Cmd + K`, the command palette) |
| **Window** | Minimise · Zoom · Toggle full screen |
| **Help** | User guide · Keyboard shortcuts |

Items that need an open presentation stay **visible but greyed out** when there
is none, and *Export*, *Undo* and *Redo* grey out when they have nothing to do.
Greying rather than hiding is deliberate: a menu item that comes and goes teaches
nobody what the app can do.

Cut, copy, paste and select all go to whatever field has focus, exactly as the
key combinations do. They are listed because this bar replaces the standard macOS
menu, and adding a menu bar must not take text editing away.

## Markdown mode

When the editor is in **Markdown mode**, find & replace works on the live
markdown text (including front matter, slide separators, and HTML comments), not
on the last-applied slide fields.

| Shortcut | Action |
| --- | --- |
| `Ctrl/Cmd + F` | Open the find bar |
| `Ctrl/Cmd + H` | Open the find bar with replace |
| `Ctrl/Cmd + B` | Make the selection bold |
| `Ctrl/Cmd + I` | Make the selection italic |
| `Ctrl/Cmd + K` | Insert a link around the selection |
| `Ctrl/Cmd + Space` | Open the searchable insert and formatting commands |
| `Tab` / `Shift + Tab` | Indent / outdent the selected source lines |
| `Enter` / `Shift + Enter` (in find field) | Next / previous match |
| `Esc` | Close find bar |

The find bar also offers previous/next buttons, a match counter (`1 / 3`), a
case-sensitivity toggle, **Replace** (current match), and **Replace all**. In the
source field itself, Enter continues a bullet, numbered list or quote; brackets
and parentheses pair automatically, and a third backtick opens a fenced block.

## Fullscreen presenter

Navigation:

| Shortcut | Action |
| --- | --- |
| `→` · `Space` · `Page Down` · click | Next slide |
| `←` · `Page Up` | Previous slide |
| `Enter` | Next slide (or jump, if a number was typed) |
| digits, then `Enter` | Jump to that slide number |
| `Backspace` | Erase the last digit of a typed slide number |
| `Home` · `End` | First · last slide |
| `G` | Slide-grid overview (arrows + `Enter` to jump) |
| `Tab` · `⇧Tab` | On a choice-menu slide: walk the categories and blocks |
| `Enter` · `Space` (with a block focused) | Follow that block's jump, or switch category |
| `Escape` (with a block focused) | Hand the keys back to the slide |

*Next* and *previous* first move **within** a slide that has more to show: the
pages of a rich-text body too long for one slide (the control bar then reads
`Slide 7 / 24 · Pagina 2 / 3`), and a timeline in step mode revealing its next
event. Stepping back into the previous slide lands on its last page. A question
slide holds *next* until it has been answered.

View & timing:

| Shortcut | Action |
| --- | --- |
| `P` | Toggle presenter view (notes, clock, countdown, per-slide timer, next slide) |
| `F` | Fix the quality problem on the current slide in place — split an overfull slide (the overflow becomes continuation pages) or cut multi-sentence bullets apart. Works single- and dual-screen; a redacted slide is left untouched, and a slide with nothing to fix shows a brief note |
| `N` · `Ctrl/Cmd + N` | Toggle **my notes** panel (recipient/course notes; local only, never on beamer). Inside the panel a bare `N` types a letter, so only `Ctrl/Cmd + N` (or `Esc`) closes it |
| `S` | Move the presentation to another screen |
| `B` · `W` | Black · white screen |
| `K` | Set the target time / countdown (type `MMSS`, `Backspace` erases a digit, `Enter` to confirm, `0` = off) |
| `R` | Reset the time & rehearsal run (elapsed and per-slide timings; the target stays) |
| `A` | Auto-advance on/off |
| `L` | Loop (restart after the last slide) on/off |
| `M` | Advance automatically after a slide's audio finishes |
| `+` · `-` | Zoom a Mermaid diagram on the current slide in · out (numpad `+`/`-` too). The keys do nothing on a slide without a zoomable diagram, and the zoom mirrors to the beamer *(listed 2026-08-30; the keys were there and undocumented)* |
| `H` · `?` | Show the in-app shortcut cheatsheet |
| `Ctrl/Cmd + W` | Close the presentation (works from the presenter and the beamer window) |

Every shortcut on this page works from **either** window in dual-screen mode: the
beamer window forwards the keys it does not handle itself to the presenter, so a
stray click on the beamer image no longer leaves the keyboard dead.

Typed-answer questions:

While a question of the kind **typed answer** is open and unanswered, the keys go
into the input field instead of to the shortcuts — otherwise a `3` in the answer
would jump to slide 3. Four keys are kept back:

| Shortcut | Action |
| --- | --- |
| `Enter` | Confirm the typed answer |
| `Page Up` · `Page Down` | Previous · next slide (so a presentation clicker keeps working) |
| `Esc` | Falls through to the normal layered `Esc` below — so it still exits the presentation from an open question |
| `Ctrl/Cmd + W` | Close the presentation |

The field lives on the **presenter** side; the beamer window shows what is being
typed but cannot be typed into. Once the answer has been given the keyboard goes
back to the normal shortcut set.

Annotation tools:

| Shortcut | Action |
| --- | --- |
| `D` | Pen |
| `T` | Highlighter |
| `E` | Toggle table editing — only on tables marked *editable while presenting* in the builder; otherwise acts as the eraser |
| `⇧E` | Eraser |
| `X` | Laser pointer |
| `C` | Clear the current slide's annotations |

Live table editing:

A table can only be edited during a presentation when it is marked **editable
while presenting** in the builder (a per-table checkbox; off by default). On such
slides a subtle pencil icon appears in the top-right corner — dimmed when off,
highlighted when on — that toggles editing with a mouse/clicker, just like `E`.

| Shortcut | Action |
| --- | --- |
| `E` · pencil icon | Toggle table editing |
| `←` · `→` · `↑` · `↓` | Move the text cursor inside the focused cell |
| `Tab` · `⇧Tab` | Move to the next · previous cell (a new row is added past the last cell) |
| `Esc` | Leave table editing |

`Esc` is layered: it first closes the **my notes** panel (`Ctrl/Cmd + N`), then
leaves table editing, then puts away the active annotation tool, then clears a
typed slide number, then removes a black/white screen, and finally exits the
presentation. `Ctrl/Cmd + W` closes the presentation straight away, from any
mode, mirroring how a window closes elsewhere in the system.

> In **dual-screen** mode (macOS, Windows, Linux) the keyboard stays with the
> laptop (presenter) window; clicks on the beamer also advance the slide.
> `Ctrl/Cmd + W` also works when the beamer window is focused — it asks the
> presenter window to close the presentation.
