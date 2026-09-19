// Van de huisstijl van een brondocument naar een stijlprofiel (#2119).
//
// Bewaakt de vertaling: de letter van de bron wordt een plaatsvervanger op
// het scherm en blijft bewaard voor de export; kleuren en voettekst komen
// mee; het logo landt waar het stond; en wat de bron niet zegt komt niet
// stiekem uit het basisprofiel (geen geleend logo).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/import/imported_document_profile.dart';
import 'package:ocideck/services/import/models/source_document_style.dart';

DocumentLogoCandidate _logo({
  DocumentLogoEdge edge = DocumentLogoEdge.bottom,
  DocumentLogoSide side = DocumentLogoSide.right,
  double widthMm = 9,
}) => DocumentLogoCandidate(
  bytes: Uint8List.fromList([1, 2, 3]),
  ext: 'png',
  sha256: 'abc',
  edge: edge,
  side: side,
  widthMm: widthMm,
  origin: DocumentLogoOrigin.footer,
);

void main() {
  const base = ThemeProfile(
    name: 'Basis',
    fontFamily: 'Georgia',
    textColor: '#333333',
    accentColor: '#2E7D64',
    logoPath: 'logos/basis.png',
    documentFooterText: 'basisvoet',
    documentShowPageNumbers: true,
    documentHeadingColor: '#123456',
  );

  test('een titel alleen is geen stijl', () {
    expect(const SourceDocumentStyle(title: 'X').isEmpty, isTrue);
  });

  group('letters', () {
    test('een vreemde letter krijgt een plaatsvervanger en blijft bewaard', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(
          bodyFontFamily: 'Aptos Light',
          headingFontFamily: 'Aptos',
        ),
        base: base,
        name: 'Stijl van Beleid',
      );
      expect(profile.name, 'Stijl van Beleid');
      expect(profile.fontFamily, 'Calibri');
      expect(profile.preferredFontFamily, 'Aptos Light');
      // Dezelfde plaatsvervanger als de body: geen aparte kopletter op het
      // scherm, wél de eigen naam voor de export.
      expect(profile.documentHeadingFontFamily, isNull);
      expect(profile.preferredDocumentHeadingFontFamily, 'Aptos');
      expect(profile.exportFontFamily, 'Aptos Light');
      expect(profile.exportDocumentHeadingFontFamily, 'Aptos');
    });

    test('een aangeboden letter heeft geen voorkeur nodig', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(
          bodyFontFamily: 'Georgia',
          headingFontFamily: 'Arial',
        ),
        base: base,
        name: 'S',
      );
      expect(profile.fontFamily, 'Georgia');
      expect(profile.preferredFontFamily, isNull);
      expect(profile.documentHeadingFontFamily, 'Arial');
      expect(profile.preferredDocumentHeadingFontFamily, isNull);
    });

    test('koppen in dezelfde letter als de tekst zetten niets aparts', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(
          bodyFontFamily: 'Cambria',
          headingFontFamily: 'cambria',
        ),
        base: base,
        name: 'S',
      );
      expect(profile.fontFamily, 'EB Garamond');
      expect(profile.preferredFontFamily, 'Cambria');
      expect(profile.documentHeadingFontFamily, isNull);
      expect(profile.preferredDocumentHeadingFontFamily, isNull);
    });

    test('zonder letters in de bron blijft de basisletter staan', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(textColor: '#000000'),
        base: base,
        name: 'S',
      );
      expect(profile.fontFamily, 'Georgia');
      expect(profile.preferredFontFamily, isNull);
    });
  });

  group('kleuren en banden', () {
    test('bronkleuren winnen en de afgeleide velden volgen mee', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(
          textColor: '#000000',
          headingColor: '#00464F',
          accentColor: '#00464F',
        ),
        base: base,
        name: 'S',
      );
      expect(profile.textColor, '#000000');
      expect(profile.tableTextColor, '#000000');
      expect(profile.accentColor, '#00464F');
      expect(profile.tableHeaderBackgroundColor, '#00464F');
      expect(profile.checklistCheckedColor, '#00464F');
      expect(profile.documentHeadingColor, '#00464F');
    });

    test('zonder kopkleur in de bron erft het profiel er geen', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(textColor: '#000000'),
        base: base,
        name: 'S',
      );
      expect(profile.documentHeadingColor, isNull);
      expect(profile.accentColor, base.accentColor);
    });

    test('voettekst en paginanummers komen uit de bron, niet uit de basis', () {
      final withFooter = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(
          footerText: 'Information security policy',
          headerText: 'NEO NL',
          showPageNumbers: true,
        ),
        base: base,
        name: 'S',
      );
      expect(withFooter.documentFooterText, 'Information security policy');
      expect(withFooter.documentHeaderText, 'NEO NL');
      expect(withFooter.documentShowPageNumbers, isTrue);

      final without = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(textColor: '#000000'),
        base: base,
        name: 'S',
      );
      expect(without.documentFooterText, '');
      expect(without.documentShowPageNumbers, isFalse);
    });
  });

  group('logo', () {
    test('landt op de plek en de maat uit de bron', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(),
        base: base,
        name: 'S',
        logoPath: 'style_logos/s.png',
        logo: _logo(widthMm: 9),
      );
      expect(profile.documentLogoPath, 'style_logos/s.png');
      expect(profile.documentLogoPosition, 'bottom-right');
      expect(profile.documentLogoSize, 34);
      expect(profile.effectiveDocumentLogoSize, 34);
      // Het presentatielogo van de basis reist niet mee.
      expect(profile.logoPath, isNull);
    });

    test('de maat volgt 96 dpi binnen de grenzen', () {
      expect(documentLogoSizeForWidthMm(9), 34);
      expect(documentLogoSizeForWidthMm(61), 231);
      expect(documentLogoSizeForWidthMm(2), 32);
      expect(documentLogoSizeForWidthMm(200), 480);
    });

    test('zonder logo krijgt het document er bewust geen', () {
      final profile = buildImportedDocumentProfile(
        style: const SourceDocumentStyle(),
        base: base,
        name: 'S',
      );
      expect(profile.documentLogoPath, '');
      expect(profile.effectiveDocumentLogoPath, '');
      expect(profile.logoPath, isNull);
    });
  });

  group('documentStyleMatchesProfile', () {
    const source = SourceDocumentStyle(
      bodyFontFamily: 'Aptos Light',
      headingFontFamily: 'Aptos',
      textColor: '#000000',
      headingColor: '#00464F',
      accentColor: '#00464F',
      footerText: 'Information security policy',
      showPageNumbers: true,
    );

    test('het profiel dat uit dezelfde bron gebouwd is past', () {
      final built = buildImportedDocumentProfile(
        style: source,
        base: base,
        name: 'S',
      );
      expect(documentStyleMatchesProfile(source, built), isTrue);
    });

    test('een ander profiel past niet', () {
      expect(documentStyleMatchesProfile(source, base), isFalse);
      final other = buildImportedDocumentProfile(
        style: source,
        base: base,
        name: 'S',
      ).copyWith(accentColor: '#FF0000');
      expect(documentStyleMatchesProfile(source, other), isFalse);
    });

    test('wat de bron niet zegt telt niet mee', () {
      // Geen letters, geen kleuren in de bron: elk profiel zonder voettekst
      // en zonder paginanummers past — een kop- of voettekst is wél een
      // uitspraak, want een bron zonder voettekst zégt "geen voettekst".
      const sparse = SourceDocumentStyle(bodyFontFamily: 'Georgia');
      expect(
        documentStyleMatchesProfile(
          sparse,
          base.copyWith(documentFooterText: '', documentShowPageNumbers: false),
        ),
        isTrue,
      );
      expect(documentStyleMatchesProfile(sparse, base), isFalse);
    });
  });
}
