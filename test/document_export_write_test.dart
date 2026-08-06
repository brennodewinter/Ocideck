// writeDocumentExport (DOCUMENT_MODE.md §11.2): schrijft de GEPROJECTEERDE body
// weg — nooit de rauwe bron — als plat `.md` of als één doorlopend HTML-document.
// Deze test bewijst dat beide formaten een bestand op schijf zetten met de
// geredigeerde inhoud, en dat de HTML-vorm de doorlopende (continuous) route
// neemt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
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
    temp = await Directory.systemTemp.createTemp('ocideck_docexport_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  const body = '# Rapport\n\nEen alinea met UNIEKPROZA.\n';

  Future<void> withBundle(Future<void> Function(ExportBundle bundle) fn) async {
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Rapport',
    );
    await fn(bundle);
  }

  test('md-export schrijft de geprojecteerde platte body', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        outputPath: out,
      );
      expect(written, out);
      final content = await File(out).readAsString();
      expect(content.contains('UNIEKPROZA'), isTrue);
      // Geen deck-scaffold: een document-export draagt geen `marp:`-kop.
      expect(content.contains('marp: true'), isFalse);
    });
  });

  test('html-export schrijft één doorlopend document, geen dia', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.html');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.html,
        html: MarpHtmlService(loadAsset: _diskLoader),
        outputPath: out,
      );
      expect(written, out);
      final html = await File(out).readAsString();
      expect(html.contains('<section class="document"'), isTrue);
      expect(html.contains('<section class="slide'), isFalse);
      // De body reist door de inerte markdown-poort.
      expect(html.contains('<script type="text/markdown">'), isTrue);
      expect(html.contains('# Rapport'), isTrue);
    });
  });
}
