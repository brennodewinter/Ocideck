@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/shell/dropped_files.dart';

/// De drop-afhandeling losgeweekt van de shell, zodat ze getoetst kán worden.
///
/// Waarom dit bestand bestaat: onder `flutter test` is `kIsWeb` altijd `false`,
/// dus de web-tak van de drop hangt achter een gate die geen widgettest passeert
/// — en dáár zat een fout die geen enkele poort zag. Het lezen van een gesleept
/// bestand ging op web over een blob-URL, de CSP blokkeerde die lezing, en de
/// opgegooide fout verdween in de zone omdat `onDragDone` niets afwacht. Voor de
/// gebruiker: een pptx op het venster gooien en er gebeurt niets.
void main() {
  group('droppedKind', () {
    test('herkent presentaties van elders als importwerk', () {
      for (final name in ['deck.pptx', 'Deck.PPTX', 'a.odp', 'b.key']) {
        expect(
          droppedKind(name),
          DroppedKind.presentation,
          reason: '$name hoort de import in te gaan',
        );
      }
    });

    test('herkent decks en pakketten', () {
      for (final name in ['deck.md', 'deck.ocideck', 'deck.zip']) {
        expect(droppedKind(name), DroppedKind.deck, reason: name);
      }
    });

    test('herkent afbeeldingen, ongeacht schrijfwijze', () {
      for (final name in ['foto.PNG', 'plaat.jpeg', 'scan.tiff']) {
        expect(droppedKind(name), DroppedKind.image, reason: name);
      }
    });

    test('negeert wat de drop niet opent', () {
      // Bewust: een type dat we toch laten liggen mag niet eerst ingelezen
      // worden — daarom kiest de drop op de naam vóór hij bytes aanraakt.
      for (final name in ['setup.exe', 'aantekening.txt', 'geen-extensie']) {
        expect(droppedKind(name), isNull, reason: name);
      }
    });
  });

  group('readDroppedBytes', () {
    test('levert de bytes van een leesbaar bestand', () async {
      final item = DropItemFile.fromData(
        Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]),
        name: 'deck.pptx',
      );

      expect(await readDroppedBytes(item), [0x50, 0x4b, 0x03, 0x04]);
    });

    test('geeft null in plaats van te gooien als lezen weigert', () async {
      // Dit is het geval dat de webversie sloopte: de browser weigerde de
      // blob-lezing, `readAsBytes` gooide, en omdat niemand die fout ving nam
      // hij de hele drop mee — zonder melding. Eén onleesbaar bestand mag
      // hoogstens dát bestand kosten.
      expect(await readDroppedBytes(_WeigerendeDropItem()), isNull);
    });

    test('een onleesbaar bestand laat de andere ongemoeid', () async {
      final items = <DropItem>[
        _WeigerendeDropItem(),
        // `path` erbij: op de VM leidt XFile de naam uit het pad af, waar de
        // web-variant hem apart meedraagt.
        DropItemFile.fromData(
          Uint8List.fromList([1, 2]),
          name: 'goed.md',
          path: 'goed.md',
        ),
      ];

      final gelezen = <String>[];
      var onleesbaar = 0;
      for (final item in items) {
        final bytes = await readDroppedBytes(item);
        if (bytes == null) {
          onleesbaar++;
        } else {
          gelezen.add(item.name);
        }
      }

      expect(gelezen, ['goed.md']);
      expect(
        onleesbaar,
        1,
        reason: 'de teller draagt de melding die de gebruiker hierna krijgt',
      );
    });
  });
}

/// Een gesleept bestand waarvan de bytes niet te krijgen zijn — wat een
/// geblokkeerde blob-lezing in de browser doet.
class _WeigerendeDropItem extends DropItemFile {
  _WeigerendeDropItem()
    : super('blob:https://example.invalid/weg', name: 'x.pptx');

  @override
  Future<Uint8List> readAsBytes() async =>
      throw Exception('Could not load Blob from its URL. Has it been revoked?');
}
