import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';

/// De zips die OciDeck schrijft zonder eigen UTC-metadata (pakket, auditdossier,
/// downloadbundel) dragen één vaste tijd, los van tijdzone en moment.
///
/// archive 4.6 schrijft per lid de DOS-tijd in lokale tijd en het exacte moment
/// in een UT-extraveld. De centrale map is ook bij AES onversleuteld: DOS min UT
/// gaf zo de UTC-offset van de maker, en het exportmoment op de seconde, prijs
/// aan iedereen met het bestand — wachtwoord of niet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void expectNeutralTimes(List<int> zip, {String? password}) {
    final archive = ZipDecoder().decodeBytes(
      zip,
      password: password,
      verify: true,
      throwOnError: true,
    );
    expect(archive.files, isNotEmpty);
    for (final file in archive.files) {
      // DOS 1980-01-01 00:00 (datum 0x0021, tijd 0): in elke zone hetzelfde.
      expect(file.lastModDosTime, 0x0021 << 16, reason: file.name);
      // Het UT-veld: één vast moment, niet het exportmoment.
      expect(
        file.lastModDateTime.toUtc(),
        DateTime.utc(1979, 12, 31),
        reason: file.name,
      );
    }
  }

  final service = FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
  );
  final deck = Deck(
    title: 'Tijdloos',
    slides: [Slide.create(SlideType.title).copyWith(title: 'Tijdloos')],
  );

  test('een pakket, onversleuteld en versleuteld', () async {
    expectNeutralTimes(await service.buildPackageBytes(deck));
    expectNeutralTimes(
      await service.buildPackageBytes(deck, password: 'geheim'),
      password: 'geheim',
    );
  });

  test('een versleuteld auditdossier', () async {
    final bytes = await service.buildDossierBytes(
      deck,
      dossierIndex: '# Dossier',
      password: 'geheim',
    );
    expectNeutralTimes(bytes, password: 'geheim');
  });

  test('een downloadbundel van meer dan één bestand', () {
    Uint8List? zip;
    debugDownloadSink = (name, bytes, mime) {
      zip = bytes;
      return true;
    };
    addTearDown(() => debugDownloadSink = null);
    deliverAsDownload([
      (name: 'deck.md', bytes: Uint8List.fromList(utf8.encode('# Deck'))),
      (name: 'notes.md', bytes: Uint8List.fromList(utf8.encode('notities'))),
    ], bundleName: 'deck.zip');
    expectNeutralTimes(zip!);
  });
}
