import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

/// Sidecars uit een nieuwere OciDeck: niets laden, en vooral niets
/// overschrijven. Half inlezen en dan opslaan wist werk dat deze build niet
/// begreep, en dat is niet meer terug te halen.

const _streek = InkStroke(
  tool: InkTool.pen,
  color: 0xFFEF4444,
  width: 0.01,
  points: [Offset(0.1, 0.2), Offset(0.3, 0.4)],
);

/// Een payload die zegt uit een nieuwere versie te komen, met inhoud die deze
/// build op zichzelf best zou kunnen lezen — juist dát is de valkuil.
String _uitDeToekomst(String json, int versie) {
  final data = Map<String, Object?>.from(jsonDecode(json) as Map);
  data['version'] = versie;
  return jsonEncode(data);
}

Future<Directory> _tijdelijkeMap(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

FileService _dienst() =>
    FileService(MarkdownService(), ImageService(), () => const ThemeProfile());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('de codecs lezen hun eigen versie', () {
    test('annotaties uit een nieuwere versie worden niet half geladen', () {
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final json = AnnotationCodec.encode(
        [slide],
        {
          slide.id: [_streek],
        },
      )!;
      expect(AnnotationCodec.decode(json, [slide]), isNotEmpty);
      expect(
        AnnotationCodec.decode(_uitDeToekomst(json, 2), [slide]),
        isEmpty,
        reason: 'versie 2 is onbekend; dan liever niets dan half',
      );
    });

    test('notities uit een nieuwere versie worden niet half geladen', () {
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final json = UserNotesCodec.encode([slide], {slide.id: 'Notitie'})!;
      expect(UserNotesCodec.decode(json, [slide]), isNotEmpty);
      // Versie 3 werd tot nu toe als 2 behandeld: wél lezen, en daarna
      // overschrijven met wat deze build ervan begreep.
      expect(UserNotesCodec.decode(_uitDeToekomst(json, 3), [slide]), isEmpty);
    });
  });

  group('een sidecar uit de toekomst wordt niet overschreven', () {
    test('de inkt-sidecar blijft staan zoals hij was', () async {
      final map = await _tijdelijkeMap('ocideck_sidecar_ink_');
      final pad = p.join(map.path, 'deck.md');
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final vanLater = _uitDeToekomst(
        AnnotationCodec.encode(
          [slide],
          {
            slide.id: [_streek],
          },
        )!,
        99,
      );
      final sidecar = File(p.join(map.path, 'deck.ink.json'));
      await sidecar.writeAsString(vanLater);

      // Opslaan zonder annotaties in het geheugen: de oude code wiste het
      // bestand hier (niets te schrijven → weg ermee).
      await _dienst().saveDeck(Deck(title: 'A', slides: [slide]), pad);
      expect(await sidecar.exists(), isTrue);
      expect(await sidecar.readAsString(), vanLater);
    });

    test('de notitie-sidecar blijft staan zoals hij was', () async {
      final map = await _tijdelijkeMap('ocideck_sidecar_notes_');
      final pad = p.join(map.path, 'deck.md');
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final vanLater = _uitDeToekomst(
        UserNotesCodec.encode([slide], {slide.id: 'Van later'})!,
        99,
      );
      final sidecar = File(p.join(map.path, 'deck.user-notes.json'));
      await sidecar.writeAsString(vanLater);

      // Zelfs mét eigen notities in het geheugen: overschrijven zou de
      // onbegrepen inhoud wissen.
      await _dienst().saveDeck(
        Deck(title: 'A', slides: [slide], userNotes: {slide.id: 'Van nu'}),
        pad,
      );
      expect(await sidecar.readAsString(), vanLater);
    });
  });
}
