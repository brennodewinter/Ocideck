## Summary

<!-- What does this change do, and why? Link any related issue (e.g. "Closes #123"). -->

## Changes

<!-- Bullet the notable changes. -->

-

## Checklist

- [ ] `make check` passes (format-check, analyze, full test suite).
- [ ] Added/updated tests for the behaviour I changed. **If this fixes a bug,
      the test is on the reported behaviour and was red once against the
      unfixed code** — or I explained in the summary why a test cannot prove
      anything here and what gate covers it instead.
- [ ] New UI strings go through `context.l10n.d('…')` **and** are translated in
      every supported language. Use `make add-l10n SPEC=…`; the authoritative
      set is `AppLocalizations.languageNames`, not a list written down here.
- [ ] If I changed how anything is stored, I updated
      [`docs/FILE_FORMAT.md`](../docs/FILE_FORMAT.md).
- [ ] Docs updated where relevant (README / docs/).
- [ ] If this touches the file format, storage, a dependency, outgoing network
      traffic, or a promise made in the UI or the docs — I described the
      trade-off in the summary: which principle I gave precedence, why, and
      what would change my mind.

## Notes for reviewers

<!-- Anything that needs extra attention, screenshots, or manual test steps
(e.g. dual-screen presenting or drawing, which need real hardware). -->
