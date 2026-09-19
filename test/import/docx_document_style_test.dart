// De huisstijl uit een `.docx` (#2119): letters, kleuren, kop- en voettekst
// en het beeld op elke bladzijde.
//
// De fixture heeft de vorm van een echt Word-document (thema, basedOn-keten,
// titelblad, verankerd beeldmerk in de voettekst, tekstkader, PAGE-veld).
// Elke test zet één ding anders en kijkt of precies dát verandert.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/docx/docx_document_importer.dart';
import 'package:ocideck/services/import/models/source_document_style.dart';

import 'helpers/docx_fixture.dart';
import 'helpers/docx_styled_fixture.dart';

void main() {
  group('letters', () {
    test('koppen volgen de major-letter, de tekst de minor-letter', () {
      final style = importDocx(docxStyledFixture()).style;
      expect(style.headingFontFamily, 'Aptos');
      expect(style.bodyFontFamily, 'Aptos Light');
    });

    test('een kopstijl met een eigen naam wint van het thema', () {
      final style = importDocx(
        docxStyledFixture(heading1Font: 'Segoe UI'),
      ).style;
      expect(style.headingFontFamily, 'Segoe UI');
      expect(style.bodyFontFamily, 'Aptos Light');
    });

    test('zonder thema blijft een thema-verwijzing leeg', () {
      final style = importDocx(docxStyledFixture(withTheme: false)).style;
      expect(style.headingFontFamily, isNull);
      expect(style.bodyFontFamily, isNull);
      expect(style.accentColor, isNull);
    });

    test('de kale fixture zonder stijlinformatie is leeg', () {
      final style = importDocx(docxFixture()).style;
      expect(style.isEmpty, isTrue, reason: '$style');
    });
  });

  group('kleuren', () {
    test('tekst-, kop- en accentkleur komen als #RRGGBB', () {
      final style = importDocx(docxStyledFixture()).style;
      expect(style.textColor, '#000000');
      expect(style.headingColor, '#00464F');
      expect(style.accentColor, '#00464F');
    });

    test(
      'een subkop met een andere kleur wordt een verlies, één per kleur',
      () {
        final style = importDocx(docxStyledFixture()).style;
        // Kop 2 is blauw, Kop 3 erft dat via basedOn: samen één melding.
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
      },
    );

    test('subkoppen in dezelfde kleur als Kop 1 zijn geen verlies', () {
      final style = importDocx(
        docxStyledFixture(heading2Color: '00464F'),
      ).style;
      expect(
        style.losses.any(
          (l) => l.kind == DocumentStyleLossKind.perLevelHeadingColor,
        ),
        isFalse,
      );
    });

    test('auto en ontbrekende kleuren worden null', () {
      final style = importDocx(
        docxStyledFixture(
          bodyColor: 'auto',
          heading1Color: null,
          heading2Color: null,
        ),
      ).style;
      expect(style.textColor, isNull);
      expect(style.headingColor, isNull);
    });
  });

  group('kop- en voettekst', () {
    test('de voettekst komt zonder tekstkader en zonder paginanummer', () {
      final style = importDocx(docxStyledFixture()).style;
      expect(style.footerText, 'Information security policy');
      expect(style.showPageNumbers, isTrue);
      expect(style.headerText, isNull);
    });

    test('zonder PAGE-veld geen paginanummers', () {
      final style = importDocx(docxStyledFixture(footerPageField: false)).style;
      expect(style.showPageNumbers, isFalse);
      expect(style.footerText, 'Information security policy');
    });

    test('een voettekst met alleen een tekstkader is leeg', () {
      final style = importDocx(
        docxStyledFixture(footerText: null, footerPageField: false),
      ).style;
      expect(style.footerText, isNull);
    });

    test('de standaardkoptekst komt mee', () {
      final style = importDocx(
        docxStyledFixture(headerText: 'NEO NL — beleid'),
      ).style;
      expect(style.headerText, 'NEO NL — beleid');
    });
  });

  group('logo', () {
    test(
      'het beeldmerk in de standaardvoettekst is de kandidaat, rechtsonder',
      () {
        final logo = fixtureLogoPng();
        final style = importDocx(
          docxStyledFixture(defaultFooterLogo: logo, firstHeaderLogo: logo),
        ).style;
        expect(style.logoCandidates, hasLength(1));
        final candidate = style.logoCandidates.single;
        expect(candidate.origin, DocumentLogoOrigin.footer);
        expect(candidate.position, 'bottom-right');
        expect(candidate.widthMm, closeTo(9.0, 0.05));
        expect(candidate.ext, 'png');
        expect(candidate.bytes, logo);
        expect(candidate.centred, isFalse);
      },
    );

    test('het woordmerk op het titelblad telt niet, maar wordt gemeld', () {
      final style = importDocx(
        docxStyledFixture(firstHeaderLogo: fixtureLogoPng()),
      ).style;
      expect(style.logoCandidates, isEmpty);
      expect(
        style.losses,
        contains(const DocumentStyleLoss(DocumentStyleLossKind.titlePageImage)),
      );
    });

    test('zonder titelblad is het first-deel geen titelblad', () {
      final style = importDocx(
        docxStyledFixture(titlePage: false, firstHeaderLogo: fixtureLogoPng()),
      ).style;
      expect(
        style.losses.any((l) => l.kind == DocumentStyleLossKind.titlePageImage),
        isFalse,
      );
    });

    test('een inline beeld in de standaardkoptekst volgt de uitlijning', () {
      final logo = fixtureLogoPng();
      final left = importDocx(
        docxStyledFixture(defaultHeaderInlineLogo: logo),
      ).style;
      expect(left.logoCandidates.single.position, 'top-left');
      expect(left.logoCandidates.single.origin, DocumentLogoOrigin.header);
      expect(left.logoCandidates.single.widthMm, closeTo(33.3, 0.1));

      final right = importDocx(
        docxStyledFixture(
          defaultHeaderInlineLogo: logo,
          defaultHeaderJc: 'right',
        ),
      ).style;
      expect(right.logoCandidates.single.position, 'top-right');
    });

    test('een gecentreerd beeld wordt links, met een melding', () {
      final style = importDocx(
        docxStyledFixture(
          defaultHeaderInlineLogo: fixtureLogoPng(),
          defaultHeaderJc: 'center',
        ),
      ).style;
      expect(style.logoCandidates.single.position, 'top-left');
      expect(style.logoCandidates.single.centred, isTrue);
      expect(
        style.losses,
        contains(const DocumentStyleLoss(DocumentStyleLossKind.centredLogo)),
      );
    });

    test('een verankerd beeld links van het midden is links', () {
      final style = importDocx(
        docxStyledFixture(
          defaultFooterLogo: fixtureLogoPng(),
          defaultFooterAnchor: const FixtureAnchor(
            xEmu: 474785,
            yEmu: 9398977,
            cxEmu: 2326532,
            cyEmu: 805961,
          ),
        ),
      ).style;
      expect(style.logoCandidates.single.position, 'bottom-left');
    });

    test('een verankerd beeld met uitlijning volgt die uitlijning', () {
      final style = importDocx(
        docxStyledFixture(
          defaultFooterLogo: fixtureLogoPng(),
          defaultFooterAnchor: const FixtureAnchor(
            xEmu: 0,
            yEmu: 9398977,
            cxEmu: 900000,
            cyEmu: 300000,
            alignH: 'right',
          ),
        ),
      ).style;
      expect(style.logoCandidates.single.position, 'bottom-right');
    });

    test('een beeld breder dan het halve blad is geen logo', () {
      final style = importDocx(
        docxStyledFixture(
          defaultFooterLogo: fixtureLogoPng(),
          defaultFooterAnchor: const FixtureAnchor(
            xEmu: 0,
            yEmu: 9398977,
            cxEmu: 7000000,
            cyEmu: 800000,
          ),
        ),
      ).style;
      expect(style.logoCandidates, isEmpty);
    });

    test('een beeld zonder rasterterugval (alleen SVG) wordt gemeld', () {
      final style = importDocx(
        docxStyledFixture(
          defaultFooterLogo: fixtureLogoPng(),
          svgOnlyFooterLogo: true,
        ),
      ).style;
      expect(style.logoCandidates, isEmpty);
      expect(
        style.losses,
        contains(const DocumentStyleLoss(DocumentStyleLossKind.vectorOnlyLogo)),
      );
    });

    test('een beeld dat per bladzijde in de body herhaald is telt ook', () {
      final logo = fixtureLogoPng(seed: 3);
      final style = importDocx(
        docxStyledFixture(
          footerText: null,
          footerPageField: false,
          bodyRepeatedLogo: logo,
          bodyRepeatCount: 4,
        ),
      ).style;
      expect(style.logoCandidates, hasLength(1));
      final candidate = style.logoCandidates.single;
      expect(candidate.origin, DocumentLogoOrigin.body);
      expect(candidate.occurrences, 4);
      expect(candidate.position, 'top-left');
      expect(candidate.widthMm, closeTo(25.0, 0.05));
    });

    test('één los beeld in de body is geen logo', () {
      final style = importDocx(
        docxStyledFixture(
          bodyRepeatedLogo: fixtureLogoPng(),
          bodyRepeatCount: 1,
        ),
      ).style;
      expect(style.logoCandidates, isEmpty);
    });

    test('hetzelfde beeld in koptekst én voettekst blijft twee kandidaten', () {
      final logo = fixtureLogoPng();
      final style = importDocx(
        docxStyledFixture(
          defaultFooterLogo: logo,
          defaultHeaderInlineLogo: logo,
        ),
      ).style;
      expect(
        style.logoCandidates.map((c) => c.position),
        containsAll(['top-left', 'bottom-right']),
      );
    });
  });

  group('beelden in de tekst', () {
    test('worden geteld zodat de import ze kan melden', () {
      final result = importDocx(
        docxStyledFixture(
          bodyRepeatedLogo: fixtureLogoPng(),
          bodyRepeatCount: 3,
        ),
      );
      expect(result.skippedImages, 3);
      expect(importDocx(docxStyledFixture()).skippedImages, 0);
    });

    test('de Markdown zelf verandert niet door de stijl', () {
      final result = importDocx(docxStyledFixture());
      expect(result.markdown, contains('# Beleid'));
      expect(result.markdown, contains('Een alinea.'));
      expect(convertDocxToMarkdown(docxStyledFixture()), result.markdown);
    });
  });
}
