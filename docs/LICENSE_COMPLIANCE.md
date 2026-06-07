# OciDeck — Open-Source Licence Compliance

OciDeck is released under the **EUPL-1.2** (see [`../LICENSE.md`](../LICENSE.md)).
This document records the policy that the project only includes open-source
software, how that is verified, and the result of the latest check.

## Policy

Every dependency and every bundled asset must be available under an OSI-approved
open-source licence. No proprietary or source-unavailable components are shipped.

Accepted licence families: **MIT, BSD (2-/3-Clause), Apache-2.0, MPL-2.0, ISC,
Zlib, BSL-1.0, Unlicense, SIL OFL-1.1, CC0** (and EUPL-1.2 for OciDeck itself).
Anything else — in particular GPL/AGPL/LGPL or a missing/unknown licence — is
flagged for review before it can be added.

## How to verify (repeatable)

A script scans the resolved package graph (direct **and** transitive) and
classifies each licence:

```sh
make licenses          # or: dart run tool/check_licenses.dart
```

It exits non-zero if any package has an unrecognised or non-open-source licence,
so it also runs as part of `make check-full` and can be wired into CI.

> The script reads each package's `LICENSE` file from `.dart_tool/package_config.json`,
> so run `flutter pub get` first. Re-run it whenever dependencies change.

Bundled (non-package) runtime assets — the JavaScript inlined into the HTML
export and the bundled font — are tracked by hand in
[`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

## Latest result

All **151** resolved packages use recognised open-source licences:

| Count | Licence |
| ---: | --- |
| 108 | BSD-3-Clause |
| 30 | MIT |
| 9 | Apache-2.0 |
| 1 | MPL-2.0 (`dbus`, Linux only) |
| 1 | BSD |
| 1 | BSL-1.0 |
| 1 | EUPL-1.2 (OciDeck itself) |

Bundled assets: marked (MIT), highlight.js (BSD-3-Clause), Mermaid (MIT, bundling
DOMPurify under Apache-2.0/MPL-2.0), MathJax (Apache-2.0), and the EB Garamond
font (SIL OFL-1.1, see `assets/fonts/OFL.txt`). The OciDeck-owned brand images in
`assets/images/` and the theme in `assets/themes/` are the project's own work.

**Conclusion: no non-open-source software is included.**

## A note on Apache-2.0 and the EUPL

A few components are Apache-2.0 (e.g. MathJax in the HTML export, and some Dart
packages). Using Apache-2.0 libraries as unmodified dependencies in an EUPL-1.2
work is fine. Note, however, that Apache-2.0 is **not** on the EUPL's list of
"compatible licences" (which governs the *outbound* relicensing of derivative
works under Article 5 EUPL). This only matters if you create a combined
derivative work that must be relicensed; it does not affect bundling these
libraries as-is. If you need formal certainty for a specific distribution
scenario, have it confirmed by someone with licence expertise.
