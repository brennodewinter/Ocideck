import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/slide_failure_policy.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_image.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// Het faalbeleid per dia (#812).
///
/// De enum bestond al, maar werd alleen *gezet* en nooit gelezen: elke dia
/// kreeg best-effort, en `skip`/`imageOnly` waren onbereikbaar. Deze tests
/// bewaken dat de keuze nu werkelijk doorwerkt — en, minstens zo belangrijk,
/// dat een dia zónder verlies er niet door geraakt wordt. Eén keuze mag niet
/// het hele deck opruimen.
void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  /// Een dia met écht verlies: audio komt nooit over, dus dit is er altijd een.
  SourceSlide problem({int index = 0, bool withImage = false}) => SourceSlide(
    index: index,
    title: 'Kwartaal',
    bodyBlocks: const [BodyBlock(kind: BodyBlockKind.bullet, text: 'Punt')],
    audioFileName: 'intro.m4a',
    images: withImage
        ? [
            SourceImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              ext: 'png',
              name: 'plaat.png',
            ),
          ]
        : const [],
  );

  ({List<Slide> slides, String notes}) build(
    List<SourceSlide> sources, {
    Map<int, SlideFailurePolicy> policies = const {},
  }) {
    final built = DeckBuilder().build(
      SourceDeck(slides: sources),
      [for (final s in sources) classifySlide(s)],
      title: 'Test',
      policies: policies,
    );
    return (
      slides: built.deck.slides,
      notes: built.deck.slides
          .where((s) => s.type == SlideType.freeMarkdown)
          .map((s) => s.customMarkdown)
          .join('\n'),
    );
  }

  test('de analyse vindt de probleemdia zonder een deck te bouwen', () {
    final sources = [problem()];
    final found = DeckBuilder().analyse([
      for (final s in sources) classifySlide(s),
    ]);
    expect(found, hasLength(1));
    expect(found.single.sourceSlideNumber, 1);
  });

  test('zonder keuze blijft het best-effort: dia plus notitie', () {
    final r = build([problem()]);
    expect(r.slides.first.type, isNot(SlideType.freeMarkdown));
    expect(r.slides.first.bullets.join(), contains('Punt'));
    expect(r.notes, contains('Niet overgenomen'));
  });

  test('overslaan laat alleen de notitie staan', () {
    final r = build([problem()], policies: {0: SlideFailurePolicy.skip});
    // De inhoudsdia is weg; wat overblijft is de notitie die zegt waarom.
    expect(r.slides.every((s) => s.type == SlideType.freeMarkdown), isTrue);
    expect(r.notes, contains('overgeslagen'));
  });

  test('alleen-de-afbeelding houdt het beeld en laat de tekst vallen', () {
    final r = build(
      [problem(withImage: true)],
      policies: {0: SlideFailurePolicy.imageOnly},
    );
    final first = r.slides.first;
    expect(first.type, SlideType.image);
    expect(first.imagePath, isNotEmpty);
    expect(first.bullets.join(), isNot(contains('Punt')));
    expect(r.notes, contains('alleen de afbeelding'));
  });

  test('alleen-de-afbeelding zonder afbeelding wordt overslaan', () {
    // Een afbeeldingsdia zonder afbeelding is niets; dan is overslaan eerlijker
    // dan een lege dia achterlaten.
    final r = build([problem()], policies: {0: SlideFailurePolicy.imageOnly});
    expect(r.slides.every((s) => s.type == SlideType.freeMarkdown), isTrue);
    expect(r.notes, contains('overgeslagen'));
  });

  test('een dia zonder verlies blijft ongemoeid, wat het beleid ook zegt', () {
    // De regel die voorkomt dat één keuze het hele deck opruimt: het beleid
    // geldt uitsluitend voor dia's die écht iets kwijtraken.
    final clean = SourceSlide(
      index: 1,
      title: 'Gewoon',
      bodyBlocks: const [BodyBlock(kind: BodyBlockKind.bullet, text: 'Blijft')],
    );
    final r = build(
      [problem(), clean],
      policies: {0: SlideFailurePolicy.skip, 1: SlideFailurePolicy.skip},
    );

    final kept = r.slides.where((s) => s.type != SlideType.freeMarkdown);
    expect(kept, hasLength(1));
    expect(kept.single.bullets.join(), contains('Blijft'));
  });
}
