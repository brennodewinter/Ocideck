## Summary

<!-- What does this change do, and why? Link any related issue (e.g. "Closes #123"). -->

## Changes

<!-- Bullet the notable changes. -->

-

## Checklist

- [ ] Every commit is **signed off** (`git commit -s`) per the
      [DCO](../dco.txt), with my real name and a reachable email.
- [ ] `make check` passes (format-check, analyze, full test suite).
- [ ] Added/updated tests for the behaviour I changed. **If this fixes a bug,
      the test is on the reported behaviour and was red once against the
      unfixed code** — or I explained in the summary why a test cannot prove
      anything here and what gate covers it instead.
- [ ] New UI strings go through `context.l10n.d('…')` **and** are translated in
      every supported language. Use `make add-l10n SPEC=…`; the authoritative
      set is `AppLocalizations.languageNames`, not a list written down here.
      **Not the maintainer?** Supply Dutch and English, leave the other 30
      blank, and say so below — the maintainer fills them in before merge.
- [ ] If I changed how anything is stored, I updated
      [`docs/FILE_FORMAT.md`](../docs/FILE_FORMAT.md).
- [ ] Docs updated where relevant (README / docs/).
- [ ] If this touches the file format, storage, a dependency, outgoing network
      traffic, or a promise made in the UI or the docs — I described the
      trade-off in the summary: which principle I gave precedence, why, and
      what would change my mind.
- [ ] **Threat model still holds.** If this change touches any of — a new or
      changed interface, the authentication/trust model, newly handled sensitive
      data, a major dependency or supplier swap, the update/distribution path, or
      a large architectural change — I re-read
      [`docs/SECURITY_DESIGN.md`](../docs/SECURITY_DESIGN.md) (§Threat model) and
      [`assurance/risicoafweging.md`](../assurance/risicoafweging.md) and either
      confirmed they still hold or updated them. (No gate enforces this: whether
      the model was genuinely revisited cannot be checked mechanically.)

## Notes for reviewers

<!-- Anything that needs extra attention, screenshots, or manual test steps
(e.g. dual-screen presenting or drawing, which need real hardware). -->
