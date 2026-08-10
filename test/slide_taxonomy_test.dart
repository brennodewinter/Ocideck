import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';

void main() {
  test('de publieke slide-taxonomie houdt haar opgeslagen waarden', () {
    expect(SlideCategory.values.map((value) => value.name), [
      'general',
      'informationSecurity',
      'procesverbetering',
      'managementsysteem',
    ]);
    expect(BulletColumns.values.map((value) => value.name), [
      'none',
      'one',
      'two',
    ]);
    expect(FindingRole.values.map((value) => value.name), [
      'header',
      'detail',
      'evidence',
    ]);
    expect(ListStyle.values.map((value) => value.name), [
      'bullets',
      'numbered',
      'checklist',
      'richText',
    ]);
    expect(TitleColumnLayout.values.map((value) => value.name), [
      'none',
      'left',
      'right',
      'both',
    ]);
    expect(TableAlign.values.map((value) => value.name), [
      'left',
      'center',
      'right',
    ]);
  });
}
