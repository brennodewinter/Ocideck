import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the desktop release archives from turning back into "tarbombs" — an
/// archive that, when unpacked, spills its files straight into the current
/// directory instead of a single top-level folder (issue #904).
///
/// The real archives only exist after a `v*` tag is built, so no `flutter test`
/// ever sees them. What we *can* pin, offline and deterministically, is the
/// packaging step in the two release workflows: assert it names a versioned
/// directory `ocideck-<versie>/` as the archive root, and that the old
/// spill-in-place forms are gone.
///
/// Scope is deliberate, matching the assessment on #904:
///
///   * Linux `.tar.gz` and Windows `.zip` — what a person downloads and unpacks
///     by hand. Both are fixed and guarded here.
///   * macOS `.zip` — already single-rooted, because `ditto --keepParent` keeps
///     the `.app` bundle as the sole top-level entry. Guarded so a future edit
///     can't quietly drop `--keepParent` and reintroduce the spill.
///   * Web `.tar.gz` — a deploy artifact extracted server-side into a target
///     directory; a top-level folder buys nothing there. Left as-is, and so
///     the negative checks below are scoped to the desktop archive names only.
void main() {
  const forgejoRelease = '.forgejo/workflows/release.yml';
  const githubRelease = '.github/workflows/release.yml';

  final forgejoYaml = File(forgejoRelease).readAsStringSync();
  final githubYaml = File(githubRelease).readAsStringSync();

  test('Linux tarball is rooted in a versioned directory ($forgejoRelease)', () {
    // The spill-in-place form: tar the bundle's *contents* (a trailing bare
    // `.`) so `./ocideck`, `./lib/…` land in the unpack directory. This exact
    // token targets the Linux tarball only — the web tarball packs `.` too, on
    // purpose, and is out of scope.
    expect(
      forgejoYaml.contains('ocideck-linux-x64-\$VERSIE.tar.gz" .'),
      isFalse,
      reason:
          'Linux tarball packs the bundle contents directly — a tarbomb '
          '(#904). Rename the top-level path component to ocideck-<versie>/ '
          'instead.',
    );
    // The fix references the versioned directory as the archive root, either as
    // a --transform target (ocideck-<versie>,) or a staging dir (ocideck-<versie>/).
    expect(
      RegExp(r'ocideck-\$VERSIE[/,]').hasMatch(forgejoYaml),
      isTrue,
      reason:
          'Linux packaging step no longer names a versioned top-level '
          'directory ocideck-<versie> (#904).',
    );
  });

  test('Windows zip is rooted in a versioned directory ($githubRelease)', () {
    // The spill-in-place form: `7z a … some.zip ./*` from inside the Release
    // directory packs its contents with no top-level folder.
    expect(
      githubYaml.contains('ocideck-windows-x64-\$VERSIE.zip" ./*'),
      isFalse,
      reason:
          'Windows zip packs the Release contents directly — a tarbomb '
          '(#904). Stage the files under ocideck-<versie>/ before zipping.',
    );
    expect(
      RegExp(r'ocideck-\$VERSIE[/"]').hasMatch(githubYaml),
      isTrue,
      reason:
          'Windows packaging step no longer stages files under a versioned '
          'top-level directory ocideck-<versie> (#904).',
    );
  });

  test(
    'macOS zip keeps its .app as the single top-level entry ($forgejoRelease)',
    () {
      // A macOS .app is already a single directory; --keepParent is what keeps it
      // as the archive root rather than spilling its innards. Dropping that flag
      // would reintroduce the #904 spill on macOS too.
      expect(
        forgejoYaml.contains('ditto -c -k --keepParent'),
        isTrue,
        reason:
            'macOS packaging no longer uses `ditto --keepParent`, so the '
            '.zip may spill the .app contents (#904).',
      );
    },
  );
}
