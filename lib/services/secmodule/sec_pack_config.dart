// Compiled-in pin + distribution config for the Informatieveiligheid module
// data pack (PENTEST_MIAUW.md §6).
//
// The pack is cut at app-release time and CONTENT-ADDRESSED: the app fetches it
// across an ordered mirror list and accepts whichever host returns bytes that
// hash to exactly [secPackSha256]. That is what keeps the module from depending
// on a single repo — pawprint/Forgejo is merely mirror #1; any host serving the
// matching bytes is equivalent.
//
// The values below pin the baseline pack produced by
// `dart run tool/build_secmodule_pack.dart`. It carries the real
// CWE/WSTG/CVSS/MIAUW datasets. Regenerate the pack and re-pin [secPackSha256]
// here in the same commit when the datasets change, exactly like
// assets/web_export/MANIFEST.json is re-pinned when a bundle is upgraded.
library;

/// The baseline pack version this app build expects. Cache is keyed by this, so
/// bumping it re-provisions.
const secPackVersion = '2026.07.1';

/// The bundled baseline pack, shipped as an app asset (pubspec.yaml → assets/
/// secmodule/) so the module provisions offline with no mirror and no outbound
/// traffic: the provisioner loads these bytes and verifies them against
/// [secPackSha256] exactly like a manual import. Kept in step with
/// [secPackVersion] and rebuilt by tool/build_secmodule_pack.dart.
const secPackAssetKey = 'assets/secmodule/secmodule_pack_$secPackVersion.zip';

/// Outer sha256 (lowercase hex) of the baseline pack, compiled into the app.
/// Integrity is hash-only for now; a detached signature is a later phase (see
/// PENTEST_MIAUW.md §14 open question 2).
const secPackSha256 =
    'f34e44f874c7874ea4394176d4232c5c8139396425857c377ae7145512d76717';

/// Generous upper bound on the fetched/imported pack size, refused before any
/// unpack (mirrors the import byte-caps elsewhere).
const secPackMaxBytes = 8 * 1024 * 1024;

/// Ordered mirror URLs. The provisioner tries them in order and accepts the
/// first whose bytes match [secPackSha256].
///
/// SKELETON STATUS: no live host serves the pack yet (deferred — see
/// PENTEST_MIAUW.md §14 open question 1). These are placeholders showing the
/// intended shape; provisioning therefore falls through to a manual local
/// import until a real mirror is stood up. pawprint/Forgejo is merely mirror #1.
const secPackMirrors = <String>[
  'https://pawprint.dewinter.com/librekat/ocideck/releases/download/'
      'secmodule-$secPackVersion/secmodule_pack_$secPackVersion.zip',
];
