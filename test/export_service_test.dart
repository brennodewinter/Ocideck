import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/services/classification_policy.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/quality_export_policy.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'support/export_bundle_fixture.dart';

Uint8List _png() {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(30, 40, 60));
  return Uint8List.fromList(img.encodePng(image));
}

/// A photo-like PNG full of pseudo-random pixels, where lossless PNG is large
/// and JPEG compression pays off — used to assert the compressed PDF shrinks.
Uint8List _noisyPng() {
  // Wider than ExportService's compressed target width so the export exercises
  // both the JPEG re-encode and the downscale path.
  final image = img.Image(width: 1600, height: 900);
  var seed = 1234567;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      image.setPixelRgb(
        x,
        y,
        seed & 0xff,
        (seed >> 8) & 0xff,
        (seed >> 16) & 0xff,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Matches a leading UTC timestamp prefix: `YYYYMMDDHHMMSS ` (e.g. `20260603124547 `).
final _dtgPrefix = RegExp(r'^\d{14} ');

void main() {
  late Directory tmp;
  late ExportService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ocideck_export');
    service = ExportService();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String deckPath() => p.join(tmp.path, 'deck.md');

  test(
    'classificatie-gate blocks an over-classified export, writes nothing',
    () async {
      const policy = ClassificationEnforcementPolicy(
        maxReleaseLevel: TlpLevel.green,
      );
      final r = await service.export(
        deckPath(),
        ExportFormat.pdf,
        [_png()],
        tlp: TlpLevel.red,
        enforcementPolicy: policy,
      );

      expect(r.success, isFalse);
      expect(r.outputPath, isNull);
      // Sinds #576 draagt het resultaat de beslissing en niet een zin — die
      // wordt in de schil gemaakt, in de taal van de gebruiker.
      expect(r.classificationDecision?.reason, ExportBlockReason.aboveCeiling);
      // Fail-closed: no file may be produced when the gate refuses.
      final produced = tmp.listSync().whereType<File>().where(
        (f) => p.extension(f.path) == '.pdf',
      );
      expect(produced, isEmpty);
    },
  );

  test('classificatie-gate allows an export at or below the ceiling', () async {
    const policy = ClassificationEnforcementPolicy(
      maxReleaseLevel: TlpLevel.amber,
    );
    final r = await service.export(
      deckPath(),
      ExportFormat.pdf,
      [_png()],
      tlp: TlpLevel.green,
      enforcementPolicy: policy,
    );
    expect(r.success, isTrue, reason: r.error);
  });

  test(
    'enforcement blocks export below the required minimum, writes nothing',
    () async {
      const policy = ClassificationEnforcementPolicy(
        minRequiredLevel: TlpLevel.green,
      );
      final r = await service.export(
        deckPath(),
        ExportFormat.pdf,
        [_png()],
        tlp: TlpLevel.clear,
        enforcementPolicy: policy,
      );

      expect(r.success, isFalse);
      expect(r.classificationDecision?.reason, ExportBlockReason.belowMinimum);
      expect(
        tmp.listSync().whereType<File>().where(
          (f) => p.extension(f.path) == '.pdf',
        ),
        isEmpty,
      );
    },
  );

  test(
    'enforcement blocks unclassified export when classification is required',
    () async {
      const policy = ClassificationEnforcementPolicy(
        requireClassification: true,
      );
      final r = await service.export(deckPath(), ExportFormat.pdf, [
        _png(),
      ], enforcementPolicy: policy);

      expect(r.success, isFalse);
      expect(
        r.classificationDecision?.reason,
        ExportBlockReason.classificationMissing,
      );
    },
  );

  test(
    'quality gate blocks export until acknowledged, writes nothing',
    () async {
      const policy = QualityExportPolicy();
      const quality = SlideQualityResult([
        SlideQualityIssue(
          slideIndex: 0,
          kind: SlideQualityIssueKind.missingAltCaption,
          category: SlideQualityCategory.altText,
          severity: MarkdownValidationSeverity.warning,
        ),
      ]);
      final blocked = await service.export(
        deckPath(),
        ExportFormat.pdf,
        [_png()],
        qualityResult: quality,
        qualityPolicy: policy,
      );

      expect(blocked.success, isFalse);
      expect(blocked.error, contains('kwaliteitsproblemen'));

      final allowed = await service.export(
        deckPath(),
        ExportFormat.pdf,
        [_png()],
        qualityResult: quality,
        qualityPolicy: policy,
        qualityAcknowledged: true,
      );
      expect(allowed.success, isTrue, reason: allowed.error);
    },
  );

  test('exports a PDF that starts with the PDF magic header', () async {
    final images = [_png(), _png()];
    final r = await service.export(deckPath(), ExportFormat.pdf, images);

    expect(r.success, isTrue, reason: r.error);
    final bytes = await File(r.outputPath!).readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('een geredigeerde export legt zijn manifest ernaast neer', () async {
    // Zonder manifest kan een ontvanger geen enkele redactie natrekken. Beide
    // bestanden horen te verschijnen: de commitments (reizen mee) en de
    // verificatiesleutels (houdt de auteur).
    const manifest = RedactionManifest(
      derivedFrom: 'seal-abc',
      entries: [
        RedactionEntry(
          id: 'a3f1',
          commitment: 'deadbeef',
          rule: 'nl.bsn',
          slideIndex: 0,
          field: 'body',
          salt: 'peper',
        ),
      ],
    );
    final r = await service.export(deckPath(), ExportFormat.pdf, [
      _png(),
    ], redactionManifest: manifest);
    expect(r.success, isTrue, reason: r.error);

    final base = p.basenameWithoutExtension(r.outputPath!);
    final commitments = File(
      p.join(tmp.path, '$base$kRedactionManifestSuffix'),
    );
    final keys = File(p.join(tmp.path, '$base$kRedactionKeysSuffix'));
    expect(await commitments.exists(), isTrue);
    expect(await keys.exists(), isTrue);
    // De commitments-versie draagt de salt niet; de sleutelversie wel.
    expect(await commitments.readAsString(), isNot(contains('peper')));
    expect(await keys.readAsString(), contains('peper'));

    // De waarschuwing hoort ín het bestand. De naam verdwijnt zodra iemand het
    // hernoemt of in een zip stopt; dan is de inhoud het enige wat nog vertelt
    // dat dit bestand elke redactie ongedaan maakt.
    expect(await keys.readAsString(), contains(kRedactionKeysNotice));
    expect(
      await commitments.readAsString(),
      contains(kRedactionManifestNotice),
      reason: 'ook het onschuldige bestand hoort te zeggen wat het is',
    );
    expect(
      await commitments.readAsString(),
      isNot(contains(kRedactionKeysNotice)),
      reason: 'het meereizende manifest mag niet als "bewaar dit" lezen',
    );
  });

  test('de bestandsnamen zijn taalonafhankelijk en niet te verwisselen', () {
    // Ze heetten `-redacties.json` en `-redacties-verificatiesleutels.json`:
    // twee Nederlandse namen die op elkaar lijken, in een app met 32 talen en
    // ontvangers in evenzovele. De scheiding tussen die twee bestanden ís de
    // beveiliging, dus ze moet leesbaar zijn zonder Nederlands te kennen.
    expect(kRedactionManifestSuffix, isNot(contains('redacties')));
    expect(kRedactionKeysSuffix, isNot(contains('verificatiesleutels')));
    expect(
      kRedactionKeysSuffix.startsWith(
        kRedactionManifestSuffix.replaceAll('.json', ''),
      ),
      isFalse,
      reason:
          'het sleutelbestand mag geen verlengstuk van de andere naam zijn — '
          'dan staan ze naast elkaar in de verkenner en pak je de verkeerde',
    );
  });

  test('PDF embeds OciDeck as Creator and Producer', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, [_png()]);
    expect(r.success, isTrue, reason: r.error);
    final text = String.fromCharCodes(await File(r.outputPath!).readAsBytes());
    expect(text, contains('/Creator'));
    expect(text, contains('/Producer'));
    expect(text, contains(kOciDeckCreator));
    expect(text, contains(kOciDeckProducer));
  });

  test('PDF embeds classification metadata when classified', () async {
    const metadata = ExportDocumentMetadata(
      title: 'Kwartaalupdate',
      author: 'Alex',
      keywords: 'kwartaal',
      tlp: TlpLevel.amber,
    );
    final r = await service.export(
      deckPath(),
      ExportFormat.pdf,
      [_png()],
      tlp: TlpLevel.amber,
      metadata: metadata,
    );
    expect(r.success, isTrue, reason: r.error);
    final text = String.fromCharCodes(await File(r.outputPath!).readAsBytes());
    expect(text, contains('TLP:AMBER'));
    expect(text, contains('Kwartaalupdate'));
    expect(text, contains('OciDeck'));
  });

  // ── AI-markering overleeft de export (AI-verordening art. 50) ─────────────
  // De markering leefde alleen binnen de app: hij blokkeerde het verzegelen en
  // was zichtbaar in de editor, maar wie het bestand kreeg zag niets. Deze drie
  // tests zijn de bestandsgrens.
  const aiMeta = ExportDocumentMetadata(
    title: 'Conceptrapport',
    unreviewedAiSlideCount: 2,
  );

  test(
    'PDF declares the unreviewed AI text in its document properties',
    () async {
      final r = await service.export(deckPath(), ExportFormat.pdf, [
        _png(),
      ], metadata: aiMeta);
      expect(r.success, isTrue, reason: r.error);
      final bytes = await File(r.outputPath!).readAsBytes();
      final text = String.fromCharCodes(bytes);
      // De Info-dict ontkomt de haakjes van de markering (dat is
      // PDF-tekenreekssyntaxis), dus toetsen we de ontkomen vorm.
      expect(text, contains('/Keywords'));
      expect(text, contains(r'AI-generated \(unreviewed\)'));
      // Het Subject draagt een em-streepje en gaat daardoor als UTF-16BE de
      // dict in: elk teken krijgt een nulbyte ernaast. Die wegstrepen maakt de
      // zin weer leesbaar zonder de rest van het bestand te ontleden.
      final zonderNullen = String.fromCharCodes(bytes.where((b) => b != 0));
      expect(zonderNullen, contains(kAiDraftSubjectNote));
    },
  );

  test('PPTX core properties carry the same marking', () async {
    final r = await service.export(deckPath(), ExportFormat.pptx, [
      _png(),
    ], metadata: aiMeta);
    expect(r.success, isTrue, reason: r.error);
    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final core = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'docProps/core.xml').content
          as List<int>,
    );
    expect(core, contains(kAiDraftKeyword));
    expect(core, contains(kAiDraftSubjectNote));
  });

  test(
    'the file name marks a draft, and stops doing so once reviewed',
    () async {
      final draft = await service.export(deckPath(), ExportFormat.pdf, [
        _png(),
      ], metadata: aiMeta);
      expect(draft.success, isTrue, reason: draft.error);
      expect(p.basename(draft.outputPath!), contains(kAiDraftFileSuffix));
      expect(
        p.basename(draft.outputPath!),
        endsWith('$kAiDraftFileSuffix.pdf'),
      );

      // Nagekeken: het achtervoegsel hoort dan wég te zijn. Anders draagt elk
      // afgerond rapport voorgoed het stempel "concept" en betekent het niets.
      final reviewed = await service.export(
        deckPath(),
        ExportFormat.pdf,
        [_png()],
        metadata: const ExportDocumentMetadata(title: 'Conceptrapport'),
      );
      expect(reviewed.success, isTrue, reason: reviewed.error);
      expect(
        p.basename(reviewed.outputPath!),
        isNot(contains(kAiDraftFileSuffix)),
      );
    },
  );

  test(
    'de markering wordt uit de bundel geteld, niet uit wat de aanroeper meegaf',
    () async {
      // De poort waar élk formaat langskomt telt zelf. Dat is het verschil
      // tussen een melding die kan ontbreken en een die dat niet kan: `metadata`
      // is optioneel én door de aanroeper samen te stellen, dus zou de melding
      // dáár vandaan komen, dan volstond "vergeten" om ongecontroleerde
      // AI-tekst zwijgend te laten vertrekken.
      final bundel = bundleFor(
        Deck(
          title: 'Conceptrapport',
          slides: [
            Slide.create(SlideType.title),
            Slide.create(
              SlideType.bullets,
            ).copyWith(aiAssistedFields: const ['description']),
          ],
        ),
      );

      // Metadata die de markering níét noemt — het geval "vergeten".
      final r = await service.export(
        deckPath(),
        ExportFormat.pdf,
        [_png()],
        audience: bundel,
        metadata: const ExportDocumentMetadata(title: 'Conceptrapport'),
      );
      expect(r.success, isTrue, reason: r.error);
      expect(p.basename(r.outputPath!), contains(kAiDraftFileSuffix));
      final text = String.fromCharCodes(
        await File(r.outputPath!).readAsBytes(),
      );
      expect(text, contains(r'AI-generated \(unreviewed\)'));
    },
  );

  test(
    'een nagekeken bundel laat de melding weg, ook als metadata hem noemt',
    () async {
      // De andere kant op, en even belangrijk: geteld is geteld. Zou de aanroeper
      // de melding erin kunnen houden, dan draagt een afgerond rapport voorgoed
      // het stempel "concept" en betekent het niets meer.
      final bundel = bundleFor(
        Deck(title: 'Rapport', slides: [Slide.create(SlideType.title)]),
      );
      final r = await service.export(
        deckPath(),
        ExportFormat.pdf,
        [_png()],
        audience: bundel,
        metadata: aiMeta,
      );
      expect(r.success, isTrue, reason: r.error);
      expect(p.basename(r.outputPath!), isNot(contains(kAiDraftFileSuffix)));
    },
  );

  test('exports a valid PPTX zip with the expected parts', () async {
    final images = [_png(), _png()];
    final r = await service.export(deckPath(), ExportFormat.pptx, images);

    expect(r.success, isTrue, reason: r.error);
    expect(p.extension(r.outputPath!), '.pptx');

    final bytes = await File(r.outputPath!).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('_rels/.rels'));
    expect(names, contains('docProps/core.xml'));
    expect(names, contains('docProps/app.xml'));
    expect(names, contains('ppt/presentation.xml'));
    expect(names, contains('ppt/slideMasters/slideMaster1.xml'));
    expect(names, contains('ppt/slideLayouts/slideLayout1.xml'));
    expect(names, contains('ppt/theme/theme1.xml'));
    expect(names, contains('ppt/slides/slide1.xml'));
    expect(names, contains('ppt/slides/slide2.xml'));
    expect(names, contains('ppt/media/image1.png'));
    expect(names, contains('ppt/media/image2.png'));

    // Every XML part must be well-formed.
    for (final file in archive.files) {
      if (file.name.endsWith('.xml') || file.name.endsWith('.rels')) {
        final content = utf8.decode(file.content as List<int>);
        expect(
          () => XmlDocument.parse(content),
          returnsNormally,
          reason: '${file.name} is not well-formed XML',
        );
      }
    }
  });

  test('PPTX core properties carry classification metadata', () async {
    const metadata = ExportDocumentMetadata(
      title: 'Strategie',
      organization: 'Acme BV',
      tlp: TlpLevel.green,
    );
    final r = await service.export(
      deckPath(),
      ExportFormat.pptx,
      [_png()],
      tlp: TlpLevel.green,
      metadata: metadata,
    );
    expect(r.success, isTrue, reason: r.error);

    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final core = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'docProps/core.xml').content
          as List<int>,
    );
    expect(core, contains('<dc:title>Strategie</dc:title>'));
    expect(core, contains('<dc:subject>TLP:GREEN — Strategie</dc:subject>'));
    expect(core, contains('<cp:keywords>'));
    expect(core, contains('TLP:GREEN'));

    final app = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'docProps/app.xml').content
          as List<int>,
    );
    expect(app, contains('<Company>Acme BV</Company>'));
    expect(app, contains('OciDeck'));
  });

  test('PPTX without notes has no notesSlide/notesMaster parts', () async {
    final r = await service.export(deckPath(), ExportFormat.pptx, [_png()]);
    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final names = archive.files.map((f) => f.name).toSet();
    expect(names.any((n) => n.startsWith('ppt/notesSlides/')), isFalse);
    expect(names.any((n) => n.startsWith('ppt/notesMasters/')), isFalse);
  });

  test('PPTX embeds speaker notes only for slides that have them', () async {
    final r = await service.export(
      deckPath(),
      ExportFormat.pptx,
      [_png(), _png()],
      audience: bundleWithNotes(const ['', 'Vergeet de cijfers niet <3 & co']),
    );
    expect(r.success, isTrue, reason: r.error);

    final archive = ZipDecoder().decodeBytes(
      await File(r.outputPath!).readAsBytes(),
    );
    final names = archive.files.map((f) => f.name).toSet();

    // Notes machinery is present for the noted slide only.
    expect(names, contains('ppt/notesMasters/notesMaster1.xml'));
    expect(names, contains('ppt/notesSlides/notesSlide2.xml'));
    expect(names, isNot(contains('ppt/notesSlides/notesSlide1.xml')));

    String partText(String name) => utf8.decode(
      archive.files.firstWhere((f) => f.name == name).content as List<int>,
    );

    // The note text is present and XML-escaped.
    final notes2 = partText('ppt/notesSlides/notesSlide2.xml');
    expect(notes2, contains('Vergeet de cijfers niet &lt;3 &amp; co'));
    // The slide links to its notesSlide.
    expect(
      partText('ppt/slides/_rels/slide2.xml.rels'),
      contains('notesSlide2.xml'),
    );

    // Every XML part (including the new notes parts) must be well-formed.
    for (final file in archive.files) {
      if (file.name.endsWith('.xml') || file.name.endsWith('.rels')) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content as List<int>)),
          returnsNormally,
          reason: '${file.name} is not well-formed XML',
        );
      }
    }
  });

  test('compressed PDF is written as a separate -compact file', () async {
    final images = [_png(), _png()];
    final r = await service.export(
      deckPath(),
      ExportFormat.pdf,
      images,
      compress: true,
    );

    expect(r.success, isTrue, reason: r.error);
    expect(p.basename(r.outputPath!), endsWith(' deck-compact.pdf'));
    expect(p.basename(r.outputPath!), matches(_dtgPrefix));
    final bytes = await File(r.outputPath!).readAsBytes();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('compressed PDF is smaller than the lossless PDF', () async {
    final images = [_noisyPng(), _noisyPng()];

    final lossless = await service.export(deckPath(), ExportFormat.pdf, images);
    final compressed = await service.export(
      deckPath(),
      ExportFormat.pdf,
      images,
      compress: true,
    );

    expect(lossless.success, isTrue, reason: lossless.error);
    expect(compressed.success, isTrue, reason: compressed.error);

    final losslessSize = await File(lossless.outputPath!).length();
    final compressedSize = await File(compressed.outputPath!).length();
    expect(compressedSize, lessThan(losslessSize));
  });

  test('writes into outputDirectory and creates it when missing', () async {
    final exportDir = p.join(tmp.path, 'exports', 'pdf');
    expect(Directory(exportDir).existsSync(), isFalse);

    final r = await service.export(deckPath(), ExportFormat.pdf, [
      _png(),
    ], outputDirectory: exportDir);

    expect(r.success, isTrue, reason: r.error);
    expect(p.dirname(r.outputPath!), exportDir);
    expect(p.basename(r.outputPath!), endsWith(' deck.pdf'));
    expect(p.basename(r.outputPath!), matches(_dtgPrefix));
    expect(File(r.outputPath!).existsSync(), isTrue);
  });

  test('without outputDirectory the export lands next to the deck', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, [_png()]);

    expect(r.success, isTrue, reason: r.error);
    expect(p.dirname(r.outputPath!), tmp.path);
  });

  test('natoDtg formats a UTC YYYYMMDDHHMMSS timestamp', () {
    final t = DateTime.utc(2026, 6, 3, 12, 45, 47);
    expect(ExportService.natoDtg(t), '20260603124547');
  });

  test('natoDtg converts non-UTC input to UTC (zone-independent)', () {
    final utc = DateTime.utc(2026, 1, 5, 9, 7, 3);
    // toLocal() then format must still yield the original UTC timestamp,
    // whatever the machine's time zone is.
    expect(ExportService.natoDtg(utc.toLocal()), '20260105090703');
  });

  test('fails gracefully when there are no slides', () async {
    final r = await service.export(deckPath(), ExportFormat.pdf, const []);
    expect(r.success, isFalse);
  });

  test('HTML export writes a self-contained .html from Markdown', () async {
    final htmlService = ExportService(
      htmlService: MarpHtmlService(loadAsset: (a) => File(a).readAsString()),
    );
    final r = await htmlService.export(
      deckPath(),
      ExportFormat.html,
      const [], // HTML needs no rasterized slides
      audience: bundleFor(
        const Deck(title: 'Titel'),
        markdown: '# Titel\n\n---\n\n# Tweede',
      ),
    );

    expect(r.success, isTrue, reason: r.error);
    expect(p.extension(r.outputPath!), '.html');
    expect(p.basename(r.outputPath!), matches(_dtgPrefix));

    final html = await File(r.outputPath!).readAsString();
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('# Titel'));
  });

  test('HTML export fails without Markdown', () async {
    final r = await service.export(deckPath(), ExportFormat.html, const []);
    expect(r.success, isFalse);
  });

  test('de HTML-export sluit beeld uit de projectmap in', () async {
    // Één afbeelding binnen de projectmap en één erbuiten. Die tweede is de
    // reden dat het lezen in ExportService zit en niet in de HTML-bouwer: een
    // deck van een derde mag met `![](…)` geen willekeurig bestand de export in
    // trekken, en die export gaat naar buiten.
    final images = Directory(p.join(tmp.path, 'images'))..createSync();
    final photo = img.Image(width: 40, height: 30);
    for (final pixel in photo) {
      pixel.setRgb(0, 51, 153);
    }
    File(
      p.join(images.path, 'binnen.png'),
    ).writeAsBytesSync(img.encodePng(photo));
    final buiten = Directory.systemTemp.createTempSync('ocideck-buiten');
    addTearDown(() => buiten.deleteSync(recursive: true));
    final outsidePath = p.join(buiten.path, 'geheim.png');
    File(outsidePath).writeAsBytesSync(img.encodePng(photo));

    final htmlService = ExportService(
      htmlService: MarpHtmlService(loadAsset: (a) => File(a).readAsString()),
    );
    final r = await htmlService.export(
      deckPath(),
      ExportFormat.html,
      const [],
      audience: bundleFor(
        const Deck(title: 'Met beeld'),
        markdown:
            '# Met beeld\n\n![Binnen](images/binnen.png)\n\n---\n\n'
            '# Buiten de map\n\n![Buiten]($outsidePath)\n',
      ),
    );

    expect(r.success, isTrue, reason: r.error);
    final html = await File(r.outputPath!).readAsString();
    // Het beeld uit de projectmap reist mee — en het pad blijft eruit.
    expect(html, contains('data:image/'));
    expect(html, isNot(contains('images/binnen.png')));
    // Het bestand erbuiten wordt niet gelezen en niet genoemd.
    expect(html, isNot(contains(outsidePath)));
    expect(html, contains('Afbeelding niet ingesloten'));
  });
}
