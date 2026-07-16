import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards what the Informatieveiligheid (MIAUW) module costs **every** user,
/// module on or off: a declared asset ships in the base build for everyone, so
/// the payload is a decision, not a side effect.
///
/// This exists because that decision was made in prose and lost. The design doc
/// promised "nothing pentest-related ships in the base app payload — not even
/// the small datasets", while both reference-data assets were declared
/// unconditionally and shipped to everyone. Nothing failed; the claim just
/// quietly stopped being true. Per `tool/check_conventions.dart`: *"Een afspraak
/// in een ontwerpdocument houdt geen data tegen; een compileerfout wel."*
///
/// So this test does not judge the payload — it pins it. Adding or removing a
/// reference-data asset is fine; doing it without touching this file is not.
/// When you change the expectations below, change the docs that describe the
/// payload in the same commit.
void main() {
  // Asset prefixes holding module reference data (as opposed to images, fonts,
  // themes or bundled docs, which are guarded elsewhere).
  const dataPrefixes = ['assets/cwe/', 'assets/secmodule/'];

  /// Every reference-data asset the base build currently declares. Deliberately
  /// exact: an unlisted entry here means someone grew the payload for all users
  /// without saying so.
  ///
  /// `assets/secmodule/` (the provisioned module pack) used to sit here too. It
  /// held a second copy of this very CWE dataset and nothing ever read it back,
  /// so it was 288 KB bought for one boolean — see the CHANGELOG entry for
  /// 2026-07-16.
  const expectedDataAssets = {'assets/cwe/cwe_full.json'};

  /// Ceiling for the unpacked bytes those assets add to every build. Headroom is
  /// for regenerating the datasets from upstream (CWE grows), not for adding new
  /// ones — a new dataset belongs in [expectedDataAssets], with this raised
  /// deliberately. Ratchet it **down** when the payload shrinks.
  const dataPayloadCeilingBytes = 260 * 1024;

  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// The `assets:` entries of the `flutter:` section, in declaration order.
  List<String> declaredAssets() {
    final lines = pubspec.split('\n');
    final start = lines.indexWhere((l) => l.trimRight() == '  assets:');
    expect(
      start,
      isNot(-1),
      reason: 'No `  assets:` block in pubspec.yaml — broken discovery scan.',
    );
    final out = <String>[];
    for (final line in lines.skip(start + 1)) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      // A key at the `flutter:` child level (e.g. `  fonts:`) ends the block.
      final entry = RegExp(r'^\s+-\s+(\S+)\s*$').firstMatch(line);
      if (entry == null) break;
      out.add(entry.group(1)!);
    }
    return out;
  }

  /// Bytes on disk for one asset entry: a file, or every file in a directory
  /// entry (Flutter bundles a trailing-slash entry's whole contents).
  int bytesFor(String entry) {
    if (entry.endsWith('/')) {
      final dir = Directory(entry);
      if (!dir.existsSync()) return 0;
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .fold(0, (sum, f) => sum + f.lengthSync());
    }
    final file = File(entry);
    return file.existsSync() ? file.lengthSync() : 0;
  }

  test('the base build declares exactly the known reference-data assets', () {
    final declared = declaredAssets()
        .where((a) => dataPrefixes.any(a.startsWith))
        .toSet();

    expect(
      declared,
      equals(expectedDataAssets),
      reason:
          'The reference-data payload of the base build changed. Every declared '
          'asset ships to every user, module enabled or not. If this is '
          'intended, update expectedDataAssets AND the docs describing the '
          'payload (docs/design/PENTEST_MIAUW.md §6, docs/ARCHITECTURE.md) in '
          'the same commit.',
    );
  });

  test('the reference-data payload stays under its ceiling', () {
    final total = expectedDataAssets.fold(0, (sum, e) => sum + bytesFor(e));

    // A declared-but-missing asset already fails the Flutter build, so reaching
    // zero here means the entry resolves to nothing on disk.
    expect(
      total,
      greaterThan(0),
      reason: 'Broken payload scan: nothing found.',
    );
    expect(
      total,
      lessThanOrEqualTo(dataPayloadCeilingBytes),
      reason:
          'Reference data now adds ${(total / 1024).round()} KB to every build, '
          'over the ${dataPayloadCeilingBytes ~/ 1024} KB ceiling. Raise the '
          'ceiling only as a deliberate, documented choice.',
    );
  });
}
