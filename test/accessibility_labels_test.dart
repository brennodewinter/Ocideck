import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/bullets_editor.dart';
import 'package:ocideck/widgets/editors/signoff_editor.dart';
import 'package:ocideck/widgets/editors/table_editor.dart';
import 'package:ocideck/widgets/editors/timeline_editor.dart';
import 'package:ocideck/widgets/dialogs/new_deck_dialog.dart';
import 'package:ocideck/widgets/editors/two_images_editor.dart';
import 'package:ocideck/widgets/editors/video_slide_editor.dart';
import 'package:ocideck/widgets/searchable_language_picker.dart';

/// Toegankelijkheidsvangrail voor de editors.
///
/// De audit vroeg om expliciete toegankelijkheidstests. De invariant die hier
/// bewaakt wordt is de meest basale en tegelijk de makkelijkst te breken:
/// **elke knop moet een toegankelijke naam hebben**. Een icoonknop zonder
/// tooltip of semantieklabel is voor een schermlezer een naamloze knop —
/// WCAG 2.2 SC 4.1.2 (Naam, rol, waarde).
///
/// De editors dragen die naam vandaag via `IconButton(tooltip:)`; deze test
/// dwingt af dát er een naam is, niet hóe die wordt geleverd. Een nieuwe kale
/// `IconButton` valt hier dus om, ongeacht of de auteur voor een tooltip of een
/// expliciete `Semantics` kiest.

/// De editors leunen op Riverpod (de beeldkiezerbalk leest een provider) en op
/// de app-localisatie, dus beide moeten om de widget heen staan.
Widget _testApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// De wortel van de semantiekboom, gezocht over de hele PipelineOwner-boom:
/// sinds de multi-view-ondersteuning hangt de SemanticsOwner niet meer
/// gegarandeerd aan de wortel-owner zelf, maar aan een van zijn kinderen.
SemanticsNode? _rootSemanticsNode(WidgetTester tester) {
  SemanticsNode? found;
  void search(PipelineOwner owner) {
    found ??= owner.semanticsOwner?.rootSemanticsNode;
    owner.visitChildren(search);
  }

  search(tester.binding.rootPipelineOwner);
  return found;
}

