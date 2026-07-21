import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/miauw_codec.dart';
import 'package:path/path.dart' as p;

/// De MIAUW-dispositie (uitsluitingen en klantbevestigingen) gaat over het
/// document in plaats van erin, en stond als base64 in de front matter. Ze
/// hoort naast de markdown, in `<naam>.miauw.json`.

const _uitsluitingen = {'1.3': 'Certificering niet vereist door klant'};
const _bevestigingen = {'2.1': 'Klant bevestigt de scope op 2026-07-01'};

Future<Directory> _tijdelijkeMap() async {
  final dir = await Directory.systemTemp.createTemp('ocideck_miauw_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

FileService _dienst() =>
    FileService(MarkdownService(), ImageService(), () => const ThemeProfile());

Deck _deck() => Deck(
  title: 'Pentest',
  slides: [Slide.create(SlideType.title).copyWith(title: 'Pentest')],
  miauwWaivers: _uitsluitingen,
  miauwConfirmations: _bevestigingen,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('de codec', () {
    test('schrijft niets als er geen dispositie is', () {
      expect(MiauwCodec.encode(const {}, const {}), isNull);
    });

    test('rondgang: uitsluitingen en bevestigingen komen heel terug', () {
      final json = MiauwCodec.encode(_uitsluitingen, _bevestigingen)!;
      final terug = MiauwCodec.decode(json);
      expect(terug.waivers, _uitsluitingen);
      expect(terug.confirmations, _bevestigingen);
    });

    test('een nieuwere versie wordt niet half gelezen', () {
      final json = MiauwCodec.encode(
        _uitsluitingen,
        _bevestigingen,
      )!.replaceAll('"version":${MiauwCodec.version}', '"version":99');
      final terug = MiauwCodec.decode(json);
      expect(terug.waivers, isEmpty);
      expect(terug.confirmations, isEmpty);
    });
  });

  group('naast het bestand, niet erin', () {
    test('opslaan zet de dispositie in de sidecar en niet in de .md', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await _dienst().saveDeck(_deck(), pad);

      final md = await File(pad).readAsString();
      expect(md, isNot(contains('ocideck_miauw_waivers')));
      expect(md, isNot(contains('ocideck_miauw_confirmations')));

      final sidecar = File(p.join(map.path, 'deck.miauw.json'));
      expect(await sidecar.exists(), isTrue);
      expect(await sidecar.readAsString(), contains('Certificering'));
    });

    test('openen zet haar weer op het deck', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await _dienst().saveDeck(_deck(), pad);

      final geopend = await _dienst().openDeck(pad);
      expect(geopend, isNotNull);
      expect(geopend!.miauwWaivers, _uitsluitingen);
      expect(geopend.miauwConfirmations, _bevestigingen);
    });

    test('een leeg geworden dispositie ruimt haar sidecar op', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      final dienst = _dienst();
      await dienst.saveDeck(_deck(), pad);
      final sidecar = File(p.join(map.path, 'deck.miauw.json'));
      expect(await sidecar.exists(), isTrue);

      await dienst.saveDeck(
        _deck().copyWith(miauwWaivers: const {}, miauwConfirmations: const {}),
        pad,
      );
      expect(await sidecar.exists(), isFalse);
    });
  });

  group('de dispositie reist mee waar de markdown alleen gaat', () {
    test('een pakket draagt haar als eigen lid', () async {
      final leden = await _dienst().buildPackageMembers(_deck());
      expect(leden.keys, contains('Pentest.miauw.json'));
      expect(
        utf8.decode(leden['Pentest.miauw.json']!),
        contains('Certificering'),
      );
      expect(
        utf8.decode(leden['Pentest.md']!),
        isNot(contains('ocideck_miauw')),
      );
    });
  });

  group('een bestaand bestand met base64 gaat mee', () {
    // Precies zoals OciDeck het tot 0.1.0 schreef: base64-JSON in de front
    // matter. Zulke bestanden liggen bij mensen op schijf.
    const oud =
        '---\n'
        'marp: true\n'
        'theme: ocideck\n'
        'ocideck_miauw_waivers: eyIxLjMiOiJDZXJ0aWZpY2VyaW5nIG5pZXQgdmVyZWlzdCBkb29yIGtsYW50In0=\n'
        'ocideck_miauw_confirmations: eyIyLjEiOiJLbGFudCBiZXZlc3RpZ3QgZGUgc2NvcGUgb3AgMjAyNi0wNy0wMSJ9\n'
        '---\n'
        '\n'
        '# Pentest\n';

    test('het blijft gewoon te openen', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await File(pad).writeAsString(oud);

      final geopend = await _dienst().openDeck(pad);
      expect(geopend, isNotNull);
      expect(geopend!.miauwWaivers, _uitsluitingen);
      expect(geopend.miauwConfirmations, _bevestigingen);
    });

    test('opslaan verhuist de dispositie naar de sidecar', () async {
      final map = await _tijdelijkeMap();
      final pad = p.join(map.path, 'deck.md');
      await File(pad).writeAsString(oud);
      final dienst = _dienst();

      final geopend = await dienst.openDeck(pad);
      await dienst.saveDeck(geopend!, pad);

      final md = await File(pad).readAsString();
      expect(md, isNot(contains('ocideck_miauw')));
      final terug = await dienst.openDeck(pad);
      expect(terug!.miauwWaivers, _uitsluitingen);
      expect(terug.miauwConfirmations, _bevestigingen);
    });
  });
}
