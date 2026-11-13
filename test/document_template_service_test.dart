import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/document_template.dart';
import 'package:ocideck/services/document_template_service.dart';

void main() {
  test(
    'empty template loads nothing; unsupported content languages use English',
    () async {
      final loaded = <String>[];
      final service = DocumentTemplateService(
        loadAsset: (key) async {
          loaded.add(key);
          return File(key).readAsStringSync();
        },
      );
      expect(await service.load(DocumentTemplate.empty, 'nl'), '');
      expect(loaded, isEmpty);
      expect(
        await service.load(DocumentTemplate.cpe, 'fr'),
        contains('Certificate of attendance'),
      );
      expect(loaded.single, 'assets/document_templates/cpe.en.md');
      expect(
        await service.load(DocumentTemplate.recipe, 'nl'),
        contains('Receptinzending'),
      );
    },
  );

  test(
    'template picker and issue actions have direct interface translations',
    () {
      for (final language in AppLocalizations.languageNames.keys.where(
        (l) => l != 'nl',
      )) {
        for (final key in [
          'Leeg document',
          'PE-bewijs',
          'Receptinzending',
          'PE-bewijzen uitgeven',
          'PE-bewijzen maken',
          'Controleer de verplichte velden en de naam, het e-mailadres en de uren van elke deelnemer.',
        ]) {
          expect(
            AppLocalizations.hasDirectDutchSourceTranslation(language, key),
            isTrue,
            reason: '$language: $key',
          );
        }
      }
    },
  );
}
