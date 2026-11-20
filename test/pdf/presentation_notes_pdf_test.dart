@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/pdf/presentation_notes_pdf.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';

import 'pdf_text_probe.dart';

Uint8List _image({int width = 320, int height = 180}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 60, 100));
  return Uint8List.fromList(img.encodePng(image));
}

ExportBundle _bundle(
  List<Slide> slides, {
  bool includeDetail = true,
  QuestionExport questions = QuestionExport.included,
}) => buildExportBundle(
  Deck(title: 'Spreektekst', slides: slides),
  slides,
  profile: PrivacyExportProfile.redacted,
  includeDetail: includeDetail,
  questions: questions,
  expandPages: true,
  disabledRules: const {},
  ownIdentity: OwnIdentity.empty,
  regions: defaultPrivacyRegions,
  markdownService: MarkdownService(),
);

Future<Uint8List> _pdf(ExportBundle bundle, {List<Uint8List>? images}) async {
  final doc = pw.Document();
  addPresentationNotesPages(
    doc,
    images ?? [for (final _ in bundle.audience.slides) _image()],
    audience: bundle.audience,
    fallbackFonts: [
      ByteData.sublistView(
        await File('assets/fonts/Roboto-Variable.ttf').readAsBytes(),
      ),
    ],
  );
  return doc.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('elke dia krijgt een eigen staand A4-blad met zijn notities', () async {
    final bytes = await _pdf(
      _bundle([
        Slide.create(SlideType.title).copyWith(notes: 'Eerste spreektekst.'),
        Slide.create(SlideType.bullets).copyWith(notes: 'Tweede spreektekst.'),
      ]),
    );
    expect(pdfPageCount(bytes), 2);
    final pages = pdfVisibleTextPerPage(bytes);
    expect(pages.first, contains('Eerste spreektekst.'));
    expect(pages.first, isNot(contains('Tweede spreektekst.')));
    expect(pages.last, contains('Tweede spreektekst.'));
    final media = RegExp(
      r'/MediaBox\s*\[0\s+0\s+([\d.]+)\s+([\d.]+)\]',
    ).allMatches(String.fromCharCodes(bytes));
    expect(media, hasLength(2));
    for (final page in media) {
      expect(double.parse(page[1]!), closeTo(595.28, .02));
      expect(double.parse(page[2]!), closeTo(841.89, .02));
    }
  });

  test(
    'een lange alinea loopt door zonder tekstverlies of extra dia',
    () async {
      final bytes = await _pdf(
        _bundle([
          Slide.create(SlideType.title).copyWith(
            notes: 'BEGIN ${List.filled(15000, 'vervolg').join(' ')} EIND',
          ),
          Slide.create(SlideType.title).copyWith(notes: 'VOLGENDE'),
        ]),
      );
      expect(pdfPageCount(bytes), greaterThan(20));
      final text = pdfVisibleText(bytes);
      expect(text, contains('BEGIN'));
      expect(RegExp('vervolg').allMatches(text), hasLength(15000));
      expect(text.indexOf('EIND'), lessThan(text.indexOf('VOLGENDE')));
      expect(pdfVisibleTextPerPage(bytes).last, contains('VOLGENDE'));
    },
  );

  test(
    'privacy en diafilters gelden ook voor de echte PDF-notitietekst',
    () async {
      final bundle = _bundle(
        [
          Slide.create(
            SlideType.title,
          ).copyWith(notes: 'Openbaar [[VERBORGEN]]'),
          Slide.create(
            SlideType.title,
          ).copyWith(isDetail: true, notes: 'VERDIEPING'),
          Slide.create(SlideType.question).copyWith(notes: 'QUIZANTWOORD'),
        ],
        includeDetail: false,
        questions: QuestionExport.omitted,
      );
      expect(bundle.audience.slides, hasLength(1));
      final bytes = await _pdf(bundle);
      final text = pdfVisibleText(bytes);
      expect(text, contains('Openbaar'));
      for (final secret in ['VERBORGEN', 'VERDIEPING', 'QUIZANTWOORD']) {
        expect(text, isNot(contains(secret)));
      }
      expect(pdfPageCount(bytes), 1);
    },
  );

  test('ongelijke aantallen beelden en notities worden geweigerd', () {
    expect(
      () => addPresentationNotesPages(
        pw.Document(),
        [],
        audience: _bundle([Slide.create(SlideType.title)]).audience,
        fallbackFonts: [],
      ),
      throwsArgumentError,
    );
  });

  test(
    'staande en brede dia’s passen zonder overloop boven de notities',
    () async {
      final bundle = _bundle([
        Slide.create(SlideType.title).copyWith(notes: 'STAAND'),
        Slide.create(SlideType.title).copyWith(notes: 'BREED'),
      ]);
      final bytes = await _pdf(
        bundle,
        images: [
          _image(width: 160, height: 900),
          _image(width: 900, height: 160),
        ],
      );
      expect(pdfPageCount(bytes), 2);
      expect(pdfVisibleTextPerPage(bytes).first, contains('STAAND'));
      expect(pdfVisibleTextPerPage(bytes).last, contains('BREED'));
    },
  );

  test('een ontbrekend letterteken verdwijnt niet stilzwijgend', () {
    final bundle = _bundle([
      Slide.create(
        SlideType.title,
      ).copyWith(notes: 'Niet beschikbaar: \u{10ffff}'),
    ]);
    expect(
      () => addPresentationNotesPages(
        pw.Document(),
        [_image()],
        audience: bundle.audience,
        fallbackFonts: [],
      ),
      throwsFormatException,
    );
  });

  test('Unicode-notities en lege notities blijven exporteerbaar', () async {
    final paragraphs = List.generate(
      45,
      (i) =>
          'Onderdeel ${i + 1}. Bespreek de uitkomst met de deelnemers. '
          'Controleer samen welke vervolgstap nodig is.',
    );
    final bytes = await _pdf(
      _bundle([
        Slide.create(SlideType.title).copyWith(
          notes:
              'Spreektekst: Łódź, Αθήνα, Москва.\n\n${paragraphs.join('\n\n')}',
        ),
        Slide.create(SlideType.title),
      ]),
    );
    expect(pdfPageCount(bytes), greaterThan(2));
    final proof = Platform.environment['OCIDECK_PDF_NOTES_PROOF'];
    if (proof != null) await File(proof).writeAsBytes(bytes);
  });

  test(
    'dienst bewaart standaard-PDF en geeft notitie-export eigen naam',
    () async {
      final tmp = await Directory.systemTemp.createTemp('ocideck-a4-notes-');
      addTearDown(() => tmp.delete(recursive: true));
      final bundle = _bundle([
        Slide.create(SlideType.title).copyWith(notes: 'SPREEKTEKST'),
      ]);
      final service = ExportService();
      final normal = await service.export(
        '${tmp.path}/deck.md',
        ExportFormat.pdf,
        [_image()],
        audience: bundle,
      );
      expect(normal.success, isTrue, reason: normal.error);
      final normalBytes = await File(normal.outputPath!).readAsBytes();
      expect(pdfVisibleText(normalBytes), isNot(contains('SPREEKTEKST')));
      final notes = await service.export(
        '${tmp.path}/deck.md',
        ExportFormat.pdf,
        [_image()],
        audience: bundle,
        pdfWithSpeakerNotes: true,
        compress: true,
      );
      expect(notes.success, isTrue, reason: notes.error);
      expect(notes.outputPath, endsWith('-a4-notities-compact.pdf'));
      final bytes = await File(notes.outputPath!).readAsBytes();
      expect(pdfVisibleText(bytes), contains('SPREEKTEKST'));
      final refused = await service.export(
        '${tmp.path}/deck.md',
        ExportFormat.pdf,
        [_image()],
        pdfWithSpeakerNotes: true,
      );
      expect(refused.success, isFalse);
    },
  );
}
