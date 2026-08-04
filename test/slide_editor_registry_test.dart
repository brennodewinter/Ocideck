import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/slide_editor_registry.dart';

// Bewaakt de dispatchtabel zelf (#1162 gaf hem het menu-diatype erbij): élke
// SlideType heeft niet alleen een sleutel maar een builder die zonder gooien een
// widget teruggeeft. `slide_type_meta_test` toetst dát de sleutel bestaat; hier
// draaien we de closures écht — de productieroute waarlangs het editor-paneel een
// editor kiest — zodat een verkeerd bedraad type (verkeerde constructor, ontbrekend
// argument) hier valt in plaats van pas bij het openen van die dia.
SlideEditorContext _contextFor(SlideType type) => SlideEditorContext(
  slide: Slide.create(type),
  onUpdate: (_) {},
  imageService: ImageService(),
  searchPaths: const [],
  captionBasePath: null,
  onAddChartVariants: (_) {},
  themeAnimationDurationMs: 0,
);

void main() {
  test('elke SlideType bouwt via de registry een widget zonder te gooien', () {
    for (final type in SlideType.values) {
      final builder = slideEditorBuilders[type];
      expect(
        builder,
        isNotNull,
        reason: 'geen slideEditorBuilders-entry voor SlideType.$type',
      );
      final widget = builder!(_contextFor(type));
      expect(widget, isA<Widget>());
      // De sleutel is stabiel per dia, zodat het paneel bij een typewissel de
      // juiste editor-state opnieuw opbouwt.
      expect(widget.key, isNotNull);
    }
  });

  test('het keuze-menu-diatype dispatcht naar de MenuEditor', () {
    final widget = slideEditorBuilders[SlideType.menu]!(
      _contextFor(SlideType.menu),
    );
    expect(widget.runtimeType.toString(), 'MenuEditor');
  });
}
