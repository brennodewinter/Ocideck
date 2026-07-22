import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';

// De invariant van de hele feature (OCIWACHT §6.5):
//
//   DE GEREDIGEERDE WAARDE KOMT IN GEEN ENKEL ONTVANGEND ARTEFACT VOOR.
//
// Een zwarte balk over leesbare tekst is geen redactie. Deze test exporteert een
// deck met bekende kanariewaarden en zoekt die letterlijk terug in wat er het
// bestand in gaat — inclusief de plekken die je niet ziet: de
// PPTX-notitiepagina's, de documentmetadata en het markdown-blok in de HTML.
//
// En de tegenhanger, even belangrijk: de bron houdt de waarde wél.

/// Een geldige 1x1-PNG. De PDF-bouwer decodeert de slide-afbeeldingen echt, dus
/// een handvol willekeurige bytes is niet genoeg.
final _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0b, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9c, 0x63, 0xf8, 0x0f, 0x04, 0x00,
  0x09, 0xfb, 0x03, 0xfd, 0xfb, 0x5e, 0x6b, 0x2b,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44,
  0xae, 0x42, 0x60, 0x82,
]);

void main() {
  // De HTML-bouwer laadt de meegeleverde JS-bundels uit de assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Kanaries die nergens in een artefact mogen opduiken.
  const geheimBsn = 'BSN123456782KANARIE';
  const geheimeNaam = 'JanDeVriesKanarie';
  const geheimeNotitie = 'HetAdresKanarie';
  const geheimeAuteur = 'PietPetersKanarie';

  Deck bronDeck() => Deck(
    title: 'Briefing [[$geheimeNaam]]',
    author: '[[$geheimeAuteur]]',
    keywords: '[[$geheimeNaam]], fraude',
    slides: [
      Slide.create(SlideType.bullets).copyWith(
        title: 'Verdachte',
        bullets: ['BSN [[$geheimBsn]]'],
        // Sprekersnotities zijn onzichtbaar in de preview, maar gaan als platte
        // tekst mee in ppt/notesSlides/notesSlide1.xml.
        notes: 'niet voorlezen: [[$geheimeNotitie]]',
      ),
    ],
  );

  /// Eén pixel per slide in plaats van een echte raster: de rasterizer heeft een
  /// widget-tree nodig en die hebben we hier niet. Voor deze test doet dat er
  /// niet toe — raster ís veilig (het zijn pixels). Het gaat om de tekstkanalen
  /// eromheen, en dat zijn precies de kanalen die je makkelijk vergeet.
  List<Uint8List> slideAfbeeldingen(int n) => [
    for (var i = 0; i < n; i++) _pixel,
  ];

  late Directory tempDir;
  late String deckPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ocideck_privacy_export');
    deckPath = '${tempDir.path}/briefing.md';
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<String> exporteer(ExportFormat format) async {
    final audience = PrivacyProjection.forAudience(bronDeck());
    final result = await ExportService().export(
      deckPath,
      format,
      slideAfbeeldingen(audience.slides.length),
      outputDirectory: tempDir.path,
      audience: ExportBundle(
        audience: audience,
        markdown: MarkdownService().generateDeck(
          audience.deck,
          forExport: true,
        ),
        manifest: RedactionManifest.empty,
        privacySummary: PrivacyExportSummary.empty,
      ),
      themeProfile: audience.deck.themeProfile,
      metadata: ExportDocumentMetadata.fromDeck(audience),
    );
    expect(result.success, isTrue, reason: result.error);
    return result.outputPath!;
  }

  void verwachtGeenKanaries(String waar, String inhoud) {
    for (final kanarie in [
      geheimBsn,
      geheimeNaam,
      geheimeNotitie,
      geheimeAuteur,
    ]) {
      expect(
        inhoud.contains(kanarie),
        isFalse,
        reason: '"$kanarie" staat leesbaar in $waar',
      );
    }
  }

  test(
    'HTML bevat de waarde nergens — ook niet in het markdown-blok',
    () async {
      final path = await exporteer(ExportFormat.html);
      // Bewust de hele broncode, niet alleen de zichtbare tekst: de HTML-export
      // zet de markdown letterlijk in een <script>-blok. Een CSS-regel die iets
      // zwart maakt, is één Ctrl+U verwijderd van een datalek.
      verwachtGeenKanaries('de HTML-broncode', await File(path).readAsString());
    },
  );

  test('PPTX bevat de waarde in geen enkele zip-entry', () async {
    final path = await exporteer(ExportFormat.pptx);
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());

    var zagNotesSlide = false;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name.contains('notesSlide')) zagNotesSlide = true;
      // De XML zit gedeflate in de zip: rauwe bytes doorzoeken zou de tekst
      // nooit vinden, ook niet als hij er wél stond. Dus uitpakken.
      final content = String.fromCharCodes(file.content as List<int>);
      verwachtGeenKanaries('PPTX-entry ${file.name}', content);
    }

    // Borg dat we het notitiekanaal daadwerkelijk hebben gecontroleerd en niet
    // per ongeluk een PPTX zonder notities hebben getest — dan bewijst de test
    // niets over het lek dat we juist wilden dichten.
    expect(
      zagNotesSlide,
      isTrue,
      reason: 'geen notesSlide in de PPTX; het notitiekanaal is niet getest',
    );
  });

  test('PDF bevat de waarde niet — ook niet in de documentmetadata', () async {
    final path = await exporteer(ExportFormat.pdf);
    final bytes = await File(path).readAsBytes();
    verwachtGeenKanaries('de PDF-bytes', String.fromCharCodes(bytes));
  });

  test('de bron houdt de waarde wél — redactie raakt de markdown niet', () {
    final bron = bronDeck();
    PrivacyProjection.forAudience(bron);

    final markdown = MarkdownService().generateDeck(bron);
    expect(markdown.contains(geheimBsn), isTrue);
    expect(markdown.contains(geheimeNotitie), isTrue);
    expect(markdown.contains('[['), isTrue);
  });
}
