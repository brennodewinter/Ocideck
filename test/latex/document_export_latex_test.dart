// writeDocumentExport naar LaTeX (DOCUMENT_MODE.md §11.2): schrijft de
// GEPROJECTEERDE body weg als een compleet LaTeX article-document — nooit de
// rauwe bron. Bewijst dat het bestand de geredigeerde inhoud bevat, dat de
// preamble aanwezig is, en dat wiskunde rechtstreeks doorkomt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:path/path.dart' as p;

Future<String> _diskLoader(String asset) => File(asset).readAsString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_latexexport_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<ExportBundle> buildBundle(
    String body, {
    TlpLevel tlp = TlpLevel.none,
    ThemeProfile? theme,
    Map<String, String> fields = const {},
  }) => buildDocumentExportBundle(
    body,
    projectPath: null,
    profile: PrivacyExportProfile.full,
    ownIdentity: OwnIdentity.empty,
    regions: defaultPrivacyRegions,
    disabledRules: const {},
    markdownService: MarkdownService(),
    title: 'Rapport',
    tlp: tlp,
    theme: theme,
    fields: fields,
  );

  test('latex-export schrijft een compleet article-document', () async {
    const body = '# Rapport\n\nEen alinea met UNIEKPROZA.\n';
    final bundle = await buildBundle(body);
    final out = p.join(temp.path, 'rapport.tex');
    final written = await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      metadata: const ExportDocumentMetadata(title: 'Rapport', language: 'nl'),
      outputPath: out,
    );
    expect(written, out);
    final tex = await File(out).readAsString();
    // Preamble aanwezig
    expect(tex, contains(r'\documentclass'));
    expect(tex, contains(r'\usepackage{amsmath,amssymb}'));
    expect(tex, contains(r'\usepackage{graphicx}'));
    expect(tex, contains('hyperref'));
    expect(tex, contains(r'\usepackage[dutch]{babel}'));
    // Titel
    expect(tex, contains(r'\title{Rapport}'));
    expect(tex, contains(r'\maketitle'));
    // Body: de geprojecteerde inhoud
    expect(tex, contains('UNIEKPROZA'));
    expect(tex, contains(r'\section{Rapport}'));
    // Postamble
    expect(tex, contains(r'\end{document}'));
  });

  test('latex-export bevat geen rauwe bron-markeerders', () async {
    const body = '# Rapport\n\nTekst.\n';
    final bundle = await buildBundle(body);
    final out = p.join(temp.path, 'rapport.tex');
    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final tex = await File(out).readAsString();
    // Geen Marp-front-matter in een LaTeX-export
    expect(tex.contains('marp: true'), isFalse);
    expect(tex.contains('---\nmarp'), isFalse);
  });

  test('document-TLP staat zichtbaar in LaTeX-kop en -voet', () async {
    const body = '# Rapport\n\nTekst.\n';
    final bundle = await buildBundle(body, tlp: TlpLevel.amberStrict);
    final out = p.join(temp.path, 'rapport-tlp.tex');
    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      // De bundel blijft de bron van de classificatie, ook als deze metadata
      // door een aanroeper onvolledig is samengesteld.
      metadata: const ExportDocumentMetadata(
        title: 'Rapport',
        tlp: TlpLevel.none,
      ),
      outputPath: out,
    );
    final tex = await File(out).readAsString();

    expect(tex, contains(r'\fancyhead[C]'));
    expect(tex, contains(r'\fancyfoot[C]'));
    expect('TLP:AMBER+STRICT'.allMatches(tex), hasLength(2));
    expect(tex, contains(r'\fancyfoot[R]{\thepage}'));
  });

  test('LaTeX-export vult en escapt documentvelden in kop en voet', () async {
    const body = '# Rapport\n\nTekst.\n';
    const theme = ThemeProfile(
      documentHeaderText: '**{title}** · {project-id} · {project_id}',
      documentFooterText: '{author} — {subtitle}',
    );
    final bundle = await buildBundle(
      body,
      theme: theme,
      fields: const {
        'title': 'Audit_2026',
        'subtitle': 'R&D 100%',
        'author': 'Ada & Bob',
        'project-id': 'P-42',
        'project_id': 'P_43',
      },
    );
    final out = p.join(temp.path, 'rapport-velden.tex');

    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final tex = await File(out).readAsString();

    expect(tex, contains(r'\textbf{Audit\_2026} · P-42 · P\_43'));
    expect(tex, contains(r'Ada \& Bob — R\&D 100\%'));
    expect(tex, isNot(contains('{project-id}')));
    expect(tex, isNot(contains('{project_id}')));
    expect(tex, isNot(contains('{subtitle}')));
  });

  test('titelpagina houdt documentchrome en TLP', () async {
    final bundle = await buildBundle(
      '# Titel\n\nTekst.\n',
      theme: const ThemeProfile(documentHeaderText: 'Kop'),
      tlp: TlpLevel.amber,
      fields: const {'title': 'Rapport'},
    );
    final out = p.join(temp.path, 'titelpagina.tex');

    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final tex = await File(out).readAsString();

    expect(tex, contains('\\maketitle\n\\thispagestyle{fancy}\n'));
  });

  test('LaTeX-kop en -voet houden veilige Markdown en bandkleuren', () async {
    const theme = ThemeProfile(
      documentHeaderText:
          '**VERTROUWELIJK** · *cursief* · `code` · ~~oud~~ · '
          '[veilig](https://example.invalid/dossier) · '
          '[onveilig](javascript:alert(1)) · {case-id}',
      documentFooterText: '[mail](mailto:test@example.invalid)',
      documentBandTextColor: '#112233',
      documentBandBackgroundColor: '#DDEEFF',
    );
    final bundle = await buildBundle(
      '# Rapport\n\nTekst.\n',
      theme: theme,
      fields: const {
        'case-id': '**letterlijk** [geen link](https://injectie.invalid)',
      },
    );
    final out = p.join(temp.path, 'chrome.tex');

    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final tex = await File(out).readAsString();

    expect(tex, contains(r'\textbf{VERTROUWELIJK}'));
    expect(tex, contains(r'\textit{cursief}'));
    expect(tex, contains(r'\texttt{code}'));
    expect(tex, contains(r'\sout{oud}'));
    expect(tex, contains(r'\href{https://example.invalid/dossier}{veilig}'));
    expect(tex, contains(r'\href{mailto:test@example.invalid}{mail}'));
    expect(tex, isNot(contains('javascript:')));
    expect(tex, contains('onveilig'));
    expect(
      tex,
      contains('**letterlijk** [geen link](https://injectie.invalid)'),
    );
    expect(tex, isNot(contains(r'\textbf{letterlijk}')));
    expect(tex, isNot(contains(r'\href{https://injectie.invalid}')));
    expect(
      tex,
      contains(r'\definecolor{ocideckDocumentBandText}{HTML}{112233}'),
    );
    expect(
      tex,
      contains(r'\definecolor{ocideckDocumentBandBackground}{HTML}{DDEEFF}'),
    );
    expect(
      r'\colorbox{ocideckDocumentBandBackground}{\textcolor{ocideckDocumentBandText}{'
          .allMatches(tex),
      hasLength(2),
    );
    expect(r'\begin{document}'.allMatches(tex), hasLength(1));
    expect(r'\end{document}'.allMatches(tex), hasLength(1));
    expect('{'.allMatches(tex).length, '}'.allMatches(tex).length, reason: tex);
  });

  test('wiskunde gaat rechtstreeks door in latex-export', () async {
    const body = r'''
# Formules

De formule $E = mc^2$ is bekend.

$$\int_0^1 x\,dx = \frac{1}{2}$$
''';
    final bundle = await buildBundle(body);
    final out = p.join(temp.path, 'formules.tex');
    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final tex = await File(out).readAsString();
    // Inline-math ongewijzigd
    expect(tex, contains(r'$E = mc^2$'));
    // Display-math ongewijzigd (backslash voor komma behouden)
    expect(tex, contains(r'\,'));
    expect(tex, contains(r'\frac{1}{2}'));
  });

  test('tabel wordt tabular met booktabs in latex-export', () async {
    const body = '| Naam | Waarde |\n| --- | --- |\n| Jan | 30 |\n';
    final bundle = await buildBundle(
      body,
      theme: const ThemeProfile(tableBorderStyle: TableBorderStyle.lined),
    );
    final out = p.join(temp.path, 'tabel.tex');
    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final tex = await File(out).readAsString();
    expect(tex, contains(r'\begin{tabular}{ll}'));
    expect(tex, contains(r'\toprule'));
    expect(tex, contains(r'\midrule'));
    expect(tex, contains(r'\bottomrule'));
    expect(tex, contains('Jan'));
  });

  test('LaTeX-export voert de volledige documenttabelstijl uit', () async {
    const body =
        '| Links | Midden | Rechts |\n'
        '| :--- | :---: | ---: |\n'
        '| Een | Twee | Drie |\n'
        '| Vier | Vijf | Zes |\n';
    const theme = ThemeProfile(
      accentColor: '#A1B2C3',
      tableTextColor: '#112233',
      tableHeaderTextColor: '#F1F2F3',
      tableHeaderBackgroundColor: '#223344',
      tableZebraStriped: true,
      tableZebraColor: '#DDEEFF',
      tableBorderStyle: TableBorderStyle.boxed,
      tableBorderColor: '#445566',
      tableCellPaddingPx: 12,
      tableAccentHeaderBorder: true,
    );
    final bundle = await buildBundle(body, theme: theme);
    final out = p.join(temp.path, 'tabelstijl.tex');

    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final tex = await File(out).readAsString();

    expect(tex, contains(r'\usepackage{array}'));
    expect(tex, contains(r'\usepackage[table]{xcolor}'));
    expect(tex, contains(r'\begin{tabular}{|l|c|r|}'));
    expect(tex, contains(r'\definecolor{ocideckTableText}{HTML}{112233}'));
    expect(
      tex,
      contains(r'\definecolor{ocideckTableHeaderText}{HTML}{F1F2F3}'),
    );
    expect(
      tex,
      contains(r'\definecolor{ocideckTableHeaderBackground}{HTML}{223344}'),
    );
    expect(tex, contains(r'\definecolor{ocideckTableZebra}{HTML}{DDEEFF}'));
    expect(tex, contains(r'\definecolor{ocideckTableBorder}{HTML}{445566}'));
    expect(tex, contains(r'\definecolor{ocideckTableAccent}{HTML}{A1B2C3}'));
    expect(tex, contains(r'\arrayrulecolor{ocideckTableBorder}'));
    expect(tex, contains(r'\rowcolors{3}{ocideckTableZebra}{}'));
    expect(tex, contains(r'\setlength{\tabcolsep}{12pt}'));
    expect(tex, contains(r'\setlength{\extrarowheight}{10.8pt}'));
    expect(tex, contains(r'\cellcolor{ocideckTableHeaderBackground}'));
    expect(tex, contains(r'\textcolor{ocideckTableHeaderText}'));
    expect(tex, contains(r'\textcolor{ocideckTableText}'));
    expect(tex, contains(r'\arrayrulecolor{ocideckTableAccent}'));
    expect(tex, contains(r'\specialrule{1.5pt}{0pt}{0pt}'));
  });
}
