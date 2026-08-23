import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart' show fileServiceProvider;
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/markdown_paste_cleanup.dart';
import 'package:ocideck/utils/source_patcher.dart';
import 'package:ocideck/widgets/shell/document_save_actions.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Byte-getrouw opslaan vanuit de visuele editor (#1613). De visuele editor
/// round-tript Markdown → Quill → Markdown, en die weg is niet byte-getrouw:
/// witregels, tabelscheidingsregels en lijstvolgorde schuiven. Opslaan vanuit
/// Visueel moet alleen de echte bewerkingen terug schrijven, niet de hele
/// genormaliseerde bron.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    // saveDocumentWithDestination werkt de recente-bestanden-lijst bij
    // (#1676); dat gebruikt SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  /// Rond de round-trip na die de visuele editor doet: Markdown → Quill →
  /// Markdown. Dit is de baseline — wat de codec produceert zónder
  /// bewerkingen.
  String roundTrip(String source) => MarkdownQuillCodec.markdownFromDocument(
    MarkdownQuillCodec.documentFromMarkdown(normalizeRichTextMarkdown(source)),
  );

  group('patchVisualEdits met echte round-trip', () {
    test('compacte tabelscheidingsregel blijft behouden na bewerking', () {
      // Origineel met compacte scheidingsregel (zoals in #1613).
      const original = '# Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n';
      final baseline = roundTrip(original);
      // De round-trip voegt spaties toe: | A | B | en | --- | --- |
      expect(baseline, isNot(original));

      // Gebruiker voegt "Belangrijk" toe aan de kop in Visueel.
      final current = roundTrip(
        '# Belangrijke Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n',
      );
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      // De kop is gewijzigd, maar de tabel behoudt de compacte scheidingsregel.
      expect(result, contains('|---|---|'));
      expect(result, isNot(contains('| --- | --- |')));
      expect(
        result,
        '# Belangrijke Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n',
      );
    });

    test('witregels rond koppen blijven behouden na kleine bewerking', () {
      const original = '# Kop\n\nEerste alinea.\n\nTweede alinea.\n';
      final baseline = roundTrip(original);

      final current = roundTrip(
        '# Kop\n\nGewijzigde alinea.\n\nTweede alinea.\n',
      );
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      expect(result, '# Kop\n\nGewijzigde alinea.\n\nTweede alinea.\n');
    });

    test('geen bewerking → origineel byte-identiek ondanks normalisatie', () {
      const original = '# Kop\n\n|A|B|\n|---|---|\n|1|2|\n';
      final baseline = roundTrip(original);
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: baseline,
      );
      expect(result, original);
    });

    test('genummerde lijst behoudt originele vorm na bewerking elders', () {
      const original =
          '# Notitie\n\n1. Eerste punt\n2. Tweede punt\n3. Derde punt\n\nTekst.\n';
      final baseline = roundTrip(original);
      final current = roundTrip(
        '# Notitie\n\n1. Eerste punt\n2. Tweede punt\n3. Derde punt\n\nGewijzigde tekst.\n',
      );
      final result = patchVisualEdits(
        original: original,
        baseline: baseline,
        current: current,
      );
      // De genummerde lijst behoudt de originele vorm; alleen "Tekst." is
      // gewijzigd.
      expect(result, contains('1. Eerste punt'));
      expect(result, contains('2. Tweede punt'));
      expect(result, contains('3. Derde punt'));
      expect(result, contains('Gewijzigde tekst.'));
      expect(result, isNot(contains('Tekst.')));
    });
  });

  group('saveDocumentWithDestination vanuit Visueel', () {
    testWidgets('schrijft alleen de bewerking weg, niet de normalisatiedrift', (
      tester,
    ) async {
      final temp = Directory.systemTemp.createTempSync('visual_save');
      addTearDown(() => temp.deleteSync(recursive: true));
      final path = p.join(temp.path, 'notitie.md');

      // Een document met een compacte tabelscheidingsregel.
      const source = '# Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n';
      final doc = MarkdownDocument.parse(source);
      final notifier = DocumentNotifier()..loadDocument(doc, filePath: path);

      // Simuleer een visuele bewerking: de gebruiker voegt "Belangrijk" toe
      // aan de kop. De notifier krijgt de genormaliseerde round-trip met
      // visualEdit: true.
      final editedSource = roundTrip(
        '# Belangrijke Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n',
      );
      notifier.edit(editedSource, visualEdit: true);

      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentProvider.overrideWith((_) => notifier),
            fileServiceProvider.overrideWithValue(
              FileService(
                MarkdownService(),
                ImageService(),
                () => throw UnimplementedError(),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, r, _) {
                ref = r;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final saved = await tester.runAsync(
        () => saveDocumentWithDestination(
          tester.element(find.byType(SizedBox)),
          ref,
          notifier,
        ),
      );
      expect(saved, isTrue);

      // Het bestand op schijf moet de compacte tabelscheidingsregel behouden.
      final onDisk = File(path).readAsStringSync();
      expect(onDisk, contains('|---|---|'));
      expect(onDisk, isNot(contains('| --- | --- |')));
      expect(
        onDisk,
        '# Belangrijke Notitie\n\n|A|B|\n|---|---|\n|1|2|\n\nTekst.\n',
      );

      // De notifier is nu schoon en heeft de byte-getrouwe versie.
      expect(notifier.currentState.isDirty, isFalse);
      expect(notifier.currentState.visualEdited, isFalse);
      expect(notifier.currentState.document!.source, onDisk);
    });

    testWidgets('opslaan vanuit Bron is byte-getrouw zonder patching', (
      tester,
    ) async {
      final temp = Directory.systemTemp.createTempSync('source_save');
      addTearDown(() => temp.deleteSync(recursive: true));
      final path = p.join(temp.path, 'notitie.md');

      const source = '# Notitie\n\nTekst.\n';
      final doc = MarkdownDocument.parse(source);
      final notifier = DocumentNotifier()..loadDocument(doc, filePath: path);

      // Bewerking in Bron (geen visualEdit): de bron is wat de gebruiker typte.
      notifier.edit('# Gewijzigde Notitie\n\nTekst.\n');

      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentProvider.overrideWith((_) => notifier),
            fileServiceProvider.overrideWithValue(
              FileService(
                MarkdownService(),
                ImageService(),
                () => throw UnimplementedError(),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, r, _) {
                ref = r;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final saved = await tester.runAsync(
        () => saveDocumentWithDestination(
          tester.element(find.byType(SizedBox)),
          ref,
          notifier,
        ),
      );
      expect(saved, isTrue);

      final onDisk = File(path).readAsStringSync();
      expect(onDisk, '# Gewijzigde Notitie\n\nTekst.\n');
    });
  });
}
