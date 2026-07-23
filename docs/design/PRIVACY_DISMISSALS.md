# Setting one privacy finding aside — design

*Design for #651. Written 23-07-2026, before any code, because the answer lands
in a sidecar and this project settles a format question first.*

**Status: proposal.** Nothing here is built. One question is still open (§8).

---

## 1. What is actually missing

The issue that started this says a privacy finding offers exactly one action —
*"Never report this rule again"*, a global switch. **That is not quite what the
code does**, and the difference matters for what should be built.

Three levers exist today:

| Lever | Scope | Where it lives |
|---|---|---|
| `PrivacyDisposition` on the **deck** | every finding in the deck | `ocideck_privacy` in the front matter |
| `PrivacyDisposition` on a **slide** | every finding on that slide | `ocideck_privacy` on the slide |
| *"Never report this rule again"* | that rule, in **every deck**, forever | user settings (`setPrivacyRuleEnabled`) |

So a per-deck, per-slide judgement already exists: `accept` on a slide says
"everything the scanner finds here belongs here", and it does not touch other
slides or other decks.

The real gap is **inside one slide**. A slide with two findings — a colleague's
name that belongs on it, and an address that does not — offers only
all-or-nothing. Accepting the slide silences the address too, and that is the
loud, irreversible response the issue rightly objects to. Turning off the rule
globally is worse again.

**What is missing is one notch finer than a slide, not a whole new axis.** That
is a smaller feature than the issue implies, and it changes where the state
belongs.

## 2. The decision already taken

**Per deck, not per user** (decided by the maintainer, 23-07-2026, #651).

A dismissal is a judgement about *this* deck's content. It should travel with
the deck: to another machine, to a second reviewer, into the `.ocideck` package.
In user preferences it stays behind, and then the second reviewer sees the
finding again — or worse, a *different* deck has a finding suppressed because a
span happened to hash the same.

That settles deck-versus-user. It leaves one question this document answers:
**where in the deck.**

## 3. Where it lives: a sidecar

`<name>.privacy-dismissals.json`, beside the `.md`, joining the four sidecars
that are already there (`FILE_FORMAT.md` §6).

The alternative was a slide-level key in the front matter, next to the
`ocideck_privacy` token that already sits there. Rejected, for the reason that
retired seven front-matter keys in 0.1.0: **the `.md` stays maximally
interchangeable and human-readable.** A disposition is one word (`accept`) and
reads fine in a text editor. A dismissal is a rule id plus an opaque salted
commitment plus a timestamp, per entry — the base64-shaped noise that argument
was about. It is *about* the document, not part of it.

Consequence: this is a file-format addition, hence this document.

## 4. What one dismissal is

```json
{
  "version": 1,
  "dismissals": [
    {"rule": "nl.bsn", "slide": "s-3f9a", "anchor": "…", "at": "2026-07-23T09:12:33.000Z"},
    {"rule": "email", "slide": "s-3f9a", "anchor": "…", "at": "2026-07-23T09:13:01.000Z", "undone": true}
  ]
}
```

- **`rule`** — the scanner rule id, the same one the global switch uses.
- **`slide`** — the slide id, so a dismissal cannot leak to another slide.
- **`anchor`** — a **salted commitment** over the matched span. Never the raw
  value: the matched span *is* the personal data, and a bare hash of a name is a
  dictionary lookup away from the name. The redaction manifest already computes
  salted commitments for exactly this reason; reuse that, do not invent a second
  scheme.
- **`at`** — when, so the undo list can be ordered and a stale dismissal is
  recognisable.
- **`undone`** — the tombstone; see §6.

### 4.1 What happens when the text changes

The anchor commits to the matched span. Edit the span and the commitment no
longer matches, so **the dismissal falls away and the finding comes back**.

That is deliberate and it is the safe direction: a dismissal is a judgement
about *this* text, and changed text has not been judged. It is also not a new
idea — the user-notes codec already anchors on a content fingerprint and already
drops a note whose slide was rewritten (`GIT_STORAGE.md` D7). Same rule, same
reasoning, one fewer concept to learn.

Editing *elsewhere* on the slide leaves the dismissal standing: the anchor is
over the span, not over the slide.

## 5. What a dismissal does, and does not do

- **The panel hides it.** That is the whole point.
- **The scanner keeps finding it.** `privacyRawScanProvider` is untouched. The
  MIAUW compliance count (EIS 1.1) and the export summary read the raw scan, so
  the number of findings in the deck does not change because somebody looked
  away. #613 already separated those two readings; this rides on that split.
- **For the export gate it counts as handled**, exactly like a slide on
  `accept`. This is a decision and not an oversight: the gate asks "is there
  anything the author has not looked at yet", and a dismissal is the author
  looking at it. A dismissal that did *not* satisfy the gate would leave the
  author with a permanently blocked export and no way forward but the global
  switch — the very outcome this feature exists to avoid.
- **It is not a redaction.** Nothing is removed from the markdown or the export.
  `PrivacyProjection` runs its own scan and ignores this file entirely, the same
  way it already ignores dispositions.

## 6. Undo, and why the file needs a tombstone

A dismissal you cannot find again is a deletion. So: a list of what was set
aside, with an undo.

Undo could remove the entry. It must not, and the reason is one this project has
already paid for twice:

- **Git.** Two people on two branches, both setting things aside on the same
  deck. A plain union merge brings back an entry the other side undid — the
  ink-layer problem exactly (`GIT_STORAGE.md` D7), which is why ink got a
  tombstone. Same shape, same answer.
- **"Never losing content" must not become "nothing can go away."** That
  sentence is in D7 for the ink layer; it applies unchanged here.

So undo writes `"undone": true` and keeps the entry. The reader treats an
undone dismissal as absent. Entries are never rewritten, only appended and
marked.

**Written one entry per line**, like the user-notes sidecar. Single-line JSON
makes every edit a same-line collision and quietly breaks the text merge; that
was measured in #541 and corrected there.

## 7. What it costs

| | |
|---|---|
| Format | New sidecar, `version: 1`, `FILE_FORMAT.md` §6.7 |
| Read path | Unknown version → **ignore the file and report everything**. Failing to read a dismissal must never hide a finding |
| Travel | `.ocideck` package, bin, autosave/recovery snapshot — same list as the other sidecars |
| Git | Union + tombstone; one entry per line so the ordinary text merge works |
| UI | A second action on the finding card, plus a "set aside" list with undo |
| l10n | ~4 new strings × 31 languages |
| Tests | Anchor stability under edits, tombstone survives a merge, raw count unchanged, gate treats it as handled |

Not urgent: #608 removed the case that made this hurt on first run.

## 8. The one still open

**OQ-1 — does a dismissal survive a *rule* change?** The anchor commits to the
matched span, not to why it matched. Tighten a rule so it no longer fires on
that span and the dismissal is simply never consulted — fine. But *widen* a rule
so it now matches a longer span, and the anchor misses: the finding returns and
the author sets it aside again.

That is the safe direction and it needs no code. It is written down because the
alternative (anchoring on the rule's version too) would make dismissals expire
on every catalogue refresh, and somebody will propose it. The answer is that
they should not: a re-appearing finding costs one click, a silently kept
dismissal over changed matching costs a leak.

Confirm or reject before building.
