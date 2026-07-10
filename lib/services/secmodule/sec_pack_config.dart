// Compiled-in pin + distribution config for the Informatieveiligheid module
// data pack (PENTEST_MIAUW.md §6).
//
// The pack is cut at app-release time and CONTENT-ADDRESSED: the app fetches it
// across an ordered mirror list and accepts whichever host returns bytes that
// hash to exactly [secPackSha256]. That is what keeps the module from depending
// on a single repo — pawprint/Forgejo is merely mirror #1; any host serving the
// matching bytes is equivalent.
//
// SKELETON STATUS: the values below pin the placeholder baseline pack produced
// by `dart run tool/build_secmodule_pack.dart` (a minimal dataset, NOT the real
// CWE/WSTG/CVSS/MIAUW content). Regenerate that pack and re-pin [secPackSha256]
// here in the same commit when the real datasets land, exactly like
// assets/web_export/MANIFEST.json is re-pinned when a bundle is upgraded.
library;

/// The baseline pack version this app build expects. Cache is keyed by this, so
/// bumping it re-provisions.
const secPackVersion = '2026.07.0-skeleton';

/// Outer sha256 (lowercase hex) of the baseline pack, compiled into the app.
/// Integrity is hash-only for now; a detached signature is a later phase (see
/// PENTEST_MIAUW.md §14 open question 2).
const secPackSha256 =
    'a47d5f705bc28c5e920ce84092a1fe26a8c7f1531de09073d48623ecc5a9aead';

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