/// Alle knopen in de semantiekboom die zich als knop aanbieden maar geen naam
/// dragen. Leeg is goed.
///
/// De naam mag uit het label óf uit de tooltip komen: Flutter houdt die apart,
/// en een `Tooltip` om een `IconButton` levert de naam via het tooltip-veld.
List<String> unnamedButtons(WidgetTester tester) {
  final offenders = <String>[];
  final root = _rootSemanticsNode(tester);
  if (root == null) return offenders;

  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final isButton =
        data.flagsCollection.isButton || data.flagsCollection.isLink;
    final hasName =
        data.label.trim().isNotEmpty || data.tooltip.trim().isNotEmpty;
    // Een uitgeschakelde knop is voor een schermlezer nog steeds aankondigbaar
    // en heeft dus net zo goed een naam nodig; die sluiten we niet uit.
    if (isButton && !hasName) {
      offenders.add('knop zonder naam op ${node.rect} (node ${node.id})');
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return offenders;
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  // De editors met een uniforme (slide, onUpdate)-constructor, elk met het
  // slidetype waarvoor ze bedoeld zijn.
  final editors = <String, Widget Function(Slide, ValueChanged<Slide>)>{
    'BulletsEditor': (slide, onUpdate) =>
        BulletsEditor(slide: slide, onUpdate: onUpdate),
    'TableEditor': (slide, onUpdate) =>
        TableEditor(slide: slide, onUpdate: onUpdate),
    'TimelineEditor': (slide, onUpdate) => TimelineEditor(
      slide: slide,
      onUpdate: onUpdate,
      themeAnimationDurationMs: 0,
    ),
    'TwoImagesEditor': (slide, onUpdate) =>
        TwoImagesEditor(slide: slide, onUpdate: onUpdate),
    'SignOffEditor': (slide, onUpdate) =>
        SignOffEditor(slide: slide, onUpdate: onUpdate),
    'VideoSlideEditor': (slide, onUpdate) => VideoSlideEditor(
      slide: slide,
      onUpdate: onUpdate,
      imageService: ImageService(),
    ),
  };

  final slideTypes = <String, SlideType>{
    'BulletsEditor': SlideType.bullets,
    'TableEditor': SlideType.table,
    'TimelineEditor': SlideType.timeline,
    'TwoImagesEditor': SlideType.twoImages,
    'SignOffEditor': SlideType.signOff,
    'VideoSlideEditor': SlideType.video,
  };

  group('Elke knop draagt een toegankelijke naam (WCAG 4.1.2)', () {
    for (final entry in editors.entries) {
      testWidgets('${entry.key} laat geen naamloze knop achter', (
        tester,
      ) async {
        // Een ruim oppervlak: editors die zelf niet scrollen lopen anders over
        // de standaard 800x600 testviewport heen en gooien een layoutfout.
        await tester.binding.setSurfaceSize(const Size(1400, 2800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Expliciet opruimen aan het eind van de body: de controle op actieve
        // SemanticsHandles draait vóór addTearDown.
        final handle = tester.ensureSemantics();

        final slide = Slide.create(slideTypes[entry.key]!);
        await tester.pumpWidget(_testApp(entry.value(slide, (_) {})));
        await tester.pumpAndSettle();

        final offenders = unnamedButtons(tester);
        handle.dispose();

        expect(
          offenders,
          isEmpty,
          reason:
              '${entry.key} bevat knoppen zonder tooltip of semantieklabel; '
              'een schermlezer kondigt die aan als naamloze knop',
        );
      });
    }

    // De twee zoekveld-wisknoppen uit #1247. De bronscan hieronder vangt een
    // kale Tooltip om een IconButton, maar níet een kale IconButton zonder
    // tooltip — en deze twee dialogen werden bovendien door geen enkele widget-
    // test gepompt met de clear-knop in beeld. De knop is pas zichtbaar als er
    // tekst in het zoekveld staat, dus typen we eerst.
    testWidgets(
      'de taalkiezer-wisknop draagt een naam als hij zichtbaar is (#1247)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _testApp(
            SearchableLanguagePicker(
              languageCode: 'en',
              onLanguageChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Open de dialoog en typ iets, zodat de wisknop verschijnt.
        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'neder');
        await tester.pump();

        final offenders = unnamedButtons(tester);
        handle.dispose();

        expect(
          offenders,
          isEmpty,
          reason:
              'de wisknop in de taalkiezer heeft geen tooltip; een schermlezer '
              'kondigt hem aan als naamloze knop (WCAG 4.1.2)',
        );
      },
    );

    testWidgets(
      'de sjabloonzoek-wisknop draagt een naam als hij zichtbaar is (#1247)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_testApp(const NewDeckDialog()));
        await tester.pumpAndSettle();
        // Typ in het sjabloonzoekveld, zodat de wisknop verschijnt.
        await tester.enterText(
          find.byKey(const ValueKey('templateSearchField')),
          'brief',
        );
        await tester.pump();

        final offenders = unnamedButtons(tester);
        handle.dispose();

        expect(
          offenders,
          isEmpty,
          reason:
              'de wisknop in de sjabloonzoek heeft geen tooltip; een schermlezer '
              'kondigt hem aan als naamloze knop (WCAG 4.1.2)',
        );
      },
    );
  });

  testWidgets('de vangrail merkt een kale icoonknop daadwerkelijk op', (
    tester,
  ) async {
    // Zonder deze zelftest zou een fout in unnamedButtons() de hele suite
    // stilletjes groen houden.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _testApp(IconButton(icon: const Icon(Icons.delete), onPressed: () {})),
    );
    await tester.pump();

    final offenders = unnamedButtons(tester);
    handle.dispose();

    expect(offenders, isNotEmpty);
  });

  // ── De bronscan (#586) ────────────────────────────────────────────────────
  //
  // De tests hierboven pompen zes editors. Er zijn er 26, plus 41 dialogen,
  // plus de presentatiemodus — die allemaal pompen is duur, en tot het zover is
  // liet deze poort 23 knoppen door met precies de fout die hij bewaakt.
  //
  // Het waren er 23 van één soort: `Tooltip(message: …, child: IconButton(…))`.
  // Dat lést als een knop met een naam en is het niet — een `Tooltip` eromheen
  // zet géén semantieklabel op de knop, alleen `IconButton(tooltip:)` doet dat.
  // Voor een schermlezer heet de uitknop van een presentatie dan "knop".
  //
  // Eén patroon, mechanisch te herkennen, dus een bronscan is hier goedkoper
  // dan 67 widgettests en vangt bovendien de plekken die niemand ooit pompt.
  test('geen enkele IconButton zit in een kale Tooltip', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'\bTooltip\(').allMatches(source)) {
        final close = _matchingParen(source, match.end - 1);
        if (close < 0) continue;
        final body = source.substring(match.end, close);
        if (!RegExp(r'child:\s*IconButton\(').hasMatch(body)) continue;
        if (RegExp(r'tooltip:').hasMatch(body)) continue;
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'een Tooltip om een IconButton geeft de knop géén toegankelijke '
          'naam; zet de tekst in IconButton(tooltip: …) — dat doet allebei',
    );
  });
}

/// De index van de `)` die hoort bij de `(` op [open], met aanhalingstekens
/// overgeslagen zodat een haakje in een tekst niet meetelt.
int _matchingParen(String source, int open) {
  var depth = 0;
  var i = open;
  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"') {
      final quote = c;
      i++;
      while (i < source.length && source[i] != quote) {
        if (source[i] == r'\') i++;
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}
