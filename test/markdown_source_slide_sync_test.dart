import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';

/// Twee dia's met genoeg tekst om binnen één dia te kunnen slepen.
const _source =
    '# Eerste\n\nregel een van de eerste dia\n\n---\n\n'
    '# Tweede\n\nregel een van de tweede dia\n';

/// Bootst het editorpaneel na: de melding van de bron-editor verandert de
/// actieve dia, en die komt als nieuw [MarkdownDeckEditor.slideNumber] terug.
/// Zonder die terugkoppeling mist de test precies de lus die de selectie sloopt.
class _PanelHost extends StatefulWidget {
  const _PanelHost();

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  int slideNumber = 1;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 1600,
            child: MarkdownDeckEditor(
              initialContent: _source,
              onApply: (_) => true,
              parseError: false,
              onExitMarkdown: () {},
              onScopeChanged: (_) {},
              slideNumber: slideNumber,
              slideCount: 2,
              onActiveSlideChanged: (index) =>
                  setState(() => slideNumber = index + 1),
            ),
          ),
        ),
      ),
    );
  }
}

TextEditingController _sourceController(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText).last).controller;

void main() {
  testWidgets('selectie over een diagrens blijft staan', (tester) async {
    await tester.pumpWidget(const _PanelHost());
    final controller = _sourceController(tester);

    // Slepen vanaf de eerste dia tot in de tweede, zoals een muissleep dat doet.
    final start = _source.indexOf('regel een van de eerste dia');
    final end = _source.indexOf('regel een van de tweede dia') + 10;
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    await tester.pumpAndSettle();

    expect(
      controller.selection,
      TextSelection(baseOffset: start, extentOffset: end),
      reason: 'de dia-wissel mag de lopende selectie niet platslaan',
    );
  });

  testWidgets('cursor blijft staan waar je in een andere dia klikt', (
    tester,
  ) async {
    await tester.pumpWidget(const _PanelHost());
    final controller = _sourceController(tester);

    // Midden in de tweede dia klikken: de actieve dia mag meelopen, maar de
    // cursor hoort niet naar het begin van die dia te springen.
    final offset = _source.indexOf('regel een van de tweede dia') + 6;
    controller.selection = TextSelection.collapsed(offset: offset);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, offset);
    expect(
      tester.state<State>(find.byType(_PanelHost)),
      isA<_PanelHostState>().having(
        (state) => state.slideNumber,
        'slideNumber',
        2,
      ),
    );
  });
}
