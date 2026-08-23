import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

/// Hoe een voetnoot op het scherm belandt: een klein volgnummer in de tekst en
/// de noot zelf onder een scheiding — niet als losse alinea midden in het
/// verhaal, waar de definitie in de bron toevallig stond.
void main() {
  Future<void> pump(
    WidgetTester tester,
    String markdown, {
    bool atEnd = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DocumentMarkdownView(markdown, footnotesAtEnd: atEnd),
        ),
      ),
    ),
  );

  testWidgets('de definitie staat niet als alinea in de tekst', (tester) async {
    await pump(tester, 'Een zin [^1].\n\n[^1]: De noot.\n\nNog een alinea.\n');

    expect(find.textContaining('[^1]:'), findsNothing);
    expect(find.textContaining('De noot.'), findsOneWidget);
  });

  testWidgets('de verwijzing wordt een nummer, geen [^1]', (tester) async {
    await pump(tester, 'Een zin [^bron].\n\n[^bron]: De noot.\n');

    // Het merkteken is het volgnummer, niet het label dat de auteur koos.
    expect(find.text('1'), findsWidgets);
    expect(find.textContaining('[^bron]'), findsNothing);
  });

  testWidgets('zonder definitie blijft [^1] gewoon tekst', (tester) async {
    // Anders zou een tekenklasse in een technische tekst ineens een merkteken
    // worden.
    await pump(tester, 'Een reguliere expressie: `x` en [^abc] erachter.\n');
    expect(find.textContaining('[^abc]'), findsOneWidget);
  });

  testWidgets('de vellenweergave laat de noten aan de pagina zelf', (
    tester,
  ) async {
    await pump(tester, 'Een zin [^1].\n\n[^1]: De noot.\n', atEnd: false);
    expect(find.textContaining('De noot.'), findsNothing);
    // Het merkteken blijft wél staan: dat hoort bij de tekst.
    expect(find.text('1'), findsWidgets);
  });
}
