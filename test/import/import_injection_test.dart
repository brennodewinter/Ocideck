import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/deck_builder.dart';
import 'package:ocideck/services/import/importers/import_failure.dart';
import 'package:ocideck/services/import/importers/importer.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_image.dart';
import 'package:ocideck/services/import/models/source_format.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/models/source_table.dart';
import 'package:ocideck/services/import/pipeline/importer_registry.dart';
import 'package:ocideck/services/import/pipeline/slide_classifier.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/services/import/utils/import_budget.dart';
import 'package:ocideck/services/markdown_safety.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// #876: Markdown-/YAML-injectie uit een geïmporteerde presentatie mag geen
/// structurele betekenis of uitvoerbare inhoud in het opgeslagen deck krijgen.
///
/// Het contract is getoetst tegen de bestaande fail-closed poort: het gebouwde
/// deck, geserialiseerd, moet door `MarkdownSafetyScanner` komen — dezelfde poort
/// die een vreemd `.md` bij het openen bewaakt.
void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  BuiltDeck build(List<SourceSlide> slides, {String title = 'Deck'}) {
    final deck = SourceDeck(slides: slides, title: title);
    final classified = [for (final s in slides) classifySlide(s)];
    return DeckBuilder().build(deck, classified, title: title);
  }

  String md(Deck deck) => MarkdownService().generateDeck(deck);

  group('gesaneerde velden leveren veilige Markdown', () {
    test(
      'injectie in titel, kop, bullet, quote, tabel en notitie is inert',
      () {
        final built = build([
          SourceSlide(
            index: 0,
            title: '<script>alert(1)</script>',
            bodyBlocks: const [
              BodyBlock(kind: BodyBlockKind.bullet, text: '<iframe src="//x">'),
              BodyBlock(
                kind: BodyBlockKind.bullet,
                text: '![p](http://t/x.png)',
              ),
            ],
            notes: '<script>note()</script>',
          ),
          SourceSlide(
            index: 1,
            bodyBlocks: const [
              BodyBlock(
                kind: BodyBlockKind.quote,
                text: '<img src=x onerror=alert(1)>',
              ),
            ],
          ),
          SourceSlide(
            index: 2,
            title: 'Tabel',
            table: const SourceTable(
              header: ['<script>a</script>', 'b'],
              rows: [
                ['[x](javascript:evil)', 'gewoon'],
              ],
            ),
          ),
        ]);
        expect(MarkdownSafetyScanner.scan(md(built.deck)), isEmpty);
      },
    );

    test('een titel kan geen extra dia binnensmokkelen', () {
      final built = build([
        SourceSlide(index: 0, title: 'Echt\n\n---\n\n# Ingebroken'),
      ]);
      final out = md(built.deck);
      expect(MarkdownSafetyScanner.scan(out), isEmpty);
      // Eén brondia in, geen `---`-separator uit de titel: het deck heeft één
      // dia (plus geen extra door de injectie).
      final reopened = MarkdownService().parseDeck(out)!;
      expect(reopened.slides, hasLength(1));
    });

    test('een newline in een hyperlink-URL smokkelt geen extra dia', () {
      // Regressie (security-architect #876): de URL ging alleen door de
      // schema-check, niet door de sanitizer. Een `\n\n---\n\n# X` in de URL
      // brak uit `[tekst](url)` en maakte een dia — en de backstop zag het niet,
      // want het is geen uitvoerbare inhoud.
      final built = build([
        SourceSlide(
          index: 0,
          title: 'T',
          bodyBlocks: const [BodyBlock(kind: BodyBlockKind.bullet, text: 'x')],
          hyperlinks: const [
            (
              text: 'klik',
              url: 'https://x\n\n---\n\n# INGEBROKEN\n\n![](http://t/p.png)',
            ),
          ],
        ),
      ]);
      final out = md(built.deck);
      expect(MarkdownSafetyScanner.scan(out), isEmpty);
      expect(MarkdownService().parseDeck(out)!.slides, hasLength(1));
    });

    test('een meerregelig bijschrift smokkelt geen extra dia', () {
      // Latent (security-architect #876): een caption gaat in een HTML-`<div>`,
      // maar een lege regel gevolgd door `---` sluit dat blok en maakt een
      // thematische breuk — backstop-blind. `singleLine` vouwt dat weg.
      final built = build([
        SourceSlide(
          index: 0,
          title: 'Beeld',
          images: [
            SourceImage(
              bytes: Uint8List.fromList(const [1, 2, 3]),
              ext: 'png',
              caption: 'foto\n\n---\n\n# INGEBROKEN',
            ),
          ],
        ),
      ]);
      final out = md(built.deck);
      expect(MarkdownSafetyScanner.scan(out), isEmpty);
      expect(MarkdownService().parseDeck(out)!.slides, hasLength(1));
    });

    test(
      'een geneutraliseerde javascript:-link laat geen spoor in de poort',
      () {
        final built = build([
          SourceSlide(
            index: 0,
            title: 'T',
            hyperlinks: const [
              (text: 'klik <script>', url: 'javascript:alert(1)'),
            ],
            bodyBlocks: const [
              BodyBlock(kind: BodyBlockKind.bullet, text: 'x'),
            ],
          ),
        ]);
        expect(MarkdownSafetyScanner.scan(md(built.deck)), isEmpty);
      },
    );
  });

  group('de fail-closed backstop vangt wat een per-veld-escaper mist', () {
    test('een javascript:-link in een twee-koloms-bullet wordt gezien', () {
      // Twee horizontale clusters -> twee-koloms. Die kolom rendert als HTML
      // (`_escapeHtml`), dus een `[x](javascript:)` erin is structureel inert,
      // maar de scanner ziet het `](javascript:` — en hoort het fail-closed te
      // weigeren, want legitieme inhoud draagt dat patroon niet.
      final built = build([
        SourceSlide(
          index: 0,
          title: 'T',
          positionedTexts: const [
            PositionedText(
              text: '[x](javascript:evil)',
              left: 0.05,
              top: 0.1,
              width: 0.4,
              height: 0.3,
            ),
            PositionedText(
              text: 'rechterkolom',
              left: 0.6,
              top: 0.1,
              width: 0.4,
              height: 0.3,
            ),
          ],
        ),
      ]);
      expect(scanDeckForUnsafeContent(built.deck), isNotEmpty);
    });

    test('een schoon deck komt door de backstop', () {
      final built = build([const SourceSlide(index: 0, title: 'Gewoon deck')]);
      expect(scanDeckForUnsafeContent(built.deck), isEmpty);
    });
  });

  test('de service weigert een import met uitvoerbare inhoud', () async {
    final source = SourceDeck(
      slides: const [
        SourceSlide(
          index: 0,
          title: 'T',
          positionedTexts: [
            PositionedText(
              text: '[x](javascript:evil)',
              left: 0.05,
              top: 0.1,
              width: 0.4,
              height: 0.3,
            ),
            PositionedText(
              text: 'rechts',
              left: 0.6,
              top: 0.1,
              width: 0.4,
              height: 0.3,
            ),
          ],
        ),
      ],
    );
    final service = PresentationImportService(
      registry: ImporterRegistry(importers: [_FakeImporter(source)]),
    );
    final result = await service.importBytes(
      _pptxEnvelope(),
      filename: 'kwaad.pptx',
    );
    expect(result.isSuccess, isFalse);
    expect(result.failure!.reason, ImportFailureReason.unsafeContent);
    expect(result.failure!.args['bestand'], 'kwaad.pptx');
  });

  group(
    'YAML-front-matter is bestand tegen type-verwarring en controltekens',
    () {
      String frontMatter(Deck deck) => md(deck).split('---')[1];

      test('een gereserveerd woord als titel round-trippt als string', () {
        final deck = Deck(title: 'true', slides: const []);
        final fm = frontMatter(deck);
        expect(fm, contains('title: "true"'));
        final reopened = MarkdownService().parseDeck(md(deck))!;
        expect(reopened.title, 'true');
      });

      test('een kale CR in de titel splitst de front matter niet', () {
        final deck = Deck(title: 'regel-een\rregel-twee', slides: const []);
        final reopened = MarkdownService().parseDeck(md(deck))!;
        // Eén titelwaarde, geen extra sleutel uit de tweede helft.
        expect(reopened.title, 'regel-een\rregel-twee');
      });
    },
  );
}

/// A stand-in importer that returns a canned [SourceDeck] for the service test.
class _FakeImporter extends Importer {
  _FakeImporter(this._deck);
  final SourceDeck _deck;

  @override
  SourceFormat get format => SourceFormat.pptx;

  @override
  String get displayName => 'Fake';

  @override
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
    ImportBudget budget = ImportBudget.standard,
    Archive? preDecoded,
  }) async => Ok(_deck);
}

Uint8List _pptxEnvelope() {
  final archive = Archive();
  final data = utf8.encode('<p:presentation/>');
  archive.addFile(ArchiveFile('ppt/presentation.xml', data.length, data));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
