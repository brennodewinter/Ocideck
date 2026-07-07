import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';

/// Host die de omvang (en bijbehorende inhoud) kan wisselen zoals het
/// echte editorpaneel dat doet: de widget blijft bestaan, alleen [scope] en
/// [initialContent] veranderen, zodat de toggle animeert en didUpdateWidget
/// de nieuwe inhoud inlaadt.
class _ScopeHost extends StatefulWidget {
  final String deckContent;
  final String slideContent;
  const _ScopeHost({required this.deckContent, required this.slideContent});

  @override
  State<_ScopeHost> createState() => _ScopeHostState();
}

class _ScopeHostState extends State<_ScopeHost> {
  MarkdownScope _scope = MarkdownScope.deck;

  @override
  Widget build(BuildContext context) {
    final isSlide = _scope == MarkdownScope.slide;
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: MarkdownDeckEditor(
            initialContent: isSlide ? widget.slideContent : widget.deckContent,
            onApply: (_) => true,
            parseError: false,
            onExitMarkdown: () {},
            scope: _scope,
            slideNumber: 2,
            slideCount: 5,
            onScopeChanged: (s) => setState(() => _scope = s),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('scope toggle shows both segments with the slide counter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ScopeHost(deckContent: 'DECK-MD', slideContent: 'SLIDE-MD'),
    );

    expect(find.text('Volledige presentatie'), findsOneWidget);
    expect(find.textContaining('Deze slide'), findsOneWidget);
    expect(find.textContaining('2/5'), findsOneWidget);
    // Start op deck-omvang: de deck-markdown staat in het tekstveld.
    expect(find.widgetWithText(TextField, 'DECK-MD'), findsOneWidget);
  });

  testWidgets('tapping "Deze slide" switches scope and reloads the content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ScopeHost(deckContent: 'DECK-MD', slideContent: 'SLIDE-MD'),
    );

    await tester.tap(find.textContaining('Deze slide'));
    await tester.pumpAndSettle();

    // De widget bleef bestaan, maar didUpdateWidget laadde de slide-markdown.
    expect(find.widgetWithText(TextField, 'SLIDE-MD'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'DECK-MD'), findsNothing);

    // En terug naar de hele presentatie.
    await tester.tap(find.text('Volledige presentatie'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'DECK-MD'), findsOneWidget);
  });
}
