import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/find_replace_dialog.dart';

/// Behaviour tests for the find-and-replace dialog. The counting and replacing
/// logic is injected, so we drive the dialog with fakes and assert on the live
/// match count, the enable/disable of "Vervang alles", and the replace feedback.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  // Target the search field by its label, not by content: once text is typed
  // the "empty TextField" would otherwise match the still-empty replace field.
  Finder findField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Zoeken naar',
  );

  // Pumps the dialog with an injected match counter and replace runner, and
  // returns the recorded calls so a test can assert what the dialog invoked.
  Future<({List<String> counted, List<String> replaced})> pump(
    WidgetTester tester, {
    required int Function(String, bool) countMatches,
    int Function(String, String, bool)? replaceAll,
  }) async {
    final counted = <String>[];
    final replaced = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FindReplaceDialog(
            countMatches: (q, cs) {
              counted.add(q);
              return countMatches(q, cs);
            },
            replaceAll: (q, r, cs) {
              replaced.add('$q→$r');
              return replaceAll?.call(q, r, cs) ?? 0;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (counted: counted, replaced: replaced);
  }

  testWidgets('shows nothing until a query is typed', (tester) async {
    await pump(tester, countMatches: (_, _) => 3);

    expect(find.textContaining('resulta'), findsNothing);
  });

  testWidgets('typing a query recounts and shows the pluralised total', (
    tester,
  ) async {
    final calls = await pump(
      tester,
      countMatches: (q, _) => q == 'foo' ? 4 : 0,
    );

    await tester.enterText(findField(), 'foo');
    await tester.pump();

    expect(calls.counted, contains('foo'));
    expect(find.text('4 resultaten'), findsOneWidget);
  });

  testWidgets('a single match uses the singular label', (tester) async {
    await pump(tester, countMatches: (_, _) => 1);

    await tester.enterText(findField(), 'x');
    await tester.pump();

    expect(find.text('1 resultaat'), findsOneWidget);
  });

  testWidgets('zero matches shows "Geen resultaten"', (tester) async {
    await pump(tester, countMatches: (_, _) => 0);

    await tester.enterText(findField(), 'zzz');
    await tester.pump();

    expect(find.text('Geen resultaten'), findsOneWidget);
  });

  testWidgets(
    '"Vervang alles" is disabled with no matches, enabled with some',
    (tester) async {
      await pump(tester, countMatches: (q, _) => q == 'hit' ? 2 : 0);

      FilledButton replaceButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Vervang alles'),
      );

      // No query yet → disabled.
      expect(replaceButton().onPressed, isNull);

      await tester.enterText(findField(), 'miss');
      await tester.pump();
      expect(replaceButton().onPressed, isNull, reason: '0 matches → disabled');

      await tester.enterText(findField(), 'hit');
      await tester.pump();
      expect(
        replaceButton().onPressed,
        isNotNull,
        reason: '2 matches → enabled',
      );
    },
  );

  testWidgets('replacing runs the injected replacer and reports the count', (
    tester,
  ) async {
    final calls = await pump(
      tester,
      // After replacing, a re-count of the original query yields 0.
      countMatches: (q, _) => q == 'old' ? 3 : 0,
      replaceAll: (_, _, _) => 3,
    );

    await tester.enterText(findField(), 'old');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Vervang alles'));
    await tester.pump();

    expect(calls.replaced, contains('old→'));
    expect(find.text('3 vervangen'), findsOneWidget);
  });

  testWidgets('the case-sensitivity toggle recounts', (tester) async {
    var lastCaseSensitive = false;
    await pump(
      tester,
      countMatches: (q, cs) {
        lastCaseSensitive = cs;
        return 1;
      },
    );

    await tester.enterText(findField(), 'x');
    await tester.pump();
    expect(lastCaseSensitive, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(lastCaseSensitive, isTrue, reason: 'toggle re-runs the count');
  });
}
