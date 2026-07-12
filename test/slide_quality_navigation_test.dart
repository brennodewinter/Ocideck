import 'package:flutter/material.dart';
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
}
