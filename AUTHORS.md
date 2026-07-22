# Authors

OciDeck was initiated and conceived by:

- **Brenno de Winter** ([biography](https://nl.wikipedia.org/wiki/Brenno_de_Winter)) — initiator and originator

It is developed as an open-source project and published by **Stichting
LibreKAT**, which is also the legal person to address about it — see
[`COMPLIANCE.md`](COMPLIANCE.md) for the registered details and
[`SECURITY.md`](SECURITY.md) for the reporting route. *(Moved here from
`README.md` on 2026-07-22: the front page identified the natural person in full,
including an external biography this project does not control, while the legal
entity that carries the liability stayed vague. That asymmetry invited people to
knock on the wrong door.)*

Copyright in the foundation's own contributions is held by Stichting
LibreKAT; contributors retain copyright in theirs, licensed under EUPL-1.2.
*(Corrected 2026-07-22: this said copyright "is held by Stichting LibreKAT"
without qualification, which is true today only because every commit so far
has one author, and would become false the moment a first outside pull request
landed. There is no CLA and no sign-off requirement, so the foundation has no
instrument that would make the unqualified sentence true — see the open issue
on adopting a DCO.)*

The name is a wink: *Oci* comes from the **Ocicats** (Brenno's cats) and *Deck*
is short for a presentation deck.

## Contributors

Thanks to everyone who has contributed code, translations, documentation, bug
reports, and ideas. (Add yourself here in your first pull request.)

### About the machine

**Roughly two thirds of the commits in this repository have an AI co-author.**
Measured 2026-07-22, late: **1,539 of 2,321 commits (66%)** carry a
`Co-Authored-By:` trailer naming Claude. For `lib/l10n/translations/` it is
**296 of 323**. The share is what matters, not the digits — it moved by a
hundred commits in a single day of work, and the numbers above will be stale
before this sentence is old. So check it yourself rather than trusting them:

```sh
git log --format=%B | grep -ci "co-authored-by:.*claude"
git log --oneline | wc -l
```

`git log --format=%an` shows exactly one human author, and that is the point
worth being precise about: **one named person reviewed and merged every one of
those commits and is accountable for the result.** The trailer records who
helped write a change, not who is answerable for it. What stood in for peer
review — and where it falls short of four eyes — is set out under *Who reviews
this, and who does not* in [`CONTRIBUTING.md`](CONTRIBUTING.md).

This is written down because the trailer is in the public history and anyone can
count it on their first day. A project that documents its own drift with dated
correction notes throughout would be judged harshly for the one number it left
implicit. *(Added 2026-07-22.)*

---

OciDeck also stands on the shoulders of open-source software; see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the components it builds on.
