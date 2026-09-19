// De huisstijl uit een `.odt` (#2119): het spiegelbeeld van de DOCX-tests,
// op een fixture in de vorm die LibreOffice Writer schrijft.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/odt/odt_document_importer.dart';
import 'package:ocideck/services/import/models/source_document_style.dart';

import 'helpers/docx_styled_fixture.dart' show fixtureLogoPng;
import 'helpers/odt_fixture.dart';
import 'helpers/odt_styled_fixture.dart';

void main() {
  group('letters en kleuren', () {
    test('koppen volgen de Heading-stijl, de tekst de default-style', () {
      final style = convertOdtDetailed(odtStyledFixture()).style;
      expect(style.headingFontFamily, 'Liberation Sans');
      expect(style.bodyFontFamily, 'Liberation Serif');
      expect(style.textColor, '#000000');
      expect(style.headingColor, '#00464F');
      // ODF kent geen themakleuren.
      expect(style.accentColor, isNull);
    });

    test('een subkop met een andere kleur is één verlies per kleur', () {
      final style = convertOdtDetailed(odtStyledFixture()).style;
      expect(
        style.losses.where(
          (l) => l.kind == DocumentStyleLossKind.perLevelHeadingColor,
        ),
        [
          const DocumentStyleLoss(
            DocumentStyleLossKind.perLevelHeadingColor,
            detail: '2:#1E78B5',
          ),
        ],
      );
    });

    test('de kale fixture is leeg', () {
      expect(convertOdtDetailed(odtFixture()).style.isEmpty, isTrue);
    });
  });

  group('kop- en voettekst', () {
    test('de voettekst komt zonder paginanummer, mét de vlag', () {
      final style = convertOdtDetailed(odtStyledFixture()).style;
      expect(style.footerText, 'Information security policy');
      expect(style.showPageNumbers, isTrue);
      expect(style.headerText, isNull);
    });

    test('zonder paginanummerveld geen vlag', () {
      final style = convertOdtDetailed(
        odtStyledFixture(footerPageNumber: false),
      ).style;
      expect(style.showPageNumbers, isFalse);
    });

    test('de koptekst komt mee', () {
      final style = convertOdtDetailed(
        odtStyledFixture(headerText: 'Beleid'),
      ).style;
      expect(style.headerText, 'Beleid');
    });
  });

  group('logo', () {
    test('het beeldmerk in de voettekst, aan de bladzijde verankerd', () {
      final logo = fixtureLogoPng();
      final style = convertOdtDetailed(
        odtStyledFixture(footerLogo: logo, firstPageLogo: logo),
      ).style;
      expect(style.logoCandidates, hasLength(1));
      final candidate = style.logoCandidates.single;
      expect(candidate.origin, DocumentLogoOrigin.footer);
      expect(candidate.position, 'bottom-right');
      expect(candidate.widthMm, closeTo(9.0, 0.01));
      expect(candidate.bytes, logo);
      expect(
        style.losses,
        contains(const DocumentStyleLoss(DocumentStyleLossKind.titlePageImage)),
      );
    });

    test('een kader in de koptekst volgt zijn horizontale positie', () {
      final logo = fixtureLogoPng();
      final right = convertOdtDetailed(
        odtStyledFixture(
          headerLogo: logo,
          headerFrame: const OdtFrame(
            widthCm: 3,
            heightCm: 1,
            horizontalPos: 'right',
          ),
        ),
      ).style;
      expect(right.logoCandidates.single.position, 'top-right');
      expect(right.logoCandidates.single.origin, DocumentLogoOrigin.header);
      expect(right.logoCandidates.single.widthMm, closeTo(30, 0.01));

      final centred = convertOdtDetailed(
        odtStyledFixture(
          headerLogo: logo,
          headerFrame: const OdtFrame(
            widthCm: 3,
            heightCm: 1,
            horizontalPos: 'center',
          ),
        ),
      ).style;
      expect(centred.logoCandidates.single.centred, isTrue);
      expect(
        centred.losses,
        contains(const DocumentStyleLoss(DocumentStyleLossKind.centredLogo)),
      );
    });

    test('zonder positie volgt een kader de uitlijning van de alinea', () {
      final style = convertOdtDetailed(
        odtStyledFixture(
          footerLogo: fixtureLogoPng(),
          footerFrame: const OdtFrame(widthCm: 2, heightCm: 1),
          footerAlign: 'end',
        ),
      ).style;
      expect(style.logoCandidates.single.position, 'bottom-right');
    });

    test('alleen SVG wordt gemeld, niet overgenomen', () {
      final style = convertOdtDetailed(
        odtStyledFixture(footerLogo: fixtureLogoPng(), footerLogoSvgOnly: true),
      ).style;
      expect(style.logoCandidates, isEmpty);
      expect(
        style.losses,
        contains(const DocumentStyleLoss(DocumentStyleLossKind.vectorOnlyLogo)),
      );
    });

    test('een beeld dat per bladzijde in de body herhaald is telt ook', () {
      final style = convertOdtDetailed(
        odtStyledFixture(
          footerText: null,
          footerPageNumber: false,
          bodyRepeatedLogo: fixtureLogoPng(seed: 2),
          bodyRepeatCount: 3,
        ),
      ).style;
      expect(style.logoCandidates, hasLength(1));
      expect(style.logoCandidates.single.origin, DocumentLogoOrigin.body);
      expect(style.logoCandidates.single.occurrences, 3);
      expect(style.logoCandidates.single.position, 'top-left');
      expect(style.logoCandidates.single.widthMm, closeTo(25, 0.01));
    });
  });

  test('beelden in de tekst komen mee, náást de stijl', () {
    final result = convertOdtDetailed(
      odtStyledFixture(bodyRepeatedLogo: fixtureLogoPng(), bodyRepeatCount: 2),
    );
    expect(result.images, hasLength(2));
    expect(result.markdown, contains('# Beleid'));
    expect(
      convertOdtToMarkdown(odtStyledFixture()),
      convertOdtDetailed(odtStyledFixture()).markdown,
    );
  });
}
