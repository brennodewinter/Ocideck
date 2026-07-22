// Media hoort in de repo thuis, niet in een waarschuwing.
//
// Wie zijn presentaties in git bewaart, verwacht dat de film erbij zit. Een deck
// waarin die ontbreekt is geen kopie maar een fragment. Video en audio gaan
// daarom door dezelfde content-geadresseerde pool als afbeeldingen (D5), en
// komen op een platform met bestandssysteem terug als gestaged bestand in plaats
// van in het geheugen (D12) — `WebAssetStore` is een map in RAM, en de
// mediagrens staat op een gigabyte.
//
// Deze test bewaakt de schrijfzijde: de verwijzing in `deck.md` wordt een
// `repo:`-pad, en de bytes komen als blob mee. De leeszijde hangt op
// `AssetStaging`, dat een echte tijdelijke map nodig heeft; die kant is een
// integratietest en geen unittest.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/deck_repo_serializer.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Een minimale, geldige MP4-kop: `ftyp`-box met merk `isom`. Genoeg om als
/// container te snuiven; de inhoud doet er voor het poolen niet toe.
final _mp4 = Uint8List.fromList([
  0, 0, 0, 24, // boxgrootte
  ...ascii.encode('ftyp'),
  ...ascii.encode('isom'),
  0, 0, 2, 0,
  ...ascii.encode('isomiso2'),
]);

/// Idem voor audio: een ID3-getagde MP3.
final _mp3 = Uint8List.fromList([
  ...ascii.encode('ID3'),
  3,
  0,
  0,
  0,
  0,
  0,
  10,
  ...List.filled(10, 0),
]);

void main() {
  final md = MarkdownService();

  // Een videodia, want alleen dáár schrijft de Markdown de verwijzing uit; op
  // een bullets-dia wordt `videoPath` wel gepoold maar niet gerenderd.
  Deck deckMet({String video = '', String audio = ''}) => Deck(
    title: 'Rapport',
    slides: [
      Slide.create(
        video.isEmpty ? SlideType.bullets : SlideType.video,
      ).copyWith(title: 'Dia', videoPath: video, audioPath: audio),
    ],
  );

  Future<RepoDeckFiles> build(Deck deck, Map<String, Uint8List> ophaalbaar) =>
      buildDeckRepoFiles(
        deck,
        md: md,
        pool: null, // native plane: git ontdubbelt zelf
        deckDir: 'decks/rapport',
        resolveBytes: (path) async => ophaalbaar[path],
      );

  test('een video gaat als blob mee en krijgt een repo:-verwijzing', () async {
    final files = await build(deckMet(video: '/media/intro.mp4'), {
      '/media/intro.mp4': _mp4,
    });

    final blobs = files.upserts.keys
        .where((k) => k.startsWith('${GitRepoLayout.assetsRoot}/'))
        .toList();
    expect(
      files.upserts.values.any((b) => b.length == _mp4.length),
      isTrue,
      reason: 'de videobytes horen als blob in de commit te zitten',
    );
    expect(blobs, isNotEmpty, reason: 'er hoort een assetpad bij te komen');

    final deckMd = utf8.decode(
      files.upserts.entries.firstWhere((e) => e.key.endsWith('deck.md')).value,
    );
    expect(
      deckMd,
      contains('assets/'),
      reason:
          'deck.md moet naar het poolpad wijzen; blijft het bronpad staan, dan '
          'kent de forge de verwijzing niet en telt de asset als ongebruikt',
    );
    expect(deckMd, isNot(contains('/media/intro.mp4')));
  });

  test('audio gaat op dezelfde manier mee', () async {
    final files = await build(deckMet(audio: '/media/stem.mp3'), {
      '/media/stem.mp3': _mp3,
    });
    expect(files.upserts.values.any((b) => b.length == _mp3.length), isTrue);
    expect(files.warnings, isEmpty);
  });

  test('dezelfde film op twee dia\'s levert één blob op', () async {
    final deck = Deck(
      title: 'Rapport',
      slides: [
        Slide.create(
          SlideType.video,
        ).copyWith(title: 'Een', videoPath: '/media/intro.mp4'),
        Slide.create(
          SlideType.video,
        ).copyWith(title: 'Twee', videoPath: '/media/intro.mp4'),
      ],
    );
    final files = await build(deck, {'/media/intro.mp4': _mp4});
    final blobs = files.upserts.keys
        .where((k) => k.startsWith('${GitRepoLayout.assetsRoot}/'))
        .toList();
    expect(
      blobs.length,
      1,
      reason:
          'de pool adresseert op inhoud, dus twee verwijzingen naar dezelfde '
          'film delen één blob — anders groeit de historie bij elke commit',
    );
  });

  test(
    'media die niet te lezen is, wordt gemeld en niet stil overgeslagen',
    () async {
      final files = await build(deckMet(video: '/media/weg.mp4'), const {});
      expect(
        files.warnings,
        contains('/media/weg.mp4'),
        reason:
            'stil laten vallen is precies de fout die dit issue beschrijft: de '
            'gebruiker denkt dat zijn film meereist',
      );
    },
  );

  test('een deck zonder media meldt niets over media', () {
    final missing = gitDeckOmissions(deckMet());
    expect(missing.isEmpty, isTrue);
  });

  test('een deck mét media meldt die niet langer als verlies', () {
    // De waarschuwing bestond omdat media achterbleef. Nu ze meereist, mag ze
    // er niet meer in staan — een waarschuwing die onwaar is, leert de
    // gebruiker de hele melding weg te klikken.
    final missing = gitDeckOmissions(
      deckMet(video: '/media/intro.mp4', audio: '/media/stem.mp3'),
    );
    expect(missing.isEmpty, isTrue);
  });
}
