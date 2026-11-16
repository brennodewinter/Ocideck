import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/cpe_certificate_service.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_renderer.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/services/pdf/markdown_to_pdf_blocks.dart';

import 'pdf/pdf_text_probe.dart';

FormFill answer(FormFill fill, String id, FormAnswerValue value) =>
    (fill.setAnswer(id, value) as FormFillChanged).fill;

FormFill course(
  String template,
  String language, {
  String hours = '6,5',
  Map<String, FormImageFact> imageFacts = const {},
}) {
  var fill =
      (FormFill.open(
                CpeCertificateService.groupForm(template, language),
                imageFacts: imageFacts,
              )
              as FormFillReady)
          .fill;
  for (final entry in {
    'programma': 'Security for auditors',
    'locatie': 'Noordwijkerhout',
    'docent': 'Docent',
    'uitgever': 'Opleider',
    'datum': '2026-11-13',
    'ondertekenaar': 'Ondertekenaar',
  }.entries) {
    fill = answer(fill, entry.key, FormAnswerValue(text: entry.value));
  }
  fill = answer(
    fill,
    'sessies',
    const FormAnswerValue(
      rows: [
        ['2026-11-12', 'Auditing', '08:30 - 17:30'],
      ],
    ),
  );
  return answer(
    fill,
    'deelnemers',
    FormAnswerValue(
      rows: [
        ['Alice', 'alice@example.org', '8', ''],
        ['Bob', 'bob@example.org', hours, 'Vanaf 10:00 aanwezig'],
      ],
    ),
  );
}

void main() {
  for (final language in ['nl', 'en']) {
    final template = File(
      'assets/document_templates/cpe.$language.md',
    ).readAsStringSync();
    test(
      '$language: individual hours and attendance, no other participant data',
      () {
        final certificates = CpeCertificateService.issue(
          template,
          course(template, language),
          language,
        );
        expect(certificates, hasLength(2));
        expect(
          certificates[0].source,
          contains('8 ${language == 'nl' ? 'PE-uren' : 'CPE hours'}'),
        );
        expect(certificates[0].source, isNot(contains('bob@example.org')));
        expect(certificates[0].source, isNot(contains('Vanaf 10:00')));
        expect(certificates[1].source, contains('6,5'));
        expect(certificates[1].source, contains('Vanaf 10:00'));
        expect(certificates[1].source, isNot(contains('alice@example.org')));
        expect(certificates[1].source, isNot(contains('<!-- field')));
      },
    );
    test(
      '$language: rejects zero, negative and invalid hours before issuing',
      () {
        // Een lege urenkolom valt op het sessietotaal terug; 8:30-17:30 is 9
        // uur, dus alleen 'oops' en 'NaN' blijven fouten.
        for (final hours in ['0', '-1', 'oops', 'NaN']) {
          expect(
            () => CpeCertificateService.issue(
              template,
              course(template, language, hours: hours),
              language,
            ),
            throwsFormatException,
            reason: hours,
          );
        }
      },
    );
    test(
      '$language: empty hours fall back to the session total, more is refused',
      () {
        final filled = CpeCertificateService.issue(
          template,
          course(template, language, hours: ''),
          language,
        );
        expect(
          filled[1].source,
          contains('9 ${language == 'nl' ? 'PE-uren' : 'CPE hours'}'),
        );
        expect(
          () => CpeCertificateService.issue(
            template,
            course(template, language, hours: '9,5'),
            language,
          ),
          throwsFormatException,
        );
      },
    );
    test(
      '$language: the signature gets a bounded height, not column width',
      () {
        final fill = answer(
          course(
            template,
            language,
            imageFacts: const {
              'images/sig.png': FormImageFact(bytes: 10, format: 'png'),
            },
          ),
          'handtekening',
          const FormAnswerValue(
            images: [FormImageRef('images/sig.png', 'Handtekening', null)],
          ),
        );
        final certificate = CpeCertificateService.issue(
          template,
          fill,
          language,
        )[0];
        expect(
          certificate.source,
          contains('![h:96px Handtekening](images/sig.png)'),
        );
      },
    );
    test('$language: certificate renders as one PDF page', () async {
      final certificate = CpeCertificateService.issue(
        template,
        course(template, language),
        language,
      )[1];
      final body = MarkdownDocument.parse(certificate.source).body;
      final bytes = await buildDocumentPdf(
        markdownToPdfBlocks(body),
        style: DocumentPdfStyle.fromTheme(const ThemeProfile()),
        fonts: DocumentPdfFonts.forFamily(
          'Roboto',
          fallbackFonts: [
            File(
              'assets/fonts/Roboto-Variable.ttf',
            ).readAsBytesSync().buffer.asByteData(),
          ],
        ),
        images: {
          'asset:assets/images/isaca-netherlands-chapter.png':
              Uint8List.fromList(
                File(
                  'assets/images/isaca-netherlands-chapter.png',
                ).readAsBytesSync(),
              ),
        },
        verbatimLabel: (_) => 'source',
      );
      expect(pdfPageCount(bytes), 1);
      expect(pdfVisibleText(bytes), contains('bob@example.org'));
      if (Platform.environment['OCIDECK_CPE_PREVIEW'] case final path?) {
        File('$path/cpe-$language.pdf').writeAsBytesSync(bytes);
      }
    });
  }
  group('sessionHours', () {
    test('a time block is the length between its clocks', () {
      expect(CpeCertificateService.sessionHours('08:30 - 17:30'), 9);
      expect(CpeCertificateService.sessionHours('9.00 - 12.30'), 3.5);
    });
    test('several blocks in one cell add up', () {
      expect(
        CpeCertificateService.sessionHours('09:00 - 12:00, 13:00 - 15:30'),
        5.5,
      );
    });
    test('a plain number or a number with a unit is hours', () {
      expect(CpeCertificateService.sessionHours('6,5'), 6.5);
      expect(CpeCertificateService.sessionHours('2 uur'), 2);
      expect(CpeCertificateService.sessionHours('90 minuten'), 1.5);
    });
    test('nothing parseable is no bound', () {
      expect(CpeCertificateService.sessionHours(''), isNull);
      expect(CpeCertificateService.sessionHours('onduidelijk'), isNull);
    });
  });
  test('both recipe assets remain valid forms', () {
    for (final language in ['nl', 'en']) {
      expect(
        FormFill.open(
          File(
            'assets/document_templates/recipe.$language.md',
          ).readAsStringSync(),
        ),
        isA<FormFillReady>(),
      );
    }
  });
}
