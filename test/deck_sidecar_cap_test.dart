// De vier sidecars naast een deck (`.ink.json`, `.user-notes.json`,
// `.miauw.json`, `.seal.json`) reizen met het deck mee — uit een pakket, een
// repo, of een map die iemand anders heeft gemaakt. Ze werden bij het openen
// onbegrensd ingelezen, met de kopie die `jsonDecode` er meteen bovenop legt.
//
// De schrijfkant is de scherpste, net als bij de bijschriften-sidecar: een
// bestand dat we niet hebben ingelezen mag ook niet vervangen of verwijderd
// worden. Het deck draagt de inhoud dan niet in het geheugen, dus opslaan zou
// andermans strepen, notities of zegel wissen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/annotation_codec.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/user_notes_codec.dart';
import 'package:path/path.dart' as p;

const _streek = InkStroke(
  tool: InkTool.pen,
  color: 0xFFEF4444,
  width: 0.01,
  points: [Offset(0.1, 0.2), Offset(0.3, 0.4)],
  id: 's1',
);

FileService _dienst() =>
    FileService(MarkdownService(), ImageService(), () => const ThemeProfile());

Future<Directory> _tijdelijkeMap(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

/// Geldige JSON die deze build op zichzelf zou kunnen lezen, opgeblazen tot
/// boven de grens met één extra sleutel. Het gaat om de omvang, niet om
/// corruptie — een sidecar die als kapot wordt herkend valt onder een andere
/// regel.
String _teGroot(String json) {
  final data = Map<String, Object?>.from(jsonDecode(json) as Map);
  data['opvulling'] = 'x' * (FileService.maxDeckSidecarBytes + 1024);
  return jsonEncode(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('een inkt-sidecar boven de grens wordt niet ingelezen', () async {
    final map = await _tijdelijkeMap('ocideck_sidecar_cap_ink_');
    final pad = p.join(map.path, 'deck.md');
    final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
    await _dienst().saveDeck(Deck(title: 'A', slides: [slide]), pad);
    await File(p.join(map.path, 'deck.ink.json')).writeAsString(
      _teGroot(
        AnnotationCodec.encode(
          [slide],
          {
            slide.id: [_streek],
          },
        )!,
      ),
    );

    final deck = await _dienst().openDeck(pad);
    expect(
      deck?.annotations ?? const {},
      isEmpty,
      reason: 'boven de grens hoort er niets ingelezen te worden',
    );
  });

  test('opslaan laat een te grote sidecar ongemoeid', () async {
    final map = await _tijdelijkeMap('ocideck_sidecar_cap_write_');
    final pad = p.join(map.path, 'deck.md');
    final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
    final sidecar = File(p.join(map.path, 'deck.user-notes.json'));
    final voor = _teGroot(
      UserNotesCodec.encode([slide], {slide.id: 'Van iemand anders'})!,
    );
    await sidecar.writeAsString(voor);

    // Zonder notities in het geheugen: de ongebonden code kwam hier langs met
    // een lege map en verwijderde het bestand.
    await _dienst().saveDeck(Deck(title: 'A', slides: [slide]), pad);

    expect(await sidecar.exists(), isTrue);
    expect(
      await sidecar.readAsString(),
      voor,
      reason:
          'wat niet is ingelezen mag ook niet vervangen worden — dat wist '
          'notities die deze build alleen maar heeft overgeslagen',
    );
  });

  test('een overgeslagen laag wordt gemeld, niet alleen gelogd', () async {
    // De reden dat #564 bestond: het bestand blijft heel, maar de gebruiker zag
    // alleen dat zijn strepen er niet waren. Dat leest als "die zijn er nooit
    // geweest" in plaats van "deze laag is overgeslagen".
    final map = await _tijdelijkeMap('ocideck_sidecar_cap_melding_');
    final pad = p.join(map.path, 'deck.md');
    final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
    await _dienst().saveDeck(Deck(title: 'A', slides: [slide]), pad);
    await File(p.join(map.path, 'deck.ink.json')).writeAsString(
      _teGroot(
        AnnotationCodec.encode(
          [slide],
          {
            slide.id: [_streek],
          },
        )!,
      ),
    );

    final uitkomst = await _dienst().openDeckDetailed(pad);
    expect(uitkomst.deck, isNotNull, reason: 'het deck opent gewoon');
    expect(
      uitkomst.skippedSidecars,
      contains('ink'),
      reason: 'wie niets meldt, laat de gebruiker denken dat er niets was',
    );
  });

  test('een deck zonder problemen meldt niets', () async {
    final map = await _tijdelijkeMap('ocideck_sidecar_cap_stil_');
    final pad = p.join(map.path, 'deck.md');
    final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
    await _dienst().saveDeck(
      Deck(
        title: 'A',
        slides: [slide],
        annotations: {
          slide.id: [_streek],
        },
      ),
      pad,
    );
    expect((await _dienst().openDeckDetailed(pad)).skippedSidecars, isEmpty);
  });

  test('een sidecar onder de grens werkt gewoon', () async {
    final map = await _tijdelijkeMap('ocideck_sidecar_cap_ok_');
    final pad = p.join(map.path, 'deck.md');
    final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
    await _dienst().saveDeck(
      Deck(
        title: 'A',
        slides: [slide],
        annotations: {
          slide.id: [_streek],
        },
        userNotes: {slide.id: 'Een notitie'},
      ),
      pad,
    );

    // Het heropende deck heeft nieuwe slide-id's; de codecs koppelen op inhoud.
    final deck = await _dienst().openDeck(pad);
    final heropend = deck!.slides.single.id;
    expect(deck.annotations[heropend], isNotEmpty);
    expect(deck.userNotes[heropend], 'Een notitie');
  });
}
