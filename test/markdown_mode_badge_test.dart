import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';

// De modus-balk van de markdown-editor toont links een status-badge: het
// <>-icoon met het woord 'Bron' (#1187). Het was een kale, klikbaar-ogende
// icoon; nu leest het als label — een woord ernaast is geen knop. Deze test
// bewaakt dat het label er is en dat het icoon níet in een knop zit.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MarkdownDeckEditor(
              initialContent: '# Titel',
              onApply: (_) => true,
              parseError: false,
              onExitMarkdown: () {},
              scope: MarkdownScope.slide,
              slideNumber: 1,
              slideCount: 1,
              onScopeChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the mode banner labels the <> icon as a "Bron" status badge', (
    tester,
  ) async {
    await pump(tester);

    // Het woord staat er als leesbaar label. (Het <>-glyph zelf zit óók op een
    // echte 'Code'-opmaakknop in de werkbalk — juist daarom las een kaal icoon
    // in de balk als klikbaar; het label lost dat op.)
    expect(find.text('Bron'), findsOneWidget);
  });

  testWidgets('the "Bron" badge is passive — not a control', (tester) async {
    await pump(tester);

    // Het label zit in geen enkel bedieningselement: het is een status-badge,
    // geen knop die een belofte wekt die hij niet waarmaakt (#1187).
    for (final control in [
      IconButton,
      TextButton,
      InkWell,
      InkResponse,
      GestureDetector,
    ]) {
      expect(
        find.ancestor(
          of: find.text('Bron'),
          matching: find.byWidgetPredicate((w) => w.runtimeType == control),
        ),
        findsNothing,
        reason: 'de "Bron"-badge mag niet in een $control zitten',
      );
    }
  });
}
