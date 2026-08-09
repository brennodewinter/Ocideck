import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/services/image_rename_service.dart';

/// Dekt de hernoem-service: naamvalidatie, doelpad-berekening, en de volledige
/// flow (bestand verplaatsen, verwijzingen in .md herschrijven, sidecar
/// migreren). Het blauwdruk is de dedup-flow; hier verplaatst één bestand naar
/// zijn eigen nieuwe naam.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rename_service');
  });

  tearDown(() {
    if (!tempDir.existsSync()) return;
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Opruimen van een tijdelijke map is nooit een testoordeel waard.
    }
  });

  group('validateStem', () {
    test('geldige naam is ok', () {
      expect(
        ImageRenameService.validateStem('logo', 'oud'),
        RenameValidation.ok,
      );
    });

    test('leeg of alleen spaties is disabled', () {
      expect(
        ImageRenameService.validateStem('', 'oud'),
        RenameValidation.disabled,
      );
      expect(
        ImageRenameService.validateStem('   ', 'oud'),
        RenameValidation.disabled,
      );
    });

    test('ongewijzigd is disabled', () {
      expect(
        ImageRenameService.validateStem('oud', 'oud'),
        RenameValidation.disabled,
      );
    });

    test('pad-scheiders zijn invalidName', () {
      expect(
        ImageRenameService.validateStem('map/logo', 'oud'),
        RenameValidation.invalidName,
      );
      expect(
        ImageRenameService.validateStem('logo\\bestand', 'oud'),
        RenameValidation.invalidName,
      );
    });

    test('.. en . zijn invalidName', () {
      expect(
        ImageRenameService.validateStem('..', 'oud'),
        RenameValidation.invalidName,
      );
      expect(
        ImageRenameService.validateStem('.', 'oud'),
        RenameValidation.invalidName,
      );
    });
  });

  group('destinationPath', () {
    test('zelfde map, nieuwe stem, extensie behouden', () {
      final dest = ImageRenameService.destinationPath(
        '/project/images/100000ABC.png',
        'logo',
      );
      expect(dest, '/project/images/logo.png');
    });

    test('werkt zonder mapnaam in het pad', () {
      final dest = ImageRenameService.destinationPath('foto.png', 'nieuw');
      expect(p.basename(dest), 'nieuw.png');
    });
  });

  group('rename', () {
    test('verplaatst het bestand en herschrijft verwijzingen in .md', () async {
      final img = File('${tempDir.path}/100000ABC.png')
        ..writeAsBytesSync(_onePixelPng);
      final deck = File('${tempDir.path}/deck.md')
        ..writeAsStringSync('# Titel\n\n![logo](${p.basename(img.path)})\n');

      final service = ImageRenameService();
      final result = await service.rename(
        oldPath: img.path,
        newStem: 'logo',
        deckFiles: [deck.path],
        captionService: CaptionService(),
        descriptionService: DescriptionService(),
      );

      expect(result.failure, isNull);
      expect(result.newPath, '${tempDir.path}/logo.png');
      expect(File(result.newPath!).existsSync(), isTrue);
      expect(img.existsSync(), isFalse);
      expect(deck.readAsStringSync(), contains('logo.png'));
      expect(deck.readAsStringSync(), isNot(contains('100000ABC')));
      expect(result.updatedDeckFiles, [deck.path]);
    });

    test('migreert caption-sidecar naar de nieuwe basename', () async {
      final img = File('${tempDir.path}/oud.png')
        ..writeAsBytesSync(_onePixelPng);
      final captions = CaptionService();
      await captions.saveCaption(img.path, 'Foto: Brenno de Winter');

      final service = ImageRenameService();
      final result = await service.rename(
        oldPath: img.path,
        newStem: 'nieuw',
        deckFiles: const [],
        captionService: captions,
        descriptionService: DescriptionService(),
      );

      expect(result.failure, isNull);
      expect(
        await captions.getCaption(result.newPath!),
        'Foto: Brenno de Winter',
      );
      expect(await captions.getCaption(img.path), isNull);
    });

    test('migreert beschrijving-sidecar naar de nieuwe basename', () async {
      final img = File('${tempDir.path}/oud.png')
        ..writeAsBytesSync(_onePixelPng);
      final descriptions = DescriptionService();
      await descriptions.saveDescription(img.path, 'KLM-logo, blauw');

      final service = ImageRenameService();
      final result = await service.rename(
        oldPath: img.path,
        newStem: 'nieuw',
        deckFiles: const [],
        captionService: CaptionService(),
        descriptionService: descriptions,
      );

      expect(result.failure, isNull);
      expect(
        await descriptions.getDescription(result.newPath!),
        'KLM-logo, blauw',
      );
      expect(await descriptions.getDescription(img.path), isNull);
    });

    test('weigert als de doelnaam al bestaat met andere inhoud', () async {
      final img = File('${tempDir.path}/oud.png')
        ..writeAsBytesSync(_onePixelPng);
      // Andere inhoud: niet dezelfde bytes.
      File(
        '${tempDir.path}/bestaat.png',
      ).writeAsBytesSync([..._onePixelPng, 0x00]);

      final service = ImageRenameService();
      final result = await service.rename(
        oldPath: img.path,
        newStem: 'bestaat',
        deckFiles: const [],
        captionService: CaptionService(),
        descriptionService: DescriptionService(),
      );

      expect(result.failure, RenameFailure.targetExists);
      // Bronbestand staat nog op de oorspronkelijke naam.
      expect(img.existsSync(), isTrue);
    });

    test('geeft sourceMissing als het bronbestand niet bestaat', () async {
      final service = ImageRenameService();
      final result = await service.rename(
        oldPath: '${tempDir.path}/bestaat-niet.png',
        newStem: 'nieuw',
        deckFiles: const [],
        captionService: CaptionService(),
        descriptionService: DescriptionService(),
      );

      expect(result.failure, RenameFailure.sourceMissing);
    });
  });
}
