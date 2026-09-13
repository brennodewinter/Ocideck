import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  testWidgets('een Gantt-dia toont zijn titel boven de planning', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.gantt).copyWith(
      title: 'Operatie: verover de vensterbank',
      tableRows: const [
        ['Taak', 'Start', 'Duur', 'Voortgang', 'Afhankelijk van'],
        ['Zonnestralen in kaart brengen', '2026-09-11', '1d', 'done', ''],
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: const ThemeProfile(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Operatie: verover de vensterbank'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
