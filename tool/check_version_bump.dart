// Guards the version bump in pubspec.yaml against accidental leaps.
//
// The version was once bumped 0.2.0 → 1.2.1 in a single release commit, and
// the tag that fired the whole release chain went out before anyone noticed
// (a released 1.2.1 that was meant to be 0.2.2). A jump like that is never a
// deliberate release step: a real bump moves exactly ONE semver axis and zeroes
// the ones below it. This gate refuses anything else.
//
// From a released X.Y.Z the only legal next versions are:
//
//   * patch  X.Y.(Z+1)   — bug-fix release
//   * minor  X.(Y+1).0   — feature release, patch reset to 0
//   * major  (X+1).0.0   — breaking release, minor and patch reset to 0
//
// So from 0.2.0 the gate allows 0.2.1, 0.3.0 or 1.0.0 — and rejects 1.2.1,
// which carries the old minor/patch across a major bump (the tell of a typo or
// a stray find-replace, not a release).
//
// The baseline is the last released version reachable from HEAD
// (`git describe --tags --abbrev=0`, matched against `v*`). When the version in
// pubspec equals that baseline there is no bump in progress and the gate is a
// no-op — normal development and feature branches never trip it; it fires only
// on the commit that actually changes the version.
//
// **A pre-release tag is not a release**, and the baseline skips it. The repo
// cuts test tags like `v0.4.7-rc1` to exercise one build lane without
// releasing anything — that tag says so in its own message ("Geen echte
// release"). Reading it as a released 0.4.7 made the gate fail on every branch
// on the machine that held it: pubspec still said 0.4.6, which from an
// imagined 0.4.7 looks like an illegal downgrade. A tag like that need not be
// on a remote to do this; `git describe` reads whatever the local clone has,
// so one release rehearsal poisons every branch on that machine until someone
// deletes the tag. That is a false alarm on the very gate whose job is to make
// a real one credible, and it fires on branches that never touched the version
// at all. SemVer agrees: a pre-release ranks *below* the release it precedes,
// so `v0.4.7-rc1` can never be the last released version.
//
// A deliberate, human-authored exception (say, a one-time correction that goes
// back down past a bad release) goes in [sanctionedTransitions]. That is the
// whole point: an accidental bump has no entry there and fails; a conscious one
// is written down, in the diff, with a reason. It is empty by default.
//
// Runs in the per-PR static gate (`make check-static`). When no tag is
// reachable (a shallow scratch clone, or git absent) it cannot know the
// baseline, so it prints a note and passes rather than fail on a machine that
// simply lacks the history — the release runner and a normal clone both have
// the tags.

import 'dart:io';

