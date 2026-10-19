// Toetst dat het bedrijfslogo op papier de maat krijgt die de instelling
// belooft — niet de verkleinde schaal waarmee de export hem lange tijd
// wegzette (#2462). De meting gebeurt op het getekende beeld in het bestand
// zelf, via de plaatsingsmatrix in de inhoudsstroom.
//
// De getallen: een logische pixel op het scherm is 1/96 duim, een PDF-punt
// 1/72 duim — dezelfde fysieke maat deelt dus de factor `kCssPxPerPoint`.
// Het standaardprofiel valt terug op `logoSize` (96 px → 72 pt, een duim).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/pdf/document_pdf_export.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';

import 'pdf_text_probe.dart';

void main() {
  const labels = DocumentPdfLabels(
    footnotesTitle: 'Noten',
    mathLabel: 'formule',
    mermaidLabel: 'diagram',
    chartLabel: 'grafiek',
  );

  /// Een breed beeldmerk, 16×2 beeldpunten — de verhouding van een
  /// woordmerk. Breed genoeg dat in elk kader de breedte bindt.
  final wideLogo = Uint8List.fromList(
    img.encodePng(img.Image(width: 16, height: 2)),
  );

  /// Een vierkant beeldmerk, 4×4 beeldpunten.
  final squareLogo = Uint8List.fromList(
    img.encodePng(img.Image(width: 4, height: 4)),
  );

  Future<Uint8List> pdfWithLogo(ThemeProfile theme, Uint8List logo) async {
    final bundle = await buildDocumentExportBundle(
      '# Offerte\n\nEen alinea tekst.\n',
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      theme: theme,
    );
    final result = await buildDocumentExportPdf(
      bundle,
      labels: labels,
      embedImage: (source) async =>
          'data:image/png;base64,${base64Encode(logo)}',
    );
    return result.bytes;
  }

  test('het standaardprofiel tekent het logo een duim breed', () async {
    // Geen documentLogoSize → terugval op logoSize 96 px = 72 pt.
    const theme = ThemeProfile(documentLogoPath: 'merk.png');
    final (width, _) = pdfDrawnImageBoxes(
      await pdfWithLogo(theme, wideLogo),
    ).single;
    expect(width, closeTo(72, 1));
  });

  test('een grotere instelling geeft voorspelbaar een groter logo', () async {
    // 240 px × 72/96 = 180 pt.
    const theme = ThemeProfile(
      documentLogoPath: 'merk.png',
      documentLogoSize: 240,
    );
    final (width, height) = pdfDrawnImageBoxes(
      await pdfWithLogo(theme, wideLogo),
    ).single;
    expect(width, closeTo(180, 1.5));
    // 4:1-verhouding: de hoogte volgt uit het beeld, geen uitrekking.
    expect(height, closeTo(22.5, 1.5));
  });

  test('een breed logo blijft binnen de tekstspiegel', () async {
    // 480 px × 72/96 = 360 pt — meer dan het aandeel dat de band aan het
    // logo geeft; de koptekst moet overeind blijven.
    const theme = ThemeProfile(
      documentLogoPath: 'merk.png',
      documentLogoSize: 480,
    );
    final bytes = await pdfWithLogo(theme, wideLogo);
    final (width, _) = pdfDrawnImageBoxes(bytes).single;
    // A4: 210 mm − 2 × 20 mm marge = 481,9 pt spiegel; de band geeft het
    // logo maximaal het vaste aandeel daarvan.
    final contentPt = (210 - 40) * 72 / 25.4;
    expect(width, closeTo(contentPt * kDocumentBandLogoWidthShare, 2));
    expect(width, lessThan(contentPt));
  });

  test('een hoog logo overstijgt de kopmarge niet', () async {
    // De band leeft ín de bovenmarge (25 mm ≈ 71 pt); een vierkant logo op
    // grote maat mag nooit over de eerste tekstregel heen vallen.
    const theme = ThemeProfile(
      documentLogoPath: 'merk.png',
      documentLogoSize: 320,
    );
    final (_, height) = pdfDrawnImageBoxes(
      await pdfWithLogo(theme, squareLogo),
    ).single;
    final marginPt = 25 * 72 / 25.4;
    expect(height, lessThan(marginPt));
  });

  test('documentLogoWidthPt deelt de fysieke maat met het scherm', () {
    // De gedeelde maatregel: zelfde instelling, zelfde papierbreedte —
    // voor PDF, voorvertoning en band (#2462).
    expect(const ThemeProfile().documentLogoWidthPt, closeTo(72, 0.01));
    expect(
      const ThemeProfile(documentLogoSize: 240).documentLogoWidthPt,
      closeTo(180, 0.01),
    );
    // De ondergrens van het instelbereik (32 px) blijft leesbaar: 24 pt.
    expect(
      const ThemeProfile(documentLogoSize: 1).documentLogoWidthPt,
      closeTo(24, 0.01),
    );
  });
}
