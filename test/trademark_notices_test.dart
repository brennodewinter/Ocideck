import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/video_source.dart';
import 'package:ocideck/models/webdav_settings.dart';

/// OciDeck noemt andermans producten bij naam: het formaat dat het schrijft
/// (Marp), de server waar het heen praat (Nextcloud), de spelers die het insluit
/// (YouTube, Vimeo). Dat is nominatief gebruik en juridisch laag risico — maar
/// alleen zolang de eigenaar erbij staat. Wie een merk voert zonder de eigenaar
/// te noemen, wekt de indruk dat het van hem is.
///
/// De poort is mechanisch: elk merk dat het product *als functie* voert, staat
/// in een enum. Komt er een embed-provider of een WebDAV-smaak bij, dan valt
/// deze test voordat de naam ongenoemd in de interface belandt.
void main() {
  final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();

  /// De naam waaronder een merk in de tabel hoort te staan, per enum-waarde.
  /// `null` = geen merknaam (een generieke of eigen categorie).
  const videoBrand = {
    VideoSourceKind.youtube: 'YouTube',
    VideoSourceKind.vimeo: 'Vimeo',
    VideoSourceKind.none: null,
    VideoSourceKind.localFile: null,
    VideoSourceKind.remoteFile: null,
  };

  const webdavBrand = {
    WebdavServerKind.nextcloud: 'Nextcloud',
    WebdavServerKind.generic: null,
  };

  test('THIRD_PARTY_NOTICES.md has a trademarks section', () {
    expect(
      notices,
      contains('## Trademarks'),
      reason:
          'De merkvermelding is de plek waar het nominatieve gebruik wordt '
          'verantwoord. Zonder die sectie hebben de controles hieronder geen '
          'thuis.',
    );
  });

  test('every branded video provider is named with its owner', () {
    expect(
      videoBrand.keys.toSet(),
      equals(VideoSourceKind.values.toSet()),
      reason:
          'Er is een videobron bijgekomen of weggegaan. Voert die een merknaam, '
          'zet hem hier én in de merktabel van THIRD_PARTY_NOTICES.md.',
    );
    for (final brand in videoBrand.values.whereType<String>()) {
      expect(
        notices,
        contains('**$brand**'),
        reason: '$brand wordt ingesloten maar staat niet in de merktabel.',
      );
    }
  });

  test('every branded WebDAV flavour is named with its owner', () {
    expect(
      webdavBrand.keys.toSet(),
      equals(WebdavServerKind.values.toSet()),
      reason:
          'Er is een WebDAV-smaak bijgekomen. Draagt die een merknaam, zet hem '
          'hier én in de merktabel van THIRD_PARTY_NOTICES.md.',
    );
    for (final brand in webdavBrand.values.whereType<String>()) {
      expect(
        notices,
        contains('**$brand**'),
        reason:
            '$brand heeft een eigen preset maar staat niet in de merktabel.',
      );
    }
  });

  test('Marp is named with its owner and the non-affiliation is stated', () {
    // Marp zit niet in een enum — het is het formaat zelf. De poort hangt
    // daarom aan het gebundelde thema: zolang OciDeck een Marp-thema meelevert,
    // voert het de naam.
    expect(File('assets/themes/ocideck.css').existsSync(), isTrue);
    expect(notices, contains('**Marp**'));
    expect(notices, contains('Marp Team'));
  });

  test('each branded row disclaims affiliation', () {
    // Een merkvermelding die alleen de eigenaar noemt, laat de suggestie van
    // samenwerking staan. Dat is precies de suggestie die je niet mag wekken.
    final rows = notices
        .split('\n')
        .where((l) => l.startsWith('| **'))
        .toList();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(
        row.toLowerCase(),
        contains('not affiliated with'),
        reason: 'Rij zonder afstandsverklaring: $row',
      );
    }
  });
}
