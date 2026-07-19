// Springt een melding naar het juiste stuk tekst?
//
// De scanner leest de bullet zoals hij in de markdown staat — met tabs voor het
// niveau en `[ ] ` voor een checklist-item. Het tekstveld toont die opmaak niet.
// Een positie uit de scan één op één toepassen accentueert dus het verkeerde
// stuk, precies zo veel te ver naar rechts als de opmaak lang is. Deze test
// bewaakt die omrekening, want de fout is stil: er stáát een accentuering, hij
// wijst alleen niet naar het gemelde gegeven.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/widgets/editors/bullets_editor.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Bouwt de opsommingseditor en meldt een bevinding op bullet [fragment],
  /// tekens [start]–[end] van de **ruwe** bullet. Geeft de selectie terug die
  /// het tekstveld daarna toont.
  Future<TextSelection> selectionFor(
    WidgetTester tester, {
    required List<String> bullets,
    required ListStyle listStyle,
    required int fragment,
    required int start,
    required int end,
  }) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: bullets, listStyle: listStyle);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BulletsEditor(slide: slide, onUpdate: (_) {}),
          ),
        ),
      ),
    );

    container
        .read(editorProvider.notifier)
        .selectWithQualityField(
          0,
          'bullets',
          span: SlideQualitySpan(
            start: start,
            end: end,
            fragmentIndex: fragment,
          ),
        );
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    final target = fields.firstWhere(
      (f) =>
          f.controller?.selection.isValid == true &&
          !f.controller!.selection.isCollapsed,
      orElse: () => fields.first,
    );
    return target.controller!.selection;
  }

  testWidgets('een gewone bullet wordt op de gemelde tekens geaccentueerd', (
    tester,
  ) async {
    // 'Bel Marieke' — de scanner meldt 'Marieke' op 4–11.
    final selection = await selectionFor(
      tester,
      bullets: ['Bel Marieke'],
      listStyle: ListStyle.bullets,
      fragment: 0,
      start: 4,
      end: 11,
    );

    expect(selection.baseOffset, 4);
    expect(selection.extentOffset, 11);
  });

  testWidgets('een checklist-item verschuift met de opmaak mee', (
    tester,
  ) async {
    // Ruw staat er '[ ] Bel Marieke'; het tekstveld toont 'Bel Marieke'. De
    // scanner meldt 8–15 in de ruwe tekst, dus 4–11 in het veld. Zonder de
    // omrekening zou hier 8–15 geaccentueerd worden — voorbij het einde van
    // 'Bel Marieke', en dus het verkeerde stuk of niets.
    final selection = await selectionFor(
      tester,
      bullets: ['[ ] Bel Marieke'],
      listStyle: ListStyle.checklist,
      fragment: 0,
      start: 8,
      end: 15,
    );

    expect(selection.baseOffset, 4);
    expect(selection.extentOffset, 11);
  });

  testWidgets('een ingesprongen bullet verschuift met zijn tabs mee', (
    tester,
  ) async {
    // Twee tabs voor het niveau; het veld toont alleen de kale tekst.
    final selection = await selectionFor(
      tester,
      bullets: ['Eerste punt', '\t\tBel Marieke'],
      listStyle: ListStyle.bullets,
      fragment: 1,
      start: 6,
      end: 13,
    );

    expect(selection.baseOffset, 4);
    expect(selection.extentOffset, 11);
  });

  testWidgets('een melding buiten het bereik accentueert niets', (
    tester,
  ) async {
    // De auteur kan doorgetypt hebben terwijl het paneel openstond. Dan liever
    // geen accentuering dan een verkeerde — en zeker geen crash op een
    // TextSelection die buiten de tekst valt.
    final selection = await selectionFor(
      tester,
      bullets: ['Kort'],
      listStyle: ListStyle.bullets,
      fragment: 0,
      start: 40,
      end: 47,
    );

    expect(selection.isCollapsed || !selection.isValid, isTrue);
  });
}
