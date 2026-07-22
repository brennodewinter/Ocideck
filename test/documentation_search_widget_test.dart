import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/documentation_service.dart';
import 'package:ocideck/widgets/reader/documentation_search_tab.dart';

/// Returns canned bodies so the search can be driven without bundled assets.
class _FakeDocService implements DocumentationService {
  _FakeDocService(this.bodies);
  final Map<String, String> bodies;

  @override
  Future<String> load(String baseAsset, String languageCode) async =>
      bodies[baseAsset] ?? '';

  @override
  Future<({String text, bool isBaseVersion})> loadDetailed(
    String baseAsset,
    String languageCode,
  ) async => (text: await load(baseAsset, languageCode), isBaseVersion: true);
}

void main() {
  // 'nl' makes d() return its argument verbatim, so titles/messages are
  // predictable to assert on.
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  final sections = [
    DocSection(
      label: 'Gebruiker',
      entries: const [
        DocEntry(icon: Icons.book, title: 'Alpha', assetBase: 'a.md'),
        DocEntry(icon: Icons.book, title: 'Beta', assetBase: 'b.md'),
      ],
    ),
    DocSection(
      label: 'Techniek',
      entries: const [
        DocEntry(icon: Icons.book, title: 'Gamma', assetBase: 'c.md'),
      ],
    ),
  ];

  Future<void> pump(WidgetTester tester) async {
    final service = _FakeDocService({
      'a.md': 'Alpha document about riverpod state management.',
      'b.md': 'Beta document about pdf export in an isolate.',
      'c.md': 'Gamma document about the timeline slide type.',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocumentationSearchTab(sections: sections, service: service),
          ),
        ),
      ),
    );
    // Let didChangeDependencies load the canned bodies.
    await tester.pumpAndSettle();
  }

  testWidgets('empty query shows every document', (tester) async {
    await pump(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('a body word narrows the list to the matching document', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'riverpod');
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Gamma'), findsNothing);
    // The empty-section heading ("Techniek") is hidden when it has no matches.
    expect(find.text('TECHNIEK'), findsNothing);
  });

  testWidgets('a word absent from every document shows the empty message', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'zzzznotpresent');
    await tester.pumpAndSettle();

    expect(find.text('Geen documenten gevonden'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('clearing the query restores the full list', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'riverpod');
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });
}
