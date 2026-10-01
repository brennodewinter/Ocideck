import 'package:flutter_test/flutter_test.dart';

import '../tool/package_coverage.dart';

/// The coverage floor for packages/ (FORM_INTAKE.md §17). The root tool
/// (`coverage_summary.dart`) is tied to the app's `lib/`; a package gets this
/// small pure function instead, and each rule is checked loud on a planted
/// violation and silent on a clean report.
void main() {
  const root = '/work/ocideck/packages/demo';

  String record(String file, int found, int hit) =>
      'SF:$root/$file\nLF:$found\nLH:$hit\nend_of_record\n';

  const code = 'int f() => 1;\n';
  const barrel = '''
/// The public API.
library;

// A comment.
export 'src/a.dart';
export 'src/b.dart' show f;
''';

  List<String> run(
    String lcov,
    Map<String, String> sources, {
    double min = 90,
    int perFile = 60,
  }) => packageCoverageProblems(
    lcov: lcov,
    sources: sources,
    packageRoot: root,
    minPercent: min,
    perFileFloorPercent: perFile,
  );

  test('a covered package is clean', () {
    expect(
      run(record('lib/src/a.dart', 10, 10), {'lib/src/a.dart': code}),
      isEmpty,
    );
  });

  test('overall coverage below the floor fails and says by how much', () {
    final found = run(
      record('lib/src/a.dart', 10, 5) + record('lib/src/b.dart', 10, 10),
      {'lib/src/a.dart': code, 'lib/src/b.dart': code},
      perFile: 40,
    );
    expect(found.single, contains('75.0%'));
    expect(found.single, contains('90.0%'));
  });

  test('a lib file that no test imports is named, not averaged away', () {
    final found = run(record('lib/src/a.dart', 10, 10), {
      'lib/src/a.dart': code,
      'lib/src/forgotten.dart': code,
    });
    expect(found.single, contains('lib/src/forgotten.dart'));
    expect(found.single, contains('no test'));
  });

  test('a file under the per-file floor fails even in a high average', () {
    final found = run(
      record('lib/src/big.dart', 100, 100) + record('lib/src/thin.dart', 10, 3),
      {'lib/src/big.dart': code, 'lib/src/thin.dart': code},
      min: 90,
    );
    expect(found.single, contains('lib/src/thin.dart'));
    expect(found.single, contains('30%'));
  });

  test('the per-file floor is inclusive', () {
    expect(
      run(record('lib/src/a.dart', 10, 6) + record('lib/src/b.dart', 90, 90), {
        'lib/src/a.dart': code,
        'lib/src/b.dart': code,
      }),
      isEmpty,
    );
  });

  test('a barrel file with nothing to execute is not "in no test"', () {
    expect(
      run(record('lib/src/a.dart', 4, 4), {
        'lib/pkg.dart': barrel,
        'lib/src/a.dart': code,
      }),
      isEmpty,
    );
  });

  test('a file with real code is not mistaken for a barrel', () {
    final found = run(record('lib/src/a.dart', 4, 4), {
      'lib/src/a.dart': code,
      'lib/src/hidden.dart': "export 'a.dart';\nint g() => 2;\n",
    });
    expect(found.single, contains('lib/src/hidden.dart'));
  });

  test('a package with only barrel files has nothing to measure', () {
    expect(run('', {'lib/pkg.dart': barrel}), isEmpty);
  });

  test('a package with code and an empty report fails', () {
    final found = run('', {'lib/src/a.dart': code});
    expect(found, isNotEmpty);
  });

  test('a stale report entry for a file that is gone does not count', () {
    expect(
      run(
        record('lib/src/a.dart', 10, 10) + record('lib/src/old.dart', 50, 0),
        {'lib/src/a.dart': code},
      ),
      isEmpty,
    );
  });

  test('coverage exactly at the floor passes', () {
    expect(
      run(record('lib/src/a.dart', 100, 90), {'lib/src/a.dart': code}),
      isEmpty,
    );
  });

  test('windows-style paths in the report and the root are normalised', () {
    expect(
      packageCoverageProblems(
        lcov:
            'SF:C:\\work\\demo\\lib\\src\\a.dart\nLF:2\nLH:2\nend_of_record\n',
        sources: {'lib/src/a.dart': code},
        packageRoot: 'C:\\work\\demo',
        minPercent: 90,
        perFileFloorPercent: 60,
      ),
      isEmpty,
    );
  });
}
