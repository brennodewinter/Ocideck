<!--
SPDX-License-Identifier: EUPL-1.2
Copyright © 2026 Stichting LibreKAT

This file travels inside every built web bundle (tool/pack_web_release.dart).
It is the source indication EUPL-1.2 article 5 asks for when the Work is
distributed or communicated: what you have in front of you is compiled, and
this says where the thing it was compiled from lives.
-->

# Where this came from

You are looking at a **build** of OciDeck, not its source. `main.dart.js` is
compiled output — it is not the program as it was written, and it is not what
you would read or change.

| | |
| --- | --- |
| **Source repository** | <https://pawprint.vigilis.online/LibreKAT/Ocideck> |
| **Licence** | EUPL-1.2 — see `LICENSE.md` next to this file |
| **Version in this bundle** | see `version.json` next to this file |
| **Dependencies of this build** | see `sbom/` next to this file |
| **Published by** | Stichting LibreKAT |

The EUPL gives you the right to use, study, adapt and redistribute OciDeck.
Studying and adapting need the source, so this is not a formality: without a
route back to it, the licence above would grant you something you could not
actually do.

## Building it yourself

```sh
git clone https://pawprint.vigilis.online/LibreKAT/Ocideck.git
cd Ocideck
flutter pub get
make build-web        # output in build/web
```

`docs/BUILD.md` in the repository has the full account, including the pinned
Flutter version — the build is reproducible only against that toolchain.

**Building from source is not a lesser route.** It is the only one where you do
not have to trust our build machine: you compile the code you just read, with a
toolchain you chose to install. `make check-web` then asserts the same
properties on your bundle that we assert on ours.

## If you are redistributing this bundle

Keep this file, `LICENSE.md`, `THIRD_PARTY_NOTICES.md` and `sbom/` reachable
alongside it. Hosting the bundle is *communicating the Work* under EUPL article
1, which means article 5's source indication applies to you as well — and this
file is how you meet it. If you modified the bundle, point the repository line
above at **your** source, not ours.
