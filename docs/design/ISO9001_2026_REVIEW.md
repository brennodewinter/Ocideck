# ISO 9001:2026 — edition review

> **Status:** decision, current · **Status last reviewed:** 2026-11-19 · **Published by:** Stichting LibreKAT

## Evidence and decision

[ISO published ISO 9001:2026](https://www.iso.org/standard/9001) on
16 September 2026. The release freshness check correctly reports that a newer
edition exists. ISO describes changes including separating risks and
opportunities and closer alignment with other management system standards.

OciDeck currently supports the **2015 clause index**: seven sections and
28 entries. It supplies factual identifiers and short titles, not the normative
text or a certification claim. The model and reference registry both label this
index as 2015. **Retain those labels and that index.** A public release
announcement establishes publication, but does not establish the complete new
clause index or how existing entries map to it. No verified clause-by-clause
comparison is available in the repository. Relabelling the existing data as
2026 would make existing progress reports misleading.

This is an explicit acceptance of the edition-freshness advisory, not a claim
that the 2015 edition is current and not an implementation of the 2026 edition.
The upstream warning remains enabled. The 2015 label remains visible in the
management system model and reference registry; no existing document is
silently reinterpreted. The advice printed by the check distinguishes an ISO
clause review from a detection-lexicon refresh.

## Conditions for adding the new edition

Before supporting 2026, review the official clause index through legitimate
access, record the identifier/title diff, and recheck ISO's reuse conditions.
Keep normative text out of the bundle. Treat edition as part of the stored
standard identity: existing reports must retain their 2015 meaning, and any
migration must explicitly handle split, added or removed clauses, evidence and
progress. Test import/export round trips and edition-specific progress totals.
Update the catalogue, reference registry and licence inventory together only
once that evidence and compatibility policy exist.

Review this decision when that verified index and mapping are available, or
when edition-specific migration work begins. The assessment in
[issue #3014](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3014) is
complete with this documented decision; the edition migration itself has not
been performed.
