import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/shell/document_import_action.dart';

import 'helpers/docx_fixture.dart';
import 'helpers/odt_fixture.dart';

/// Het document van het actieve tabblad, of `null` als er geen open staat.
String? _openDocumentSource(ProviderContainer container) {
  final content = container.read(tabsProvider).current?.content;
  return content is DocumentTabContent
      ? content.documentNotifier.currentState.document?.source
      : null;
}

/// Het invoerpunt van de document-import: bestandskiezer → conversie → nieuw
/// documenttabblad.
///
/// De bestandskiezer laat zich onder `flutter test` niet aansturen (statische
/// `FilePicker`), dus de tests gaan door de `fileOverride`-route — dezelfde
/// code op de keuze na. Wat hier bewaakt wordt is dat een import nooit stil
/// half slaagt: geen tabblad zonder melding, en geen melding zonder tabblad.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
  });

  Future<(ProviderContainer, BuildContext)> pump(WidgetTester tester) async {
    late BuildContext ctx;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScaffoldMessenger(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    return (container, ctx);
  }

  testWidgets('een gekozen .docx opent als document in een nieuwe tab', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    await importDocument(
      ctx,
      fileOverride: (bytes: docxFixture(), name: 'rapport.docx'),
    );
    await tester.pump();

    final source = _openDocumentSource(container);
    expect(source, isNotNull);
    expect(source, contains('# Titel'));
    expect(find.textContaining('geïmporteerd'), findsOneWidget);
    container.dispose();
  });

  testWidgets('een gekozen .odt opent als document in een nieuwe tab', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    await importDocument(
      ctx,
      fileOverride: (bytes: odtFixture(), name: 'brief.odt'),
    );
    await tester.pump();

    final source = _openDocumentSource(container);
    expect(source, isNotNull);
    expect(source, contains('# Titel'));
    container.dispose();
  });

  testWidgets('een onleesbaar bestand meldt de fout en opent geen tab', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    await importDocument(
      ctx,
      fileOverride: (
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        name: 'kapot.docx',
      ),
    );
    await tester.pump();

    expect(_openDocumentSource(container), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    container.dispose();
  });

  testWidgets('een vreemde extensie meldt de fout en opent geen tab', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    await importDocument(
      ctx,
      fileOverride: (
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        name: 'memo.pages',
      ),
    );
    await tester.pump();

    expect(_openDocumentSource(container), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    container.dispose();
  });

  test('het menulabel komt uit de vertaling, niet uit de aanroeper', () {
    AppLocalizations.setActiveLanguageCode('nl');
    final label = documentImportLabel(const AppLocalizations(Locale('nl')));
    expect(label, isNotEmpty);
    expect(label.toLowerCase(), contains('importeren'));
  });
}
