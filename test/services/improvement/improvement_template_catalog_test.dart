import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/improvement_template_catalog.dart';
import 'package:ocideck/services/improvement/matrix_spec.dart';

void main() {
  setUp(() {
    ImprovementTemplateCatalog.instance.resetForTest();
  });

  test('floor exposes the fourteen bundled artefact templates', () {
    final cat = ImprovementTemplateCatalog.instance;
    expect(cat.matrixTemplates.map((t) => t.id), ['fmea', 'raci', 'sipoc']);
    expect(cat.canvasTemplates, hasLength(5));
    expect(cat.treeTemplates, hasLength(3));
    expect(cat.flowTemplates, hasLength(3));
    expect(improvementTemplateById('sipoc'), isNotNull);
    expect(improvementTemplateById('unknown-house'), isNull);
  });

  test('FMEA still marks RPN as derived', () {
    final fmea = ImprovementTemplateCatalog.instance.matrixById('fmea')!;
    expect(fmea.columns.where((c) => c.derived).map((c) => c.key), ['rpn']);
    expect(fmea.storedColumns.map((c) => c.key), isNot(contains('rpn')));
  });

  test('loadJsonForTest replaces the floor', () {
    ImprovementTemplateCatalog.instance.loadJsonForTest(
      jsonEncode({
        'source': 'test',
        'version': '1',
        'templates': [
          {
            'id': 'kano',
            'engine': 'matrix',
            'phase': 'define',
            'label': {'nl': 'Kano', 'en': 'Kano'},
            'guidance': {'nl': 'x', 'en': 'x'},
            'columns': [
              {
                'key': 'need',
                'label': {'nl': 'Behoefte', 'en': 'Need'},
              },
            ],
          },
        ],
      }),
    );
    expect(
      ImprovementTemplateCatalog.instance.matrixTemplates.map((t) => t.id),
      ['kano'],
    );
  });
}
