import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/document_deck_bridge.dart';
import 'package:ocideck/services/latex/markdown_to_latex.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:path/path.dart' as p;

Future<String> _diskLoader(String asset) => File(asset).readAsString();

String _incidentTimeline({String? sensitiveValue}) {
  final rows = List.generate(19, (index) {
    final value = sensitiveValue ?? 'Feit $index';
    return '| ${index.toString().padLeft(2, '0')}:00 | $value | Bron $index |';
  }).join('\n');
  return '''<!-- timeline -->
| Tijd | Gebeurtenis | Bron |
| --- | --- | --- |
$rows''';
}

int _occurrences(String source, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(source).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const source = '''<!-- timeline -->
| Tijd | Gebeurtenis | Status |
| --- | --- | --- |
| 12:02 | Eerste melding | Gemeld |
| 13:41 | Herstelclaim **weerlegd** | Vastgesteld |''';

  test('LaTeX projecteert de tijdlijn zonder gewone tabular', () {
    final latex = markdownToLatex(source);
    expect(latex, contains(r'\begin{description}'));
    expect(latex, contains('12:02'));
    expect(latex, contains(r'Herstelclaim \textbf{weerlegd}'));
    expect(latex, contains('Status: Vastgesteld'));
    expect(latex, isNot(contains(r'\begin{tabular}')));
  });

  test(
    'continue HTML draagt tijdlijnstructuur en printveilige kaarten',
    () async {
      final html = await MarpHtmlService(
        loadAsset: _diskLoader,
      ).build(source, continuous: true);
      expect(html, contains('ocideck-timeline-marker'));
      expect(
        html,
        contains('ocideck-timeline-marker" aria-hidden="true"></div>\n\n|'),
      );
      expect(html, contains("list.className='ocideck-timeline'"));
      expect(html, contains("timeLabel.className='ocideck-timeline-label'"));
      expect(html, contains("eventLabel.className='ocideck-timeline-label'"));
      expect(html, contains('ocideck-timeline-card::before'));
      expect(
        html,
        contains(
          'ocideck-timeline li:last-child .ocideck-timeline-time::after',
        ),
      );
      expect(html, contains('break-inside:avoid'));
      expect(html, contains('13:41'));
    },
  );

  test('continue HTML en LaTeX behouden alle 19 gebeurtenissen', () async {
    final incident = _incidentTimeline();
    final html = await MarpHtmlService(
      loadAsset: _diskLoader,
    ).build(incident, continuous: true);
    final latex = markdownToLatex(incident);

    expect(html, contains("list.className='ocideck-timeline'"));
    expect(latex, contains(r'\begin{description}'));
    expect(_occurrences(latex, r'\item[\textbf{'), 19);
    for (var index = 0; index < 19; index++) {
      expect(html, contains('Feit $index'));
      expect(html, contains('Bron $index'));
      expect(latex, contains('Feit $index'));
      expect(latex, contains('Bron: Bron $index'));
    }
  });

  group('OciWacht houdt marker en tabel atomair per tekstexport', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('ocideck_timeline_export_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test(
      'Markdown, continue HTML en LaTeX gebruiken dezelfde projectie',
      () async {
        const bsn = '728398242';
        final bundle = await buildDocumentExportBundle(
          _incidentTimeline(sensitiveValue: 'BSN $bsn bevestigd'),
          projectPath: null,
          profile: PrivacyExportProfile.redacted,
          ownIdentity: OwnIdentity.empty,
          regions: defaultPrivacyRegions,
          disabledRules: const {},
          markdownService: MarkdownService(),
        );
        final service = MarpHtmlService(loadAsset: _diskLoader);
        final outputs = <DocumentExportFormat, String>{};
        for (final format in const [
          DocumentExportFormat.md,
          DocumentExportFormat.html,
          DocumentExportFormat.latex,
        ]) {
          final path = p.join(temp.path, 'tijdlijn.${format.name}');
          await writeDocumentExport(
            bundle,
            format,
            html: service,
            enforcementPolicy: const ClassificationEnforcementPolicy(),
            outputPath: path,
          );
          outputs[format] = await File(path).readAsString();
        }

        for (final output in outputs.values) {
          expect(output, isNot(contains(bsn)));
          expect(_occurrences(output, kRedactionToken), 19);
          for (var index = 0; index < 19; index++) {
            expect(output, contains('Bron $index'));
          }
        }
        expect(
          outputs[DocumentExportFormat.md],
          contains('<!-- timeline -->\n| Tijd | Gebeurtenis | Bron |'),
        );
        expect(
          outputs[DocumentExportFormat.html],
          contains('ocideck-timeline-marker'),
        );
        expect(
          outputs[DocumentExportFormat.latex],
          contains(r'\begin{description}'),
        );
        expect(
          outputs[DocumentExportFormat.latex],
          isNot(contains(r'\begin{tabular}')),
        );
      },
    );

    test('een onbruikbare tijdlijn behoudt exacte kolomkopcontext', () {
      const bsn = '728398242';
      const source =
          '<!-- timeline -->\n'
          '| Tijd | Feit | Bron | BSN |\n'
          '| --- | --- | --- | --- |\n'
          '| 12:02 | melding | loket | $bsn |';
      final deck = DocumentDeckBridge.documentToDeck(source);
      final findings = const PrivacyScanner()
          .scan(deck)
          .findings
          .where((finding) => finding.ruleId == 'nl.bsn')
          .toList();

      expect(findings, hasLength(1));
      expect(findings.single.field, 'customMarkdown');
      expect(findings.single.confidence, PrivacyConfidence.certain);
      final projected = PrivacyProjection.forAudience(
        deck,
        profile: PrivacyExportProfile.redacted,
      );
      expect(
        DocumentDeckBridge.deckToDocumentMarkdown(projected.deck),
        isNot(contains(bsn)),
      );
    });

    test('een lange tijdlijncel indexeert kolomcontext één keer', () {
      const repetitions = 5000;
      const bsn = '728398242';
      final repeated = List.filled(repetitions, bsn).join(' ');
      final source =
          '<!-- timeline -->\n'
          '| Tijd | BSN | Bron |\n'
          '| --- | --- | --- |\n'
          '| 12:02 | $repeated | logboek |';
      final findings = const PrivacyScanner()
          .scan(DocumentDeckBridge.documentToDeck(source))
          .findings
          .where((finding) => finding.ruleId == 'nl.bsn');

      expect(findings, hasLength(repetitions));
      expect(
        findings.every(
          (finding) => finding.confidence == PrivacyConfidence.certain,
        ),
        isTrue,
      );
    });
  });
}
