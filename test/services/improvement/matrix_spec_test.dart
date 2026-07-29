import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/matrix_spec.dart';

void main() {
  test('FMEA RPN is derived and never invented', () {
    final fmea = bundledImprovementTemplates.firstWhere((t) => t.id == 'fmea');
    expect(
      MatrixSpec.derivedRpn([
        'step',
        'fail',
        'effect',
        '7',
        'cause',
        '6',
        'ctrl',
        '5',
        '',
      ], fmea.columns),
      210,
    );
    expect(MatrixSpec.derivedRpn(['x'], fmea.columns), isNull);
  });

  test('bundled templates cover SIPOC and FMEA', () {
    expect(
      bundledImprovementTemplates.map((t) => t.id),
      containsAll(['sipoc', 'fmea', 'raci']),
    );
  });
}
