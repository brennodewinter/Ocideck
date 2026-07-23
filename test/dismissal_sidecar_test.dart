import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/dismissal_codec.dart';
import 'package:path/path.dart' as p;

/// Terzijdegelegde privacybevindingen horen naast de markdown, in
/// `<naam>.dismissals.json` (FILE_FORMAT §6.7, #651).
///
/// Het gaat *over* het document — "deze naam hóórt hier" — en niet erin, net
/// als de notities, de inktlaag en het zegel. Deze toetsen lopen het hele pad
/// af: opslaan, heropenen, opruimen, en de reis in een pakket.

const _zout = '0123456789abcdef0123456789abcdef';

Future<Directory> _tijdelijkeMap() async {
  final dir = await Directory.systemTemp.createTemp('ocideck_dismissals_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

FileService _dienst() =>
    FileService(MarkdownService(), ImageService(), () => const ThemeProfile());

DeckDismissals _terzijde() => DeckDismissals(
  salt: _zout,
  dismissals: [
    PrivacyDismissal(
      ruleId: 'nl.name',
      commitment: commitmentFor(_zout, 'Jan Jansen'),
      at: DateTime.utc(2026, 7, 23, 12),
      seenAtSlide: 0,
      seenAtField: 'title',
    ),
  ],
);

Deck _deck({DeckDismissals? terzijde}) => Deck(
  title: 'Pentest',
  slides: [Slide.create(SlideType.title).copyWith(title: 'Jan Jansen')],
  dismissals: terzijde ?? _terzijde(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('newDismissalSalt', () {
    test('geeft elke keer iets anders, in hex', () {
      final a = newDismissalSalt();
      final b = newDismissalSalt();
      expect(
        a,
        isNot(b),
        reason: 'een voorspelbaar zout stopt geen correlatie',
      );
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
    });
  });

  group('naast het bestand, niet erin', () {
    test('opslaan schrijft de sidecar, en de .md draagt niets', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await _dienst().saveDeck(_deck(), pad);

      final sidecar = File(p.join(map.path, 'deck.dismissals.json'));
      expect(await sidecar.exists(), isTrue);

      final inhoud = await sidecar.readAsString();
      expect(inhoud, contains('nl.name'));
      // De kern van §6.7: geen tweede kopie van het persoonsgegeven.
      expect(inhoud, isNot(contains('Jan Jansen')));

      final md = await File(pad).readAsString();
      expect(md, isNot(contains('dismissal')));
      expect(md, isNot(contains(_zout)));
    });

    test('heropenen zet het oordeel terug op het deck', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await _dienst().saveDeck(_deck(), pad);

      final geopend = await _dienst().openDeck(pad);
      expect(geopend, isNotNull);
      final terug = geopend!.dismissals;
      expect(terug, isNotNull);
      expect(terug!.salt, _zout);
      expect(terug.hides('nl.name', 'Jan Jansen'), isTrue);
      expect(terug.hides('nl.name', 'Piet Pietersen'), isFalse);
      // seen_at is er om te tónen, niet om op te matchen — maar het hoort de
      // reis wel te overleven, anders kan de lijst niet zeggen wáár je oordeelde.
      expect(terug.dismissals.single.seenAtSlide, 0);
      expect(terug.dismissals.single.seenAtField, 'title');
    });

    test('een deck zonder oordelen krijgt geen sidecar', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await _dienst().saveDeck(
        _deck(terzijde: const DeckDismissals(salt: _zout)),
        pad,
      );
      expect(
        await File(p.join(map.path, 'deck.dismissals.json')).exists(),
        isFalse,
      );
    });

    test('alles herroepen ruimt de sidecar niet op', () async {
      // Bewust: een herroeping is zélf een oordeel dat moet blijven staan.
      // Gooi je hem weg, dan wint bij de eerstvolgende samenvoeging de kant
      // die de terzijdelegging nog draagt en blijft de bevinding verborgen.
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final dienst = _dienst();
      await dienst.saveDeck(_deck(), pad);

      final c = commitmentFor(_zout, 'Jan Jansen');
      await dienst.saveDeck(
        _deck(
          terzijde: DeckDismissals(
            salt: _zout,
            revocations: [
              PrivacyDismissal(
                ruleId: 'nl.name',
                commitment: c,
                at: DateTime.utc(2026, 7, 23, 13),
              ),
            ],
          ),
        ),
        pad,
      );

      final sidecar = File(p.join(map.path, 'deck.dismissals.json'));
      expect(await sidecar.exists(), isTrue);
      final geopend = await dienst.openDeck(pad);
      expect(geopend!.dismissals!.hides('nl.name', 'Jan Jansen'), isFalse);
    });
  });

  group('het reist mee waar de markdown alleen niet genoeg is', () {
    test('een pakket draagt het als eigen lid', () async {
      final leden = await _dienst().buildPackageMembers(_deck());
      expect(leden.keys, contains('Pentest.dismissals.json'));
      expect(leden['Pentest.dismissals.json'], isNot(contains('Jan Jansen')));
    });

    test('zonder oordelen zit er geen lid in het pakket', () async {
      final leden = await _dienst().buildPackageMembers(
        _deck(terzijde: const DeckDismissals(salt: _zout)),
      );
      expect(leden.keys, isNot(contains('Pentest.dismissals.json')));
    });
  });
}
