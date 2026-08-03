import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/shell/presentation_import_action.dart';

/// Regressie voor #1175: wie een `.odp` (of `.pptx`/`.key`) via "Openen" koos,
/// liep dood op "OciDeck opent Markdown" en vond de importroute niet. De
/// herkenning hieronder is de kern van de uitweg: een presentatie krijgt een
/// import-aanbod, Markdown en andere bestanden blijven met rust.
void main() {
  const l10n = AppLocalizations(Locale('nl'));

  group('isImportablePresentationName', () {
    test('herkent de drie importformaten, hoofdletters inbegrepen', () {
      expect(isImportablePresentationName('talk.odp'), isTrue);
      expect(isImportablePresentationName('deck.pptx'), isTrue);
      expect(isImportablePresentationName('keynote.key'), isTrue);
      expect(isImportablePresentationName('LUID.ODP'), isTrue);
      expect(isImportablePresentationName('/home/kwoot/verhaal.odp'), isTrue);
    });

    test('laat Markdown en andere bestanden met rust', () {
      expect(isImportablePresentationName('notities.md'), isFalse);
      expect(isImportablePresentationName('deck.ocideck'), isFalse);
      expect(isImportablePresentationName('plaatje.png'), isFalse);
      expect(isImportablePresentationName('README'), isFalse);
      // Punt zit alleen in een map, het bestand zelf heeft geen extensie.
      expect(isImportablePresentationName('map.v2/losbestand'), isFalse);
    });
  });

  group('presentationOpenRescue', () {
    test('geen uitweg voor een niet-presentatie', () {
      expect(
        presentationOpenRescue(
          l10n,
          'notities.md',
          importModuleAvailable: true,
        ),
        isNull,
      );
    });

    test('module aan: biedt aan om meteen te importeren', () {
      final rescue = presentationOpenRescue(
        l10n,
        'talk.odp',
        importModuleAvailable: true,
      );
      expect(rescue, isNotNull);
      expect(rescue!.startsImport, isTrue);
      // De melding zegt wat het is én dat OciDeck het kan omzetten.
      expect(rescue.message, contains('presentatie'));
      expect(rescue.message.toLowerCase(), contains('importeren'));
    });

    test('module uit: wijst naar de instellingen, importeert niet stil', () {
      final rescue = presentationOpenRescue(
        l10n,
        'talk.odp',
        importModuleAvailable: false,
      );
      expect(rescue, isNotNull);
      expect(rescue!.startsImport, isFalse);
      expect(rescue.message, contains('module'));
    });
  });
}
