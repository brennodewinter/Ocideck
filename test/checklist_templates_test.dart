import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/checklist_template.dart';
import 'package:ocideck/services/checklist_templates.dart';
import 'package:ocideck/services/wstg_catalog.dart';

void main() {
  test('wstgChecklistSource carries the full bundled WSTG list', () {
    final s = wstgChecklistSource();
    expect(s.standardLabel, WstgCatalog.instance.standardLabel);
    expect(s.rows.length, WstgCatalog.instance.tests.length);
    expect(s.rows.first.id, 'WSTG-INFO-01');
  });

  test('templateChecklistSource maps a template to rows', () {
    final s = templateChecklistSource(
      const ChecklistTemplate(
        name: 'Eigen',
        standardLabel: 'PTES intern',
        items: [ChecklistTemplateItem(id: 'A', title: 'Test A')],
      ),
    );
    expect(s.label, 'Eigen');
    expect(s.standardLabel, 'PTES intern');
    expect(s.rows.single.id, 'A');
    expect(s.rows.single.test, 'Test A');
  });

  test('checklistSources lists WSTG first, then the custom templates', () {
    final list = checklistSources(const [ChecklistTemplate(name: 'X')]);
    expect(list, hasLength(2));
    expect(list.first.label, WstgCatalog.instance.standardLabel);
    expect(list[1].label, 'X');
  });
}
