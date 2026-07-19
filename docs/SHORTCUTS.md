# OciDeck — Keyboard shortcuts

`Ctrl` is shown for Windows/Linux; use `Cmd` (⌘) on macOS.

## Editor (app-wide)

| Shortcut | Action |
| --- | --- |
| `Ctrl/Cmd + K` | Open the command palette (searchable list of actions) |
| `Ctrl/Cmd + O` | Open a presentation |
| `Ctrl/Cmd + S` | Save the active deck |
| `Ctrl/Cmd + Z` | Undo |
| `Ctrl/Cmd + Shift + Z` | Redo |
| `Ctrl + Y` | Redo (alternative) |
| `Ctrl/Cmd + H` | Find & replace (visual mode: dialog; markdown mode: in-editor bar — see below) |
| `Ctrl/Cmd + V` (in a table cell) | Paste a spreadsheet/CSV/markdown selection as a table (also `Shift + Insert`) |
| `Tab` to the panel divider, then `←` / `→` | Resize the slide panel |

In the **add-slide dialog**, `Tab` moves between the type cards, `Enter` picks
the focused one, and `Esc` cancels.

## Markdown mode

When the editor is in **Markdown mode**, find & replace works on the live
markdown text (including front matter, slide separators, and HTML comments), not
on the last-applied slide fields.

| Shortcut | Action |
| --- | --- |
| `Ctrl/Cmd + F` | Open the find bar |
| `Ctrl/Cmd + H` | Open the find bar with replace |
| `Enter` / `Shift + Enter` (in find field) | Next / previous match |
| `Esc` | Close find bar |

The find bar also offers previous/next buttons, a match counter (`1 / 3`), a
case-sensitivity toggle, **Replace** (current match), and **Replace all**.

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

View & timing:

| Shortcut | Action |
| --- | --- |
| `P` | Toggle presenter view (notes, clock, countdown, per-slide timer, next slide) |
| `Ctrl/Cmd + N` | Toggle **my notes** panel (recipient/course notes; local only, never on beamer) |
| `S` | Move the presentation to another screen |
| `B` · `W` | Black · white screen |
| `K` | Set the target time / countdown (type `MMSS`, `Backspace` erases a digit, `Enter` to confirm, `0` = off) |
| `R` | Reset the time & rehearsal run (elapsed and per-slide timings; the target stays) |
| `A` | Auto-advance on/off |
| `L` | Loop (restart after the last slide) on/off |
| `M` | Advance automatically after a slide's audio finishes |
| `H` · `?` | Show the in-app shortcut cheatsheet |
| `Ctrl/Cmd + W` | Close the presentation (works from the presenter and the beamer window) |

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
