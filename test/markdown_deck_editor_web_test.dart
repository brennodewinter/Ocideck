@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';

// Draai met `flutter test --platform chrome test/markdown_deck_editor_web_test.dart`.
// Bewust zónder de synchrone runner uit markdown_deck_editor_test.dart: die
// vervanging verborg dat de standaardrunner in de browser op `Isolate.run`
// stukliep (#2764).

void main() {
  testWidgets('web: de broncontrole levert bij openen en na wijzigen (#2764)', (
    tester,
  ) async {
    expect(kIsWeb, isTrue, reason: 'deze regressie vereist een echte browser');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MarkdownDeckEditor(
              // Ongesloten front matter: een fout op een vaste regel.
              initialContent: '---\nmarp: true\n# nooit gesloten\n',
              onApply: (_) => true,
              parseError: false,
              onExitMarkdown: () {},
              onScopeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Controleren…'), findsNothing);
    expect(find.textContaining('fout(en),'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      '---\nmarp: true\n---\n\n# ok\n',
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Controleren…'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Controleren…'), findsNothing);
    expect(find.text('Geen syntaxproblemen gevonden'), findsOneWidget);

    // Een editor die verdwijnt terwijl een ronde gepland staat, krijgt geen
    // setState meer: dat zou hier als uitzondering bovenkomen.
    await tester.enterText(find.byType(TextField).last, '# weg\n');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });
}
