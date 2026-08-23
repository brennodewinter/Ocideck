import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/slide_quality_navigation.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/state/editor_provider.dart';

/// Tests navigation from a quality issue to its editor field. A per-slide issue
/// selects that slide and arms its field for focus; the deck-wide branch (which
/// opens the settings dialog) is exercised by the settings-dialog tests.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('a per-slide issue selects the slide and arms its field', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const issue = SlideQualityIssue(
      slideIndex: 2,
      kind: SlideQualityIssueKind.slideContrast,
      category: SlideQualityCategory.contrast,
      severity: MarkdownValidationSeverity.warning,
      field: 'textColor',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => navigateToSlideQualityIssue(
                  context: context,
                  ref: ref,
                  issue: issue,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();

    final state = container.read(editorProvider);
    expect(state.selectedIndex, 2);
    expect(state.selection, {2});
    expect(state.focusQualityField, 'textColor');
  });

  test('een privacybevinding op de front matter hoort niet bij het thema', () {
    // Deckbreed betekende ooit vanzelf "thema". Sinds de privacyscanner ook de
    // front matter leest is dat niet meer waar, en stuurde de navigatie een
    // e-mailadres in het auteursveld naar de kleurinstellingen — waar het veld
    // niet bestaat, dus zonder markering en zonder scroll.
    const finding = SlideQualityIssue(
      slideIndex: kDeckWideSlideIndex,
      kind: SlideQualityIssueKind.privacyContact,
      category: SlideQualityCategory.privacy,
      severity: MarkdownValidationSeverity.warning,
      field: 'author',
    );
    expect(issueBelongsToDeckInfo(finding), isTrue);
  });

  test('een deckbrede contrastmelding blijft bij de kleurinstellingen', () {
    const contrast = SlideQualityIssue(
      slideIndex: kDeckWideSlideIndex,
      kind: SlideQualityIssueKind.themeContrast,
      category: SlideQualityCategory.contrast,
      severity: MarkdownValidationSeverity.warning,
      field: 'textColor',
    );
    expect(issueBelongsToDeckInfo(contrast), isFalse);
  });

  test('een melding op een dia is nooit een deckgegeven', () {
    const onSlide = SlideQualityIssue(
      slideIndex: 3,
      kind: SlideQualityIssueKind.privacyContact,
      category: SlideQualityCategory.privacy,
      severity: MarkdownValidationSeverity.warning,
      // Zelfde veldnaam als een deckveld ('title' bestaat op beide niveaus);
      // de slide-index moet de doorslag geven.
      field: 'deckTitle',
    );
    expect(issueBelongsToDeckInfo(onSlide), isFalse);
  });
}
