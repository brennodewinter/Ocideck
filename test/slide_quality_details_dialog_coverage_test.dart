import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/widgets/dialogs/slide_quality_details_dialog.dart';
import 'package:ocideck/widgets/panels/slide_quality_actions.dart';

SlideQualityResult _result() => const SlideQualityResult([
  SlideQualityIssue(
    slideIndex: 0,
    kind: SlideQualityIssueKind.missingAltCaption,
    category: SlideQualityCategory.altText,
    severity: MarkdownValidationSeverity.warning,
    args: {'label': 'Afbeelding'},
  ),
  SlideQualityIssue(
    slideIndex: 1,
    kind: SlideQualityIssueKind.bulletCountHigh,
    category: SlideQualityCategory.textDensity,
    severity: MarkdownValidationSeverity.error,
    args: {'count': '9'},
  ),
  // Deck-wide issue → exercises the isDeckWide "Thema (hele presentatie)" branch.
  SlideQualityIssue(
    slideIndex: kDeckWideSlideIndex,
    kind: SlideQualityIssueKind.imageContrastUnverified,
    category: SlideQualityCategory.contrast,
    severity: MarkdownValidationSeverity.informational,
  ),
]);

Widget _host(void Function(BuildContext) onTap) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => onTap(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('renders a section per severity incl. the deck-wide branch', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host((ctx) => showSlideQualityDetailsDialog(ctx, result: _result())),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Kwaliteitsoverzicht'), findsOneWidget);
    // A section for each of the three severities is rendered.
    expect(find.textContaining('Thema (hele presentatie)'), findsOneWidget);
    expect(find.textContaining('Slide 1'), findsOneWidget);
    expect(find.textContaining('Slide 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an issue closes the dialog and fires onIssueTap', (
    tester,
  ) async {
    SlideQualityIssue? tapped;
    await tester.pumpWidget(
      _host(
        (ctx) => showSlideQualityDetailsDialog(
          ctx,
          result: _result(),
          onIssueTap: (i) => tapped = i,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Slide 1'));
    await tester.pumpAndSettle();

    expect(tapped, isNotNull);
    expect(tapped!.kind, SlideQualityIssueKind.missingAltCaption);
    expect(find.text('Kwaliteitsoverzicht'), findsNothing); // dialog closed
  });

  testWidgets('a quick-fix action closes the dialog and runs', (tester) async {
    var ran = false;
    await tester.pumpWidget(
      _host(
        (ctx) => showSlideQualityDetailsDialog(
          ctx,
          result: _result(),
          actionsFor: (i) => i.kind == SlideQualityIssueKind.bulletCountHigh
              ? [
                  SlideQualityAction(
                    label: 'Splits',
                    icon: Icons.call_split,
                    run: () => ran = true,
                  ),
                ]
              : const [],
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Splits'), findsOneWidget);
    await tester.tap(find.text('Splits'));
    await tester.pumpAndSettle();

    expect(ran, isTrue);
    expect(find.text('Kwaliteitsoverzicht'), findsNothing);
  });

  testWidgets('the close button dismisses the dialog', (tester) async {
    await tester.pumpWidget(
      _host((ctx) => showSlideQualityDetailsDialog(ctx, result: _result())),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // With no quick-fix actions, the dialog's only TextButton is "close".
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('Kwaliteitsoverzicht'), findsNothing);
  });
}
