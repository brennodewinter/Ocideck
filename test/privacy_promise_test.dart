import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/redaction_manifest.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/export_service.dart';
import 'package:ocideck/services/privacy/privacy_export_policy.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';
import 'package:ocideck/widgets/privacy_statement_content.dart';

// De belofte, en de grens eromheen.
//
// "De controle garandeert niet dat alles wordt gevonden; ze verkleint de kans dat
// er persoonsgegevens onbedoeld uitlekken."
//
// Dat is de hele belofte, en ze is bewust kleiner dan de feature aanvoelt. Wie
// denkt dat de controle álles vindt, deelt op grond van die aanname — en dan
// heeft een gemiste bevinding méér schade aangericht dan geen controle, want dan
// had hij tenminste zelf gekeken.
//
// Een belofte die je stilletjes kunt oprekken is geen belofte. Vandaar deze test.
const _promise =
    'De controle garandeert niet dat alles wordt gevonden; '
    'ze verkleint de kans dat er persoonsgegevens onbedoeld uitlekken.';

const _clean = SlideQualityResult([]);

const _hasIssues = SlideQualityResult([
  SlideQualityIssue(
    slideIndex: 0,
    kind: SlideQualityIssueKind.imageContrastUnverified,
    category: SlideQualityCategory.contrast,
    severity: MarkdownValidationSeverity.warning,
  ),
]);

ExportBundle _emptyBundle(PrivacyExportProfile profile) => ExportBundle(
  audience: PrivacyProjection.forAudience(
    const Deck(title: 'Test'),
    profile: profile,
  ),
  markdown: '',
  manifest: RedactionManifest.empty,
  privacySummary: PrivacyExportSummary.empty,
);

Widget _exportDialog(SlideQualityResult quality) => MaterialApp(
  home: Scaffold(
    body: ExportDialog(
      deckPath: '/tmp/deck.md',
      bundleFor: _emptyBundle,
      exportService: ExportService(),
      qualityResult: quality,
    ),
  ),
);

void main() {
  group('het exportdialoog', () {
    testWidgets('noemt de grens óók als er níets is gevonden', (tester) async {
      // Dít is het gevaarlijke geval, en daarom de belangrijkste test van de
      // twee. Een deck mét bevindingen waarschuwt zichzelf al. Een deck zónder
      // bevindingen toont een groen "Klaar voor export — geen kwaliteitsproblemen
      // gevonden", en dát leest als "schoon". Terwijl het niet meer zegt dan: wij
      // hebben niets gevonden.
      await tester.pumpWidget(_exportDialog(_clean));

      expect(find.textContaining('Klaar voor export'), findsOneWidget);
      expect(find.text(_promise), findsOneWidget);
    });

    testWidgets('en ook als er wél iets is gevonden', (tester) async {
      await tester.pumpWidget(_exportDialog(_hasIssues));

      expect(find.text(_promise), findsOneWidget);
    });
  });

  testWidgets('de privacyverklaring noemt de grens', (tester) async {
    // De verklaring gaat óók door de toestemmingspoort, vóór het eerste gebruik.
    // Daar hoort de grens te staan, niet alleen de belofte.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PrivacyStatementContent()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('De privacycontrole'), findsOneWidget);
    expect(find.text(_promise), findsOneWidget);
    expect(
      find.textContaining(
        'niet een dia waarvan vaststaat dat er niets in staat',
      ),
      findsOneWidget,
    );
  });
}
