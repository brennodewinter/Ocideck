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

FormFill course(String template, String language, {String hours = '6,5'}) {
  var fill =
      (FormFill.open(CpeCertificateService.groupForm(template, language))
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
        for (final hours in ['0', '-1', 'oops', 'NaN', '']) {
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
