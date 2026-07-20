import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

/// Een schil die de stand van buitenaf omzet, zoals de echte werkbalk doet.
class _Host extends StatefulWidget {
  const _Host({required this.controller});

  final TextEditingController controller;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  NotesEditorMode mode = NotesEditorMode.markdown;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() {
            mode = mode == NotesEditorMode.markdown
                ? NotesEditorMode.visual
                : NotesEditorMode.markdown;
          }),
          child: const Text('wissel'),
        ),
        Expanded(
          child: MarkdownNotesEditor.legacy(
            controller: widget.controller,
            baseStyle: const TextStyle(fontSize: 16, color: Colors.black),
            linkColor: Colors.blue,
            hintText: 'Notities',
            mode: mode,
            showModeToggle: false,
          ),
        ),
      ],
    );
  }
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  // De heen-en-terugweg door de rijke-tekstlaag is niet verliesvrij. Wie de
  // visuele stand alleen aanzet om te kíjken, mag daar geen tekst aan
  // overhouden die stuk is.
  for (final geval in const [
    ('een tabel', '| Poort | Status |\n| --- | --- |\n| 443 | open |'),
    ('backslash-ontsnappingen', r'Prijs is 5 \* 3, pad C:\\temp'),
    ('een voetnoot', 'Zie hier[^1]\n\n[^1]: de noot'),
  ]) {
    testWidgets('kijken in de visuele stand laat ${geval.$1} intact', (
      tester,
    ) async {
      final controller = TextEditingController(text: geval.$2);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_testApp(_Host(controller: controller)));
      await tester.tap(find.text('wissel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('wissel'));
      await tester.pumpAndSettle();

      expect(controller.text, geval.$2);
    });
  }

  testWidgets('een echte wijziging in de visuele stand komt wél terug', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'begin');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(_Host(controller: controller)));
    await tester.tap(find.text('wissel'));
    await tester.pumpAndSettle();

    final quill = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    quill.replaceText(
      quill.document.length - 1,
      0,
      ' en meer',
      const TextSelection.collapsed(offset: 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('wissel'));
    await tester.pumpAndSettle();

    expect(controller.text, contains('en meer'));
  });
}
