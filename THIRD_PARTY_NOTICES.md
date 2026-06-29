# Third-Party Notices

OciDeck is licensed under the EUPL-1.2 (see [`LICENSE.md`](LICENSE.md)). It
builds on, and bundles, third-party components that remain under their own
licences. This file lists them; each component's full licence text is available
from its project or package page.

## Bundled runtime assets

Shipped inside the app and embedded into the **offline HTML export**
(`assets/web_export/`) and the UI:

| Component | Used for | Licence |
| --- | --- | --- |
| [marked](https://github.com/markedjs/marked) | Markdown → HTML in the export | MIT |
| [highlight.js](https://github.com/highlightjs/highlight.js) | Code highlighting in the export | BSD-3-Clause |
| [DOMPurify](https://github.com/cure53/DOMPurify) | Sanitises the rendered Markdown before it hits the DOM in the export | Apache-2.0 / MPL-2.0 |
| [Mermaid](https://github.com/mermaid-js/mermaid) | Diagrams in the export | MIT |
| [MathJax](https://github.com/mathjax/MathJax) (`tex-svg.js`) | Math rendering in the export | Apache-2.0 |
| [EB Garamond](https://github.com/octaviopardo/EBGaramond12) font | Bundled deck font | SIL Open Font License 1.1 |
| [Roboto](https://github.com/googlefonts/roboto-classic) font | Bundled UI font (replaces the runtime fetch from fonts.gstatic.com) | SIL Open Font License 1.1 |

The exact pinned version, source URL and SHA-256 of every vendored JS bundle
live in [`assets/web_export/MANIFEST.json`](assets/web_export/MANIFEST.json).
`make deps-check` verifies each file still matches that manifest and queries the
[OSV](https://osv.dev) database for known vulnerabilities.

## Vendored (forked) plugins

Kept in `third_party/` and wired in via `pubspec.yaml` (path dependency /
`dependency_overrides`). Both are forks of upstream plugins with local native
changes; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#vendored-forks).

| Component | Origin | Licence | Local changes |
| --- | --- | --- | --- |
| `desktop_multi_window` | [MixinNetwork/flutter-plugins](https://github.com/MixinNetwork/flutter-plugins) | MIT | Added native macOS window placement/fullscreen/close methods for the dual-screen presenter |
| `screen_retriever_macos` | [leanflutter/screen_retriever](https://github.com/leanflutter/screen_retriever) | MIT | Packaging fix for recent Xcode/CocoaPods |

## Dart & Flutter packages

Direct dependencies (see `pubspec.yaml` for exact version constraints). Each is
distributed under its own OSI-approved licence as published on
[pub.dev](https://pub.dev); most are MIT, BSD-3-Clause, or Apache-2.0.

- `flutter`, `flutter_localizations` (Flutter SDK — BSD-3-Clause)
- `flutter_riverpod`
- `file_picker`
- `path_provider`, `path`
- `uuid`
- `screen_retriever`, `window_manager`
- `shared_preferences`
- `pasteboard`
- `pdf`
- `archive`
- `video_player`
- `characters`
- `url_launcher`
- `desktop_drop`
- `image`
- `flutter_highlight`, `highlight`
- `flutter_math_fork`
- `wakelock_plus`
- `fl_chart`
- `cupertino_icons`

> To regenerate an authoritative, version-pinned licence inventory you can use a
> tool such as `flutter pub deps` together with a licence-collection package.

## Licence audit

A scan of all resolved Dart/Flutter packages (direct **and** transitive) and the
bundled assets found only OSI-approved open-source licences — MIT, BSD
(2-/3-Clause), Apache-2.0, MPL-2.0, and the SIL Open Font License 1.1. No
proprietary or source-unavailable components are included. (The only MPL-2.0
dependency is `dbus`, used on Linux.) Re-run such a scan after changing
dependencies.

Run it yourself with `make licenses` (or `dart run tool/check_licenses.dart`).
The policy, method, and latest result are documented in
[`docs/LICENSE_COMPLIANCE.md`](docs/LICENSE_COMPLIANCE.md).

