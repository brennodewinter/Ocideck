import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';

/// De kopkleur van een documentstijl.
///
/// Zonder dit veld kon een document geen rustige broodtekst mét koppen in de
/// huisstijlkleur dragen: een hoofdstukkop volgde de tekstkleur en een subkop
/// het accent, dus wie de bodytekst temperde kreeg een grijze `#` boven een
/// gekleurde `##` — dat leest als een vergissing. Bewaakt wordt niet dat het
/// veld bestaat, maar dat het overal aankomt waar een kop getekend wordt: het
/// model, de documentweergave in de app, de HTML-export die de browserafdruk
/// maakt, en de PDF-export. Eén ervan overslaan levert een document op dat op
/// het ene oppervlak anders staat dan op het andere.
const _md = '''
---
marp: true
theme: ocideck
---

# Kop

Een alinea.

### Subkop
''';

void main() {
  group('model', () {
    test('zonder de kleur blijft de oude verdeling staan', () {
      const profile = ThemeProfile(
        name: 'Test',
        textColor: '#222222',
        accentColor: '#2E7D64',
      );
      expect(profile.documentHeadingColor, isNull);
      expect(profile.effectiveDocumentHeadingColor, '#222222');
      expect(profile.effectiveDocumentSubheadingColor, '#2E7D64');
    });

    test('met de kleur dragen alle kopniveaus hem', () {
      const profile = ThemeProfile(
        name: 'Huisstijl',
        textColor: '#1F2933',
        accentColor: '#2E7D64',
        documentHeadingColor: '#003399',
      );
      expect(profile.effectiveDocumentHeadingColor, '#003399');
      expect(profile.effectiveDocumentSubheadingColor, '#003399');
    });

    test('de kleur overleeft toJson → fromJson', () {
      const profile = ThemeProfile(
        name: 'Huisstijl',
        documentHeadingColor: '#003399',
      );
      expect(
        ThemeProfile.fromJson(profile.toJson()).documentHeadingColor,
        '#003399',
      );
    });

    test('een profiel van vóór dit veld leest als niet-gezet', () {
      final legacy = ThemeProfile.fromJson(const {'name': 'Oud'});
      expect(legacy.documentHeadingColor, isNull);
      expect(legacy.effectiveDocumentHeadingColor, legacy.textColor);
      expect(legacy.effectiveDocumentSubheadingColor, legacy.accentColor);
    });
  });

  group('weergave', () {
    /// De kleuren van de eerste drie tekstblokken: kop, alinea, subkop.
    List<Color?> blockColors(WidgetTester tester) => tester
        .widgetList<InlineMarkdownText>(find.byType(InlineMarkdownText))
        .take(3)
        .map((w) => w.style.color)
        .toList();

    Future<void> pumpDocument(WidgetTester tester, ThemeProfile profile) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentMarkdownView(
              '# Kop\n\nEen alinea.\n\n### Subkop\n',
              maxTextWidth: null,
              themeProfile: profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'zonder de kleur volgt de kop de tekst en de subkop het accent',
      (tester) async {
        await pumpDocument(
          tester,
          const ThemeProfile(
            name: 'Test',
            textColor: '#222222',
            accentColor: '#2E7D64',
          ),
        );

        final colors = blockColors(tester);
        expect(
          colors[0],
          const Color(0xFF222222),
          reason: 'kop volgt de tekst',
        );
        expect(colors[1], const Color(0xFF222222), reason: 'alinea');
        expect(
          colors[2],
          const Color(0xFF2E7D64),
          reason: 'subkop volgt accent',
        );
      },
    );

    testWidgets('met de kleur dragen beide koppen hem, de alinea niet', (
      tester,
    ) async {
      await pumpDocument(
        tester,
        const ThemeProfile(
          name: 'Huisstijl',
          textColor: '#1F2933',
          accentColor: '#2E7D64',
          documentHeadingColor: '#003399',
        ),
      );

      final colors = blockColors(tester);
      expect(colors[0], const Color(0xFF003399));
      expect(colors[1], const Color(0xFF1F2933), reason: 'de tekst blijft');
      expect(colors[2], const Color(0xFF003399));
    });
  });

  group('pdf', () {
    test('de kopkleur landt in de PDF-stijl', () {
      final style = DocumentPdfStyle.fromTheme(
        const ThemeProfile(
          textColor: '#1F2933',
          accentColor: '#2E7D64',
          documentHeadingColor: '#003399',
        ),
      );
      expect(style.headingColor.toHex().toUpperCase(), contains('003399'));
      expect(style.subheadingColor.toHex().toUpperCase(), contains('003399'));
    });

    test('zonder de kleur volgt de PDF de oude verdeling', () {
      final style = DocumentPdfStyle.fromTheme(
        const ThemeProfile(textColor: '#1F2933', accentColor: '#2E7D64'),
      );
      expect(style.headingColor.toHex().toUpperCase(), contains('1F2933'));
      expect(style.subheadingColor.toHex().toUpperCase(), contains('2E7D64'));
    });
  });

  group('export', () {
    Future<String> documentHtml(ThemeProfile theme) => MarpHtmlService(
      loadAsset: (asset) => File(asset).readAsString(),
    ).build(_md, continuous: true, theme: theme);

    test('de kopkleur landt op élk kopniveau in de CSS', () async {
      final html = await documentHtml(
        const ThemeProfile(
          name: 'Huisstijl',
          textColor: '#1F2933',
          accentColor: '#2E7D64',
          documentHeadingColor: '#003399',
        ),
      );

      expect(
        html,
        contains('.document h1{color:var(--ocideck-title-color,#003399)}'),
      );
      expect(
        html,
        contains(
          '.document h2,.document h3,.document h4,.document h5,'
          '.document h6{color:#003399}',
        ),
      );
    });

    test('zonder de kleur blijft de export bij de oude verdeling', () async {
      final html = await documentHtml(
        const ThemeProfile(
          name: 'Test',
          textColor: '#222222',
          accentColor: '#2E7D64',
        ),
      );

      expect(
        html,
        contains('.document h1{color:var(--ocideck-title-color,#222222)}'),
      );
      // h3 tot en met h6 stonden hier niet: die vielen in de export terug op de
      // bodykleur terwijl de app ze wél als subkop kleurde.
      expect(
        html,
        contains(
          '.document h2,.document h3,.document h4,.document h5,'
          '.document h6{color:#2E7D64}',
        ),
      );
    });
  });
}
