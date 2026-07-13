import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/checklist_template.dart';

void main() {
  const sample = ChecklistTemplate(
    name: 'Interne netwerktest',
    standardLabel: 'PTES intern',
    items: [
      ChecklistTemplateItem(
        id: 'NET-01',
        title: 'Poortscan',
        category: 'Recon',
      ),
      ChecklistTemplateItem(id: 'NET-02', title: 'Zwakke wachtwoorden'),
    ],
  );

  test('toJson/fromJson round-trips a template and its items', () {
    final back = ChecklistTemplate.fromJson(sample.toJson());
    expect(back.name, 'Interne netwerktest');
    expect(back.standardLabel, 'PTES intern');
    expect(back.items, hasLength(2));
    expect(back.items[0].id, 'NET-01');
    expect(back.items[0].category, 'Recon');
    expect(back.items[1].category, isEmpty);
  });

  test('encodeList/decodeList round-trips a list', () {
    final list = [sample, const ChecklistTemplate(name: 'Leeg')];
    final back = ChecklistTemplate.decodeList(
      ChecklistTemplate.encodeList(list),
    );
    expect(back, hasLength(2));
    expect(back[0].items, hasLength(2));
    expect(back[1].name, 'Leeg');
    expect(back[1].items, isEmpty);
  });

  test('decodeList is tolerant of junk and drops nameless templates', () {
    expect(ChecklistTemplate.decodeList(null), isEmpty);
    expect(ChecklistTemplate.decodeList(''), isEmpty);
    expect(ChecklistTemplate.decodeList('not json'), isEmpty);
    expect(ChecklistTemplate.decodeList('{"not":"a list"}'), isEmpty);
    // A template without a name cannot be selected, so it is dropped.
    expect(
      ChecklistTemplate.decodeList('[{"name":"","items":[]}]'),
      isEmpty,
    );
  });

  test('empty items are dropped on decode', () {
    final t = ChecklistTemplate.fromJson({
      'name': 'X',
      'items': [
        {'id': '', 'title': ''},
        {'id': 'A', 'title': 'Test A'},
      ],
    });
    expect(t.items, hasLength(1));
    expect(t.items.single.id, 'A');
  });
}
