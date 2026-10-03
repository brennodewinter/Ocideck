import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart' show fileServiceProvider;
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/tabs_provider.dart'
    show importSecurityAlarmProvider;
import 'package:ocideck/utils/markdown_paste_cleanup.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/utf8_bom.dart';
import 'package:ocideck/widgets/shell/document_save_actions.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// De poort-test van DOCUMENT_MODE.md §3.1: openen → niet bewerken → opslaan
/// levert **byte-identieke** uitvoer op. Gemeten op 2026-09-30 lekte dat bij een
/// leidende UTF-8-BOM (`EF BB BF`): Dart's `readAsString()` en `utf8.decode`
/// gooien hem weg, `utf8.encode` schrijft hem niet terug.
///
/// Bewust via **echte bestanden** en niet via een string-fixture: zet je de BOM
/// als `'﻿…'` in een string, dan slaagt `MarkdownDocument.parse` wél — het
/// verlies zit in de byte↔string-grens, en die bestaat alleen met een bestand.
FileService _service() =>
    FileService(MarkdownService(), ImageService(), () => ThemeProfile());

const _host = Key('host');

const _bom = [0xEF, 0xBB, 0xBF];

/// De bytes uit de bevinding: `# a` met een BOM ervoor en CRLF erachter.
const _measured = [..._bom, 0x23, 0x20, 0x61, 0x0D, 0x0A];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('doc_bom');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<MarkdownDocument> open(String path) async {
    final opened = await _service().openDocumentDetailed(path);
    expect(opened.failure, isNull);
    return opened.document!;
  }

  /// Open [bytes] als document vanaf een echt bestand en sla het ongewijzigd op
  /// naar een tweede bestand; geeft de bytes terug die daar staan.
  Future<List<int>> openAndSave(List<int> bytes) async {
    final src = p.join(temp.path, 'in.md');
    final dst = p.join(temp.path, 'uit.md');
    File(src).writeAsBytesSync(bytes);
    final written = await saveDocument(await open(src), dst);
    expect(written, isNotNull);
    return File(dst).readAsBytesSync();
  }

  group('open → opslaan via een echt bestand (§3.1)', () {
    test('de gemeten bytes: BOM + CRLF komen byte-identiek terug', () async {
      expect(await openAndSave(_measured), _measured);
    });

    test('een bestand zonder BOM krijgt er ook geen bij', () async {
      const plain = [0x23, 0x20, 0x61, 0x0D, 0x0A];
      expect(await openAndSave(plain), plain);
    });

    test('BOM + front matter + niet-ASCII blijft byte-identiek', () async {
      final bytes = [
        ..._bom,
        ...utf8.encode('---\ntheme: rvs\n---\n\n# Één café — “zo”\n'),
      ];
      expect(await openAndSave(bytes), bytes);
    });

    test('alleen een BOM (drie bytes) blijft drie bytes', () async {
      expect(await openAndSave(_bom), _bom);
    });

    test('een tweede BOM erachter is inhoud en blijft staan', () async {
      // Alleen de eerste EF BB BF is de markering; wat erna komt is tekst.
      final bytes = [..._bom, ..._bom, 0x23, 0x20, 0x61, 0x0A];
      expect(await openAndSave(bytes), bytes);
    });

    test(
      'de BOM zit niet in de bron: stijl en koppen blijven leesbaar',
      () async {
        final src = p.join(temp.path, 'stijl.md');
        File(src).writeAsBytesSync([
          ..._bom,
          ...utf8.encode('---\ntheme: rvs\n---\n\n# Kop\n'),
        ]);
        final doc = await open(src);
        expect(doc.source, startsWith('---\n'));
        expect(doc.styleName, 'rvs');
        expect(doc.outline.map((e) => e.title), contains('Kop'));
      },
    );

    test('een bewerking behoudt de BOM', () async {
      final src = p.join(temp.path, 'in.md');
      File(src).writeAsBytesSync(_measured);
      final edited = (await open(src)).withSource('# b\r\n');
      final dst = p.join(temp.path, 'uit.md');
      await saveDocument(edited, dst);
      expect(File(dst).readAsBytesSync(), [
        ..._bom,
        0x23,
        0x20,
        0x62,
        0x0D,
        0x0A,
      ]);
    });
  });

  group('opslaan via de app-route (conflict-hash, visuele opslag)', () {
    Future<WidgetRef> pump(
      WidgetTester tester,
      DocumentNotifier notifier,
    ) async {
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentProvider.overrideWith((_) => notifier),
            fileServiceProvider.overrideWithValue(_service()),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            // Een Scaffold, anders toont de ScaffoldMessenger zijn snackbar niet.
            home: Scaffold(
              body: Consumer(
                builder: (context, r, _) {
                  ref = r;
                  return const SizedBox.shrink(key: _host);
                },
              ),
            ),
          ),
        ),
      );
      return ref;
    }

    /// Opslaan met een wachttijd waarin een (ten onrechte) verschenen
    /// conflictdialoog zichtbaar wordt, in plaats van de test te laten hangen.
    Future<bool> save(
      WidgetTester tester,
      WidgetRef ref,
      DocumentNotifier notifier,
    ) async {
      bool? result;
      unawaited(
        saveDocumentWithDestination(
          tester.element(find.byKey(_host)),
          ref,
          notifier,
        ).then((v) => result = v),
      );
      await pumpUntil(
        tester,
        () => result != null || find.byType(AlertDialog).evaluate().isNotEmpty,
        reason: 'opslaan gaf niets terug',
      );
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'een ongewijzigd bestand met BOM is geen "gewijzigd door een '
            'ander programma"',
      );
      return result ?? false;
    }

    testWidgets(
      'BOM-bestand bewerken en opslaan: geen vals conflict, BOM blijft',
      (tester) async {
        final path = p.join(temp.path, 'rapport.md');
        File(path).writeAsBytesSync(_measured);
        final doc = (await tester.runAsync(() => open(path)))!;
        final notifier = DocumentNotifier()..loadDocument(doc, filePath: path);
        // De hash die de notifier onthoudt is die van de bytes op schijf.
        expect(
          notifier.currentState.savedFileHash,
          DocumentIntegrity.hashBytes(File(path).readAsBytesSync()),
        );

        notifier.edit('# b\r\n');
        final ref = await pump(tester, notifier);
        expect(await save(tester, ref, notifier), isTrue);

        expect(File(path).readAsBytesSync(), [
          ..._bom,
          0x23,
          0x20,
          0x62,
          0x0D,
          0x0A,
        ]);
        // En na het opslaan klopt de hash weer met wat er nu staat.
        expect(
          notifier.currentState.savedFileHash,
          DocumentIntegrity.hashBytes(File(path).readAsBytesSync()),
        );
      },
    );

    testWidgets('opslaan vanuit Visueel behoudt de BOM', (tester) async {
      final path = p.join(temp.path, 'visueel.md');
      File(
        path,
      ).writeAsBytesSync([..._bom, ...utf8.encode('# Kop\n\nEerste regel.\n')]);
      final doc = (await tester.runAsync(() => open(path)))!;
      final notifier = DocumentNotifier()..loadDocument(doc, filePath: path);
      final edited = MarkdownQuillCodec.markdownFromDocument(
        MarkdownQuillCodec.documentFromMarkdown(
          normalizeRichTextMarkdown('# Kop\n\nEerste regelx.\n'),
        ),
      );
      notifier.edit(edited, visualEdit: true);
      final ref = await pump(tester, notifier);
      expect(await save(tester, ref, notifier), isTrue);

      expect(File(path).readAsBytesSync(), [
        ..._bom,
        ...utf8.encode('# Kop\n\nEerste regelx.\n'),
      ]);
    });

    testWidgets('Herladen na een extern conflict leest UTF-8 en BOM goed in', (
      tester,
    ) async {
      final path = p.join(temp.path, 'conflict.md');
      File(path).writeAsBytesSync([..._bom, ...utf8.encode('# Eén\n')]);
      final doc = (await tester.runAsync(() => open(path)))!;
      final notifier = DocumentNotifier()..loadDocument(doc, filePath: path);
      notifier.edit('# Eén bewerkt\n');
      // Een ander programma schrijft het bestand ondertussen opnieuw.
      File(
        path,
      ).writeAsBytesSync([..._bom, ...utf8.encode('# Één café — “zo”\n')]);

      final ref = await pump(tester, notifier);
      bool? result;
      unawaited(
        saveDocumentWithDestination(
          tester.element(find.byKey(_host)),
          ref,
          notifier,
        ).then((v) => result = v),
      );
      await pumpUntil(
        tester,
        () => find.text('Herladen').evaluate().isNotEmpty,
        reason: 'de conflictdialoog verscheen niet',
      );
      await tester.tap(find.text('Herladen'));
      await pumpUntil(
        tester,
        () => result != null,
        reason: 'het herladen kwam niet terug',
      );

      // Herladen schrijft niets: de notifier neemt het bestand over zoals het is.
      expect(result, isFalse);
      final reloaded = notifier.currentState.document!;
      expect(reloaded.source, '# Één café — “zo”\n');
      expect(reloaded.hasUtf8Bom, isTrue);
      expect(notifier.currentState.isDirty, isFalse);
      expect(
        notifier.currentState.savedFileHash,
        DocumentIntegrity.hashBytes(File(path).readAsBytesSync()),
      );
    });

    /// Laat "Herladen" lopen na een extern conflict waarbij het bestand door een
    /// ander programma is overschreven met [external].
    Future<DocumentNotifier> reloadAfterConflict(
      WidgetTester tester,
      List<int> external,
    ) async {
      final path = p.join(temp.path, 'geweigerd.md');
      File(path).writeAsBytesSync(utf8.encode('# Mijn werk\n'));
      final doc = (await tester.runAsync(() => open(path)))!;
      final notifier = DocumentNotifier()..loadDocument(doc, filePath: path);
      notifier.edit('# Mijn werk, bewerkt\n');
      File(path).writeAsBytesSync(external);

      final ref = await pump(tester, notifier);
      unawaited(
        saveDocumentWithDestination(
          tester.element(find.byKey(_host)),
          ref,
          notifier,
        ),
      );
      await pumpUntil(
        tester,
        () => find.text('Herladen').evaluate().isNotEmpty,
        reason: 'de conflictdialoog verscheen niet',
      );
      await tester.tap(find.text('Herladen'));
      return notifier;
    }

    testWidgets('een geweigerde herlaad meldt dat, en laat het werk staan', (
      tester,
    ) async {
      // Een ander programma slaat het bestand als UTF-16 op: geen geldige UTF-8.
      final notifier = await reloadAfterConflict(tester, [
        0xFF,
        0xFE,
        0x23,
        0x00,
      ]);
      await pumpUntil(
        tester,
        () => find
            .text('Dit bestand is geen leesbare tekst. OciDeck opent Markdown.')
            .evaluate()
            .isNotEmpty,
        reason: 'de melding verscheen niet: Herladen deed stil niets',
      );
      // Het werk van de gebruiker is niet overschreven.
      expect(notifier.currentState.document!.source, '# Mijn werk, bewerkt\n');
      expect(notifier.currentState.isDirty, isTrue);
    });

    testWidgets('een onveilig bestand bij Herladen zet het veiligheidsalarm', (
      tester,
    ) async {
      final notifier = await reloadAfterConflict(
        tester,
        utf8.encode('# Titel\n\n<script>alert(1)</script>\n'),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(_host)),
      );
      await pumpUntil(
        tester,
        () => container.read(importSecurityAlarmProvider) != null,
        reason: 'het alarm werd niet gezet: onveilige inhoud kwam stil binnen',
      );
      expect(container.read(importSecurityAlarmProvider)!.findings, isNotEmpty);
      expect(notifier.currentState.document!.source, '# Mijn werk, bewerkt\n');
    });
  });

  group('het deckpad (gedeconstrueerd: geen byte-identiteitsbelofte)', () {
    const deck = '---\nmarp: true\ntheme: ocideck\n---\n\n# Dia\n';

    test('een deck met BOM opent zonder klachten', () async {
      final src = p.join(temp.path, 'deck.md');
      File(src).writeAsBytesSync([..._bom, ...utf8.encode(deck)]);
      final opened = await _service().openDeckDetailed(src);
      expect(opened.failure, isNull);
      expect(opened.deck, isNotNull);
    });

    test(
      'opslaan schrijft het deck zonder BOM, zoals een deck zonder BOM',
      () async {
        // Een deck wordt bij het openen tot slides gedeconstrueerd en bij het
        // opslaan opnieuw gegenereerd; zonder BOM is daar de gekozen vorm. Dit
        // pint het gemeten gedrag vast (2026-09-30) — het is bewust *anders* dan
        // het documentpad, dat de BOM wél teruggeeft.
        final withBom = p.join(temp.path, 'met.md');
        final without = p.join(temp.path, 'zonder.md');
        File(withBom).writeAsBytesSync([..._bom, ...utf8.encode(deck)]);
        File(without).writeAsBytesSync(utf8.encode(deck));
        final a = (await _service().openDeckDetailed(withBom)).deck!;
        final b = (await _service().openDeckDetailed(without)).deck!;
        await _service().saveDeck(a, withBom);
        await _service().saveDeck(b, without);
        final saved = File(withBom).readAsBytesSync();
        expect(startsWithUtf8Bom(saved), isFalse);
        expect(saved, File(without).readAsBytesSync());
      },
    );
  });

  group('utf8_bom', () {
    test('decodeUtf8KeepingBomFlag haalt precies één BOM van de tekst', () {
      expect(decodeUtf8KeepingBomFlag(_measured), (
        text: '# a\r\n',
        hasBom: true,
      ));
      expect(decodeUtf8KeepingBomFlag([..._bom, ..._bom, 0x61]), (
        text: '\uFEFFa',
        hasBom: true,
      ));
      expect(decodeUtf8KeepingBomFlag([0x61, ..._bom]), (
        text: 'a\uFEFF',
        hasBom: false,
      ));
      expect(decodeUtf8KeepingBomFlag(const <int>[]), (
        text: '',
        hasBom: false,
      ));
    });

    test('ongeldige UTF-8 blijft een FormatException', () {
      expect(
        () => decodeUtf8KeepingBomFlag([..._bom, 0xFF, 0xFE]),
        throwsFormatException,
      );
    });

    test('decoderen en coderen geeft de bytes terug', () {
      for (final bytes in <List<int>>[
        _measured,
        _bom,
        [..._bom, ..._bom, 0x61],
        [0x61, 0x0A],
        const <int>[],
      ]) {
        final d = decodeUtf8KeepingBomFlag(bytes);
        expect(encodeUtf8WithBom(d.text, hasBom: d.hasBom), bytes);
      }
    });

    test('startsWithUtf8Bom kent ook korte invoer', () {
      expect(startsWithUtf8Bom(const <int>[]), isFalse);
      expect(startsWithUtf8Bom(const [0xEF, 0xBB]), isFalse);
      expect(startsWithUtf8Bom(_bom), isTrue);
    });
  });

  group('MarkdownDocument', () {
    test('de BOM-vlag reist mee door withSource, toBytes en hashDocument', () {
      final doc = MarkdownDocument.parse('# a\r\n', hasUtf8Bom: true);
      expect(doc.toBytes(), _measured);
      final next = doc.withSource('# b\r\n');
      expect(next.hasUtf8Bom, isTrue);
      expect(
        DocumentIntegrity.hashDocument(next),
        DocumentIntegrity.hashBytes(next.toBytes()),
      );
      // Zonder BOM is de hash die van de tekst, zoals vóór deze wijziging.
      final plain = MarkdownDocument.parse('# a\r\n');
      expect(plain.hasUtf8Bom, isFalse);
      expect(
        DocumentIntegrity.hashDocument(plain),
        DocumentIntegrity.hashMarkdown('# a\r\n'),
      );
      expect(
        DocumentIntegrity.hashDocument(doc),
        isNot(DocumentIntegrity.hashMarkdown('# a\r\n')),
      );
    });
  });
}
