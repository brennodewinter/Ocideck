import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// #1164 — een dia die één pagina van een gesplitste reeks is, toont naast zijn
/// titel een "(page/total)"-teller, zodat spreker en publiek zien dat de lijst
/// doorloopt. Een losse dia toont niets extra.
Widget _host(Slide slide, {({int page, int total})? position}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: slide,
            themeProfile: const ThemeProfile(),
            splitRunPosition: position,
          ),
        ),
      ),
    ),
  );
}

void main() {
  Slide bullets(String title) => Slide.create(
    SlideType.bullets,
  ).copyWith(title: title, bullets: const ['Een', 'Twee', 'Drie']);

  // De teller loopt als trailing-span mee in dezelfde paragraaf als de titel,
  // dus titel én teller zitten in één rich-text — zoeken gaat met textContaining.
  testWidgets('een reeks-pagina toont de teller naast de titel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(bullets('Aanpak'), position: (page: 2, total: 3)),
    );
    await tester.pump();
    expect(find.textContaining('Aanpak'), findsOneWidget);
    expect(find.textContaining('2/3'), findsOneWidget);
  });

  testWidgets('een losse dia toont geen teller', (tester) async {
    await tester.pumpWidget(_host(bullets('Aanpak')));
    await tester.pump();
    expect(find.textContaining('Aanpak'), findsOneWidget);
    // Geen enkel "x/y"-tellertje.
    expect(find.textContaining(RegExp(r'\d+/\d+')), findsNothing);
  });

  testWidgets('een reeks van één pagina toont geen teller', (tester) async {
    // total == 1 is geen reeks: de teller blijft weg, ook als er een positie is.
    await tester.pumpWidget(
      _host(bullets('Aanpak'), position: (page: 1, total: 1)),
    );
    await tester.pump();
    expect(find.textContaining(RegExp(r'\d+/\d+')), findsNothing);
  });

  testWidgets('de teller werkt ook op een tweekoloms dia', (tester) async {
    final slide = Slide.create(SlideType.twoBullets).copyWith(
      title: 'Vergelijking',
      bullets: const ['links een', 'links twee'],
      bullets2: const ['rechts een', 'rechts twee'],
    );
    await tester.pumpWidget(_host(slide, position: (page: 3, total: 4)));
    await tester.pump();
    expect(find.textContaining('3/4'), findsOneWidget);
  });
}
