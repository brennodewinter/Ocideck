import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cvss_builder.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/editors/finding_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The finding editor shows a context (CIA-weighted) score beside the base score
/// when the finding's scope object is rated on the scope matrix, and offers a
/// dropdown to pick a scope object from the matrix.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  const baseVector =
      'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N';

  Future<Slide> pump(WidgetTester tester, {required bool rated}) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    final scope = Slide.create(SlideType.scopeMatrix).copyWith(
      title: 'Scope',
      tableRows: ScopeMatrixSpec(
        rows: [
          ScopeRow(
            object: 'https://app.example',
            cia: rated
                ? const CiaRating(
                    confidentiality: CiaLevel.low,
                    integrity: CiaLevel.low,
                    availability: CiaLevel.low,
                  )
                : const CiaRating(),
          ),
        ],
      ).toTableRows(),
    );
    final finding = Slide.create(SlideType.finding).copyWith(
      findingId: 'F-1',
      customMarkdown: const FindingSpec(
        heading: 'F-1',
        scopeObject: 'https://app.example',
        cvssVector: baseVector,
      ).toMarkdown(),
    );
    notifier.updateSlide(0, scope);
    notifier.insertSlides([finding], afterIndex: 0);

    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
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
    return finding;
  }

  testWidgets('shows base + context score for a rated scope object', (
    tester,
  ) async {
    await pump(tester, rated: true);
    // Base 9.3 (Critical) and CIA-weighted context 8.9 (High).
    expect(find.textContaining('Basis 9.3'), findsOneWidget);
    expect(find.textContaining('Context 8.9'), findsOneWidget);
    expect(find.text('CVSS-wizard'), findsOneWidget);
  });

  testWidgets('shows only the base score when the object is unrated', (
    tester,
  ) async {
    await pump(tester, rated: false);
    expect(find.textContaining('Basis 9.3'), findsOneWidget);
    expect(find.textContaining('Context'), findsNothing);
  });

  testWidgets('offers a dropdown to pick a scope object from the matrix', (
    tester,
  ) async {
    await pump(tester, rated: true);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('https://app.example'), findsWidgets);
  });
}