/// A parsed `X.Y.Z` semantic version. Build metadata (`+6`) and any
/// pre-release suffix are dropped before parsing — the gate reasons about the
/// release number, not the build.
class SemVer {
  const SemVer(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Parses the `X.Y.Z` core of [raw], ignoring a `+build` or `-prerelease`
  /// suffix. Returns null when the core is not three integers.
  static SemVer? tryParse(String raw) {
    final core = raw.split('+').first.split('-').first.trim();
    final parts = core.split('.');
    if (parts.length != 3) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0) return null;
      nums.add(n);
    }
    return SemVer(nums[0], nums[1], nums[2]);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// The three canonical single-step increments from [from]: patch, minor
/// (patch→0) and major (minor→0, patch→0). Nothing else is a legal release
/// step. Public and free of I/O so the regression test can pin the rule
/// directly.
Set<String> legalNextVersions(SemVer from) => {
  '${from.major}.${from.minor}.${from.patch + 1}',
  '${from.major}.${from.minor + 1}.0',
  '${from.major + 1}.0.0',
};

/// Whether moving from [from] to [to] is a legal version transition: either no
/// change at all, or exactly one of the canonical increments.
bool isLegalTransition(SemVer from, String to) =>
    to == from.toString() || legalNextVersions(from).contains(to);

/// Deliberately sanctioned transitions that the canonical rule forbids, as
/// `from->to`. Each needs a comment saying why. This is the escape hatch for a
/// conscious correction (say, undoing an accidental bump by going back down) —
/// never for a routine bump.
///
///   * `1.2.1->0.3.0` — the accidental `v1.2.1` release of 2026-08-03 is
///     abandoned; the project deliberately returns below 1.0 and continues its
///     0.x line at 0.3.0. A one-time downgrade past a version that briefly
///     existed. From 0.3.0 onward the canonical rule applies again unaided.
const Set<String> sanctionedTransitions = {'1.2.1->0.3.0'};

/// Reads the `version:` line from pubspec.yaml at [path], returning the raw
/// value (with any `+build` suffix). Throws when the field is missing.
String readPubspecVersion(String path) {
  for (final line in File(path).readAsLinesSync()) {
    final m = RegExp(r'^version:\s*(\S+)').firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  throw StateError('No `version:` field in $path');
}

/// The last released version reachable from HEAD, or null when git has no
/// matching tag (or is unavailable). Strips the leading `v`.
///
/// `--exclude '*-*'` drops every pre-release tag (`v0.4.7-rc1`, `v1.0.0-beta`):
/// a hyphen after the version core is exactly SemVer's pre-release marker, and
/// a pre-release is not a release. Without it a test tag becomes the baseline
/// and the gate fails on a tree whose version nobody touched — see the header.
///
/// [workingDirectory] exists for the regression test, which builds a throwaway
/// repository with both a release and a pre-release tag. The glob lives in an
/// argument list, so nothing short of a real `git describe` can prove it works.
String? lastReleasedVersion({String? workingDirectory}) {
  try {
    final r = Process.runSync('git', [
      'describe',
      '--tags',
      '--abbrev=0',
      '--match',
      'v*',
      '--exclude',
      '*-*',
    ], workingDirectory: workingDirectory);
    if (r.exitCode != 0) return null;
    final tag = (r.stdout as String).trim();
    if (!tag.startsWith('v')) return null;
    return tag.substring(1);
  } on ProcessException {
    return null;
  }
}

void main(List<String> args) {
  const pubspecPath = 'pubspec.yaml';
  final rawVersion = readPubspecVersion(pubspecPath);
  final current = SemVer.tryParse(rawVersion);
  if (current == null) {
    stderr.writeln(
      'check-version-bump: pubspec version "$rawVersion" is not a valid '
      'X.Y.Z semantic version.',
    );
    exit(1);
  }

  final baselineRaw = lastReleasedVersion();
  if (baselineRaw == null) {
    stdout.writeln(
      'check-version-bump: no release tag reachable — cannot determine the '
      'baseline, skipping (a shallow clone or a repo without tags). The '
      'release runner and a full clone validate this.',
    );
    return;
  }

  final baseline = SemVer.tryParse(baselineRaw);
  if (baseline == null) {
    stdout.writeln(
      'check-version-bump: last tag "$baselineRaw" is not a valid version, '
      'skipping.',
    );
    return;
  }

  final to = current.toString();
  final transition = '$baseline->$to';

  if (isLegalTransition(baseline, to)) {
    stdout.writeln('check-version-bump: OK ($baseline → $to).');
    return;
  }

  if (sanctionedTransitions.contains(transition)) {
    stdout.writeln(
      'check-version-bump: OK — sanctioned exception $transition (see '
      'tool/check_version_bump.dart).',
    );
    return;
  }

  final allowed = (legalNextVersions(baseline).toList()..sort()).join(', ');
  stderr
    ..writeln('check-version-bump: illegal version bump.')
    ..writeln('  last release : $baseline (git describe)')
    ..writeln('  pubspec now  : $to')
    ..writeln('')
    ..writeln('A release moves exactly one semver axis and zeroes the ones')
    ..writeln('below it. From $baseline the only legal next versions are:')
    ..writeln('  $allowed')
    ..writeln('')
    ..writeln('Fix the version in pubspec.yaml (and kOciDeckVersion in')
    ..writeln(
      'lib/services/export_metadata.dart — see version_consistency_test).',
    )
    ..writeln('For a deliberate, one-off exception, add "$transition" to')
    ..writeln(
      'sanctionedTransitions in tool/check_version_bump.dart with a reason.',
    );
  exit(1);
}
