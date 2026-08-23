import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/editors/finding_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The finding editor's test picker (feedback #8) links the finding to a
/// checklist test and actively writes it back to the matching checklist row.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  testWidgets('picking a test links the finding and marks the checklist row', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);

    final scope = Slide.create(SlideType.scopeMatrix).copyWith(
      title: 'Scope',
      tableRows: ScopeMatrixSpec(
        title: 'Scope',
        rows: const [
          ScopeRow(object: 'https://app.example', type: ScopeObjectType.web),
        ],
      ).toTableRows(),
    );
    final checklist = Slide.create(SlideType.checklist).copyWith(
      title: 'OWASP WSTG v4.2',
      tableRows: ChecklistSpec(
        standardLabel: 'OWASP WSTG v4.2',
        rows: const [
          ChecklistRow(id: 'WSTG-ATHN-07', test: 'Weak password policy'),
        ],
      ).toTableRows(),
      checklistScope: 'https://app.example',
    );
    final finding = Slide.create(SlideType.finding).copyWith(
      findingId: 'F-1',
      customMarkdown: const FindingSpec(
        heading: 'F-1',
        scopeObject: 'https://app.example',
      ).toMarkdown(),
    );
    notifier.loadDeck(Deck(title: 'D', slides: [finding, scope, checklist]));

    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FindingEditor(
              slide: finding,
              onUpdate: (s) {
                updated = s;
                notifier.updateSlide(0, s);
              },
              imageService: ImageService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The picker offers the checklist's test for this scope object.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WSTG-ATHN-07 — Weak password policy').last);
    await tester.pumpAndSettle();

    // The finding records the link…
    expect(updated!.customMarkdown, contains('**Test:** `WSTG-ATHN-07`'));

    // …and the checklist row is now an anomaly linked to F-1.
    final checklistOut = container
        .read(deckProvider)
        .deck!
        .slides
        .firstWhere((s) => s.type == SlideType.checklist);
    final row = ChecklistSpec.fromSlide(
      checklistOut.title,
      checklistOut.tableRows,
    ).rows.single;
    expect(row.findingId, 'F-1');
    expect(row.status, ChecklistStatus.anomaly);
  });

  testWidgets('no checklist for the scope object shows a hint, no dropdown', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    final finding = Slide.create(SlideType.finding).copyWith(
      findingId: 'F-1',
      customMarkdown: const FindingSpec(
        heading: 'F-1',
        scopeObject: 'https://app.example',
      ).toMarkdown(),
    );
    notifier.loadDeck(Deck(title: 'D', slides: [finding]));

    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FindingEditor(
              slide: finding,
              onUpdate: (_) {},
              imageService: ImageService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Maak eerst een checklist voor dit scope-object.'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
}
