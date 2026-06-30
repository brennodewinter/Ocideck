import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';

/// Guard for the SlideType descriptor registry (the maintainability refactor):
/// the `slideTypeMeta` map must cover every [SlideType], so a newly added type
/// fails here instead of throwing a null-assertion at runtime when its label or
/// marpClass is first read.
void main() {
  test('every SlideType has metadata', () {
    for (final type in SlideType.values) {
      expect(
        slideTypeMeta[type],
        isNotNull,
        reason: 'Add a slideTypeMeta entry for SlideType.$type',
      );
    }
  });

  test('label and marpClass read through the registry', () {
    expect(SlideType.title.label, 'Titelpagina');
    expect(SlideType.title.marpClass, 'title');
    expect(SlideType.bullets.marpClass, isEmpty);
    expect(SlideType.bulletsImage.marpClass, 'split');
  });

  test('capability flags match the types they replaced', () {
    // splitWithImage replaced `type == SlideType.bulletsImage`.
    expect(SlideType.values.where((t) => t.splitWithImage), [
      SlideType.bulletsImage,
    ]);
    // isHeading replaced `type == title || type == section`.
    expect(SlideType.title.isHeading, isTrue);
    expect(SlideType.section.isHeading, isTrue);
    expect(SlideType.bullets.isHeading, isFalse);
    expect(SlideType.values.where((t) => t.isHeading).toSet(), {
      SlideType.title,
      SlideType.section,
    });
  });
}
