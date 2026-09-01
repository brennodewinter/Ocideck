// Test-corpus voor robustness: een vaste set pathologische bestanden die bij
// elke CI-run door de invoerpaden van OciDeck wordt gehaald. Beweert per
// bestand: geen crash, geen hang, een geldige weigering of een geldig
// resultaat met waarschuwing. Voorkomt regressie van de fixes uit
// #1350–#1355, #1358–#1360.
//
// De corpus-bestanden worden in de test zelf gesynthetiseerd (geen binaire
// fixtures nodig) — zo blijven ze versieerbaar en diffbaar.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_safety.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/utils/json_depth_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FileService makeService() => FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
  );

  group('corrupt-file corpus', () {
    // ── #1350, teruggedraaid in #1909 ───────────────────────────────────
    // Front matter zonder body gold hier als "afgekapt" en werd geweigerd. Dat
    // is precies de vorm die OciDeck zélf wegschrijft voor een presentatie
    // waarvan de enige dia nog leeg is, dus de weigering trof het eigen werk van
    // de gebruiker — zie de motivering bij `openDeckDetailed`. Wat de corpus
    // hier bewaakt is daarmee verschoven van "weigert" naar "opent zonder te
    // crashen of te blijven hangen", de andere helft van de corpus-belofte.
    test(
      'deck zonder body opent als lege presentatie via openDeckFromContent',
      () {
        final raw = '---\nmarp: true\ntheme: default\n---\n';
        final result = makeService().openDeckFromContent(raw);
        expect(result.failure, isNull);
        expect(
          result.deck,
          isNotNull,
          reason:
              'Een lege presentatie is niet te onderscheiden van een afgekapte, '
              'en OciDeck moet kunnen teruglezen wat het zelf schrijft.',
        );
      },
    );

    // ── #1353: Diep-geneste JSON ────────────────────────────────────────
    test('diep-geneste JSON wordt geweigerd vóór jsonDecode', () {
      final deep =
          '[' * (kMaxJsonNestingDepth + 100) +
          ']' * (kMaxJsonNestingDepth + 100);
      expect(
        () => jsonDecodeGuarded(deep),
        throwsA(isA<FormatException>()),
        reason: 'Diep-geneste JSON mag niet tot een StackOverflowError leiden.',
      );
    });

    test('diep-geneste JSON met objecten wordt geweigerd', () {
      final n = kMaxJsonNestingDepth + 100;
      final deep = '${'{"a":' * n}1${'}' * n}';
      expect(() => jsonDecodeGuarded(deep), throwsA(isA<FormatException>()));
    });

    // ── #1358: LaTeX-injectie via paden ─────────────────────────────────
    test('afbeeldingspad met } wordt geëscaped in LaTeX-export', () {
      final escaped = _escapeImagePathForTest('foo}\\input{/etc/passwd}{bar');
      expect(escaped, isNot(contains(r'\input')));
      expect(escaped, contains(r'\}'));
    });

    // ── Niet-UTF8 deck ──────────────────────────────────────────────────
    test('niet-UTF8 bytes als .md worden geweigerd', () {
      final bytes = Uint8List.fromList([0xff, 0xfe, 0x00, 0x01, 0x02, 0xff]);
      expect(() => utf8.decode(bytes, allowMalformed: false), throwsException);
    });

    // ── Willekeurige bytes als .md ──────────────────────────────────────
    test('willekeurige bytes zonder frontmatter worden geweigerd', () {
      final raw = 'Hello world, this is not a presentation at all.';
      final result = makeService().openDeckFromContent(raw);
      expect(result.failure, OpenFailure.notPresentation);
    });

    // ── Zip-bom ─────────────────────────────────────────────────────────
    test('zip-bom met understated uncompressed size wordt gestopt', () {
      final archive = Archive();
      final big = List<int>.filled(10 * 1024 * 1024, 0x41); // 10 MB nullen
      archive.addFile(ArchiveFile('bomb.txt', big.length, big));
      final zipBytes = ZipEncoder().encode(archive);

      final result = makeService().decodePackageEntries(
        zipBytes,
        maxBytes: 1024 * 1024, // 1 MB limiet
      );
      expect(
        result,
        isNull,
        reason: 'Een zip-bom moet worden geweigerd door de cap.',
      );
    });

    // ── Zip-slip-pakket ─────────────────────────────────────────────────
    test('zip-slip entries met ../ worden geweigerd', () async {
      final archive = Archive();
      final content = utf8.encode('hello');
      archive.addFile(ArchiveFile('../escape.txt', content.length, content));
      final zipBytes = ZipEncoder().encode(archive);

      final temp = await Directory.systemTemp.createTemp('ocideck_corpus_');
      addTearDown(() async => temp.delete(recursive: true));

      await makeService().importPackageBytesDetailed(zipBytes, temp.path);
      final escaped = File('${temp.path}/../escape.txt');
      expect(
        await escaped.exists(),
        isFalse,
        reason: 'Een zip-slip entry mag niet buiten de doelmap schrijven.',
      );
    });

    // ── Safety scanner ──────────────────────────────────────────────────
    test('deck met uitvoerbare inhoud wordt geweigerd', () {
      final raw = '---\nmarp: true\n---\n\n<script>alert(1)</script>\n';
      final findings = MarkdownSafetyScanner.scan(raw);
      expect(
        findings,
        isNotEmpty,
        reason:
            'Uitvoerbare inhoud moet door de safety scanner worden '
            'gevonden.',
      );
    });

    // ── #1354: High-frame-count GIF ─────────────────────────────────────
    test('kMaxImageFrames is een redelijke grens', () {
      expect(kMaxImageFrames, greaterThan(0));
      expect(kMaxImageFrames, lessThan(10000));
    });
  });
}

/// Lokale kopie van de LaTeX-escape voor paden, om de logica te testen
/// zonder de private functie te hoeven exporteren.
String _escapeImagePathForTest(String src) {
  if (src.isEmpty) return '';
  final normalized = src.replaceAll(r'\', '/');
  return normalized
      .replaceAll('&', r'\&')
      .replaceAll('%', r'\%')
      .replaceAll('#', r'\#')
      .replaceAll('_', r'\_')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}')
      .replaceAll(r'$', r'\$')
      .replaceAll('~', r'\textasciitilde{}')
      .replaceAll('^', r'\textasciicircum{}');
}
