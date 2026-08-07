// writeDocumentExport naar LaTeX (DOCUMENT_MODE.md §11.2): schrijft de
// GEPROJECTEERDE body weg als een compleet LaTeX article-document — nooit de
// rauwe bron. Bewijst dat het bestand de geredigeerde inhoud bevat, dat de
// preamble aanwezig is, en dat wiskunde rechtstreeks doorkomt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
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

  Future<ExportBundle> buildBundle(String body) => buildDocumentExportBundle(
    body,
    projectPath: null,
    profile: PrivacyExportProfile.full,
    ownIdentity: OwnIdentity.empty,
    regions: defaultPrivacyRegions,
    disabledRules: const {},
    markdownService: MarkdownService(),
    title: 'Rapport',
  );

  test('latex-export schrijft een compleet article-document', () async {
    const body = '# Rapport\n\nEen alinea met UNIEKPROZA.\n';
    final bundle = await buildBundle(body);
    final out = p.join(temp.path, 'rapport.tex');
    final written = await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
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
      outputPath: out,
    );
    final tex = await File(out).readAsString();
    // Geen Marp-front-matter in een LaTeX-export
    expect(tex.contains('marp: true'), isFalse);
    expect(tex.contains('---\nmarp'), isFalse);
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
    final bundle = await buildBundle(body);
    final out = p.join(temp.path, 'tabel.tex');
    await writeDocumentExport(
      bundle,
      DocumentExportFormat.latex,
      html: MarpHtmlService(loadAsset: _diskLoader),
      outputPath: out,
    );
    final tex = await File(out).readAsString();
    expect(tex, contains(r'\begin{tabular}{ll}'));
    expect(tex, contains(r'\toprule'));
    expect(tex, contains(r'\midrule'));
    expect(tex, contains(r'\bottomrule'));
    expect(tex, contains('Jan'));
  });
}
