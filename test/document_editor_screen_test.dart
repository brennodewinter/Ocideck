import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/theme_profile_logo.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(DocumentNotifier notifier) => ProviderScope(
    overrides: [documentProvider.overrideWith((ref) => notifier)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DocumentEditorScreen(),
    ),
  );

  /// Wissel naar bron-modus (standaard is Visueel).
  Future<void> openSource(WidgetTester tester) async {
    await tester.tap(find.text('Bron'));
    await tester.pump();
  }

  testWidgets('standaard Visueel: bewerkbaar oppervlak + moduskeuze', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Visueel | Bron staat in de werkbalk.
    expect(find.text('Visueel'), findsOneWidget);
    expect(find.text('Bron'), findsOneWidget);
    // Standaard visueel: de gedeelde notes-editor, geen read-only preview.
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(find.byType(DocumentMarkdownView), findsNothing);
    // Eenvoudige markdown → Quill-WYSIWYG (bewerkbaar).
    expect(find.byType(QuillEditor), findsOneWidget);
  });

  testWidgets('Visueel: een tabel valt niet terug op ruwe markdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n'
          '| Team | Omzet |\n| --- | ---: |\n| Ontwerp | 120 |\n',
        ),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // De regressie (#1328): een tabel dwong Visueel naar de ruwe-markdown-
    // terugval. Nu blijft het de bewerkbare WYSIWYG — de tabel is een embed.
    expect(find.byType(MarkdownNotesEditor), findsOneWidget);
    expect(find.byType(QuillEditor), findsOneWidget);
    // De tabel wordt als gerenderde embed getekend (DocumentMarkdownView), niet
    // als de letterlijke tekst `| Team | Omzet |` in een tekstveld.
    expect(find.byType(DocumentMarkdownView), findsWidgets);
    expect(find.text('| Team | Omzet |'), findsNothing);
  });

  testWidgets('Visueel: een inhoudsopgave valt niet terug op ruwe markdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Rapport\n\n<!-- toc -->\n\n## Eerste deel\n\nTekst.\n',
        ),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // De regressie: `<!-- toc -->` is HTML-commentaar, en dat wierp de hele
    // visuele modus terug op brontekst — je zag ineens je ruwe markdown.
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.textContaining('Bronmodus beschermt opmaak'), findsNothing);
    // De marker wordt de inhoudsopgave-voorbeeldweergave, met de koppen van
    // het document erin — niet de letterlijke markertekst.
    expect(find.text('<!-- toc -->'), findsNothing);
    expect(find.text('Inhoudsopgave'), findsOneWidget);
    expect(find.text('Eerste deel'), findsWidgets);
  });

  testWidgets(
    'Visueel: rauwe HTML blijft bewerkbaar met opmaakbalk en waarschuwing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(
          MarkdownDocument.parse('# Kop\n\n<div>rauwe html</div>\n\nTekst.'),
        );
      await tester.pumpWidget(harness(n));
      await tester.pump();

      // Een constructie die de brug niet verliesvrij aankan valt níet terug op
      // een read-only leesweergave (OciDeck beslist niet vóór de gebruiker dat
      // een document onbewerkbaar is): de gedeelde notes-editor blijft, nu op de
      // bewerkbare brontekst — geen Quill-WYSIWYG, geen gerenderde leesweergave.
      expect(find.byType(MarkdownNotesEditor), findsOneWidget);
      expect(find.byType(QuillEditor), findsNothing);
      expect(find.byType(DocumentMarkdownView), findsNothing);
      // De volledige opmaakknoppenbalk blijft binnen bereik...
      expect(find.byTooltip('Vet'), findsOneWidget);
      expect(find.byTooltip('Kop'), findsOneWidget);
      // ...met een begrijpelijke waarschuwing dat je hier de brontekst bewerkt.
      expect(find.textContaining('Bronmodus beschermt opmaak'), findsOneWidget);

      // En het is écht bewerkbaar: typen stroomt live naar de notifier.
      await tester.enterText(
        find.byType(TextField),
        '# Kop\n\n<div>rauwe html</div>\n\nGewijzigd.',
      );
      await tester.pump();
      expect(n.currentState.document!.source, contains('Gewijzigd.'));
      expect(n.currentState.isDirty, isTrue);
    },
  );

  testWidgets('de breedtekiezer en de zoom staan in de werkbalk', (
    tester,
  ) async {
    // #1: de volle breedte gebruiken en in- of uitzoomen moet tijdens het
    // werken kunnen, niet alleen via een dialoog in de instellingen — waar de
    // breedte-instelling bovendien stil werd overruled door de pagina-einden.
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Op ware grootte valt er niets terug te zetten, dus staat er geen
    // percentage in de weg.
    expect(find.text('100%'), findsNothing);
    await tester.tap(find.byTooltip('Inzoomen'));
    await tester.pumpAndSettle();
    expect(find.text('110%'), findsOneWidget);

    // Het percentage is zelf de weg terug naar ware grootte.
    await tester.tap(find.text('110%'));
    await tester.pumpAndSettle();
    expect(find.text('110%'), findsNothing);

    // De breedtekiezer biedt de drie standen.
    await tester.tap(find.byTooltip('Schrijfbreedte'));
    await tester.pumpAndSettle();
    expect(find.text('Paginabreedte'), findsOneWidget);
    expect(find.text('Leeskolom'), findsOneWidget);
    expect(find.text('Volledige breedte'), findsOneWidget);
  });

  testWidgets('Cmd+= zoomt in en Cmd+0 zet terug op ware grootte', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Tekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // De binding zelf aanroepen, zoals de Cmd+S-toets hierboven: een
    // toetsaanslag komt in een test niet bij `CallbackShortcuts` zonder focus
    // in de boom, en wat hier bewezen moet worden is de bedrading.
    void invoke(LogicalKeyboardKey key) {
      for (final widget in tester.widgetList<CallbackShortcuts>(
        find.byType(CallbackShortcuts),
      )) {
        for (final entry in widget.bindings.entries) {
          final activator = entry.key;
          if (activator is SingleActivator &&
              activator.trigger == key &&
              activator.meta) {
            entry.value();
            return;
          }
        }
      }
      fail('geen sneltoets gebonden aan Cmd+${key.keyLabel}');
    }

    // `equal` en niet `add`: op de meeste indelingen zit + op shift-=, en dan
    // is dat de toets die het toetsenbord meldt.
    invoke(LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    expect(find.text('110%'), findsOneWidget);

    invoke(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(find.text('110%'), findsNothing);
  });

  testWidgets('op volledige breedte tekent de editor geen pagina-einden', (
    tester,
  ) async {
    // Buiten paginabreedte breekt het vel ergens anders dan de lijn aanwijst;
    // hem dan tonen zou een onwaarheid tekenen. De knop zegt dat ook.
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    expect(find.byTooltip('Pagina-einden verbergen'), findsOneWidget);

    await tester.tap(find.byTooltip('Schrijfbreedte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volledige breedte'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Pagina-einden gelden alleen op paginabreedte.'),
      findsOneWidget,
    );
    final editor = tester.widget<MarkdownNotesEditor>(
      find.byType(MarkdownNotesEditor),
    );
    expect(
      editor.documentMaxWidth,
      isNull,
      reason: 'volledige breedte betekent geen kolomgrens',
    );
  });

  testWidgets('Bron toont rauwe bron én live weergave', (tester) async {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Kop\n\nTekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();
    await openSource(tester);

    expect(find.widgetWithText(TextField, '# Kop\n\nTekst.'), findsOneWidget);
    final view = tester.widget<DocumentMarkdownView>(
      find.byType(DocumentMarkdownView),
    );
    expect(view.markdown, '# Kop\n\nTekst.');
  });

  testWidgets(
    'Vigilis kleurt document en live preview maar niet de Markdownbron',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(
          MarkdownDocument.parse(
            '---\ntheme: Vigilis\n---\n\n# Rapport\n\n## Bevindingen\n\nTekst.',
          ),
        );
      await tester.pumpWidget(harness(n));
      await tester.pumpAndSettle();

      final visual = tester.widget<MarkdownNotesEditor>(
        find.byType(MarkdownNotesEditor),
      );
      expect(visual.editorTheme.surface, const Color(0xFFFFFFFF));
      expect(visual.editorTheme.text, const Color(0xFF111318));
      expect(visual.editorTheme.accent, const Color(0xFFFFB800));
      expect(find.byType(ThemeProfileLogo), findsOneWidget);
      expect(find.byKey(const Key('document-header-text')), findsOneWidget);
      expect(find.text('Bestuurlijk rapport'), findsOneWidget);
      expect(find.byKey(const Key('document-footer-text')), findsOneWidget);
      expect(find.byKey(const Key('document-page-number')), findsOneWidget);

      await openSource(tester);
      final preview = tester.widget<DocumentMarkdownView>(
        find.byType(DocumentMarkdownView),
      );
      expect(preview.themeProfile?.name, 'Vigilis');
      expect(preview.chartTheme?.name, 'Vigilis');
      expect(find.byType(ThemeProfileLogo), findsOneWidget);
      expect(find.byKey(const Key('document-header-text')), findsOneWidget);
      expect(find.byKey(const Key('document-footer-text')), findsOneWidget);

      final source = tester.widget<TextField>(find.byType(TextField));
      expect(source.style?.fontFamily, 'monospace');
      expect(n.currentState.document!.body, contains('## Bevindingen'));
    },
  );

  testWidgets('typen in bron stroomt live naar de notifier', (tester) async {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'Hallo wereld');
    await tester.pump();

    expect(n.currentState.document!.source, 'Hallo wereld');
    expect(n.currentState.isDirty, isTrue);
  });

  testWidgets('ongedaan maken werkt de editortekst bij', (tester) async {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();
    n.undo();
    await tester.pump();

    expect(find.widgetWithText(TextField, 'a'), findsOneWidget);
  });

  testWidgets('de Overzicht-rail toont de koppen zonder crash', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Een\n\n## Twee\n\ntekst\n\n# Drie\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    expect(find.text('Een'), findsWidgets);
    expect(find.text('Twee'), findsWidgets);
    expect(find.text('Drie'), findsWidgets);

    await tester.tap(find.text('Twee').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cmd+S slaat op naar het pad en maakt het document schoon', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('doc_save');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync('oud\n');

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('oud\n'), filePath: path);
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'nieuw\n');
    await tester.pump();
    expect(n.currentState.isDirty, isTrue);

    const saveActivator = SingleActivator(LogicalKeyboardKey.keyS, meta: true);
    final shortcuts = tester
        .widgetList<CallbackShortcuts>(find.byType(CallbackShortcuts))
        .firstWhere((w) => w.bindings.containsKey(saveActivator));
    await tester.runAsync(() async {
      shortcuts.bindings[saveActivator]!();
      // isDirty clear't pas ná de awaited atomic write (document_editor_screen
      // roept markSaved aan ná `await saveDocument`), dus dit is het juiste
      // wachtsignaal. Het budget moet wel ruim: op de Forgejo linux-gate draaien
      // vier job-containers parallel op één dind, en onder die I/O-contentie
      // haalde de write de oude 500ms niet → de lus las nog 'oud'. 5s vangt de
      // last-piek af zonder een echte hang te verbergen (bounded).
      for (var i = 0; i < 500 && n.currentState.isDirty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(File(path).readAsStringSync(), 'nieuw\n');
    expect(n.currentState.isDirty, isFalse);
  });

  testWidgets('het invoeg-palet schrijft een mermaid-blok in de bron', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Tekst.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mermaid'));
    await tester.pump();

    final source = n.currentState.document!.source;
    expect(source, contains('```mermaid'));
    expect(source, startsWith('Tekst.'));
  });

  testWidgets('het invoeg-palet schrijft een pagina-einde (---) in de bron', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('Voor.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pagina-einde'));
    await tester.pump();

    final source = n.currentState.document!.source;
    // Een `---` op een eigen regel, met een witregel ervóór zodat het een
    // thematische breuk is (geen setext-kop) — draagbaar en geen frontmatter.
    // Aan het eind van het document sluit er geen regel meer op: de visuele
    // stand (de standaard) schrijft de bron via de rijke-tekstbrug terug, en
    // die laat geen sluitende witruimte achter.
    expect(source, startsWith('Voor.'));
    expect(source, contains('\n\n---'));
    expect(source, isNot(contains('- - -')));
    expect(n.currentState.document!.styleName, isNull);
  });

  testWidgets('het invoeg-palet schrijft een voetnoot in de bron', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Tekst.'));
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voetnoot'));
    await tester.pumpAndSettle();

    // Het merkteken op de cursor, de lege notenregel eronder om te vullen.
    expect(n.currentState.document!.body, contains('[^1]'));
    expect(n.currentState.document!.body, contains('[^1]: '));
  });

  testWidgets('een tweede voetnoot krijgt het volgende vrije label', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Tekst [^1].\n\n[^1]: Eerste.\n'));
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voetnoot'));
    await tester.pumpAndSettle();

    expect(n.currentState.document!.body, contains('[^2]: '));
  });

  testWidgets('Visueel: een voetnoot gooit je niet terug in de brontekst', (
    tester,
  ) async {
    // Precies de functie waarvoor de visuele stand het hardst nodig is: je
    // schrijft een noot terwijl je in de tekst zit.
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('Een zin [^1].\n\n[^1]: De noot.\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.textContaining('Bronmodus beschermt opmaak'), findsNothing);
  });

  testWidgets('het invoeg-palet biedt elk item precies één keer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Pagina-einde stond er twee keer in — geen zichtbare fout in een test die
    // op tekst zoekt, maar wél een dubbel item in het menu en een `tap()` die
    // niet meer weet welke hij moet hebben.
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('Voor.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    for (final label in [
      'Grafiek',
      'Tabel',
      'Tijdlijn',
      'Mermaid',
      'Afbeelding',
      'Pagina-einde',
      'Inhoudsopgave',
      'Plakken',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label in het palet');
    }
  });

  testWidgets('Invoegen → Tijdlijn opent eerst de gewone tabeleditor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('Voor.'));
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tijdlijn'));
    await tester.pumpAndSettle();

    expect(find.text('Tabel'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Tijd'), findsOneWidget);
    expect(n.currentState.document!.source, 'Voor.');

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();
    expect(
      n.currentState.document!.source,
      contains('<!-- timeline -->\n| Tijd | Gebeurtenis | Status |'),
    );
  });

  testWidgets('het invoeg-palet schrijft een inhoudsopgave-marker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('Voor.'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inhoudsopgave'));
    await tester.pump();

    // Alleen de marker: de lijst zelf wordt bij export gegenereerd, zodat een
    // hernoemde kop geen verouderde inhoudsopgave in het bestand achterlaat.
    final source = n.currentState.document!.source;
    expect(source, contains('<!-- toc -->'));
    expect(source, isNot(contains('- [')));
  });

  testWidgets('Visueel: invoegen landt op de cursor, niet onderaan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse(
          '# Kop een\n\nEerste alinea.\n\nTweede alinea.\n',
        ),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    // Cursor in de eerste alinea zetten, zoals een gebruiker doet.
    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller
        .updateSelection(
          const TextSelection.collapsed(offset: 12),
          ChangeSource.local,
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inhoudsopgave'));
    await tester.pumpAndSettle();

    // De regressie: de bron-cursor staat in Visueel stil, dus elke invoeging
    // belandde onderaan het document — wat leest als "er gebeurt niets".
    final source = n.currentState.document!.source;
    expect(
      source,
      contains('Eerste alinea.\n\n<!-- toc -->\n\nTweede alinea.'),
      reason: 'het blok hoort onder de regel van de cursor te landen',
    );
    // En één keer, zonder een gat van witregels eromheen.
    expect(RegExp('<!-- toc -->').allMatches(source).length, 1);
    expect(source, isNot(contains('\n\n\n')));
  });

  testWidgets('Visueel: een pagina-einde wordt een lijn, geen foutblok', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('Voor.\n\n---\n\nNa.\n'));
    await tester.pumpWidget(harness(n));
    await tester.pumpAndSettle();

    // Zonder builder voor de `divider`-embed tekent Quill een RenderErrorBox
    // over het hele schrijfoppervlak.
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.byType(Divider), findsWidgets);
    // En de scheiding blijft `---`: de brug schrijft hem niet als `- - -` terug.
    expect(n.currentState.document!.source, contains('---'));
    expect(n.currentState.document!.source, isNot(contains('- - -')));
  });

  testWidgets('Visueel: een tabel invoegen landt ook op de cursor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('Eerste alinea.\n\nTweede alinea.\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller
        .updateSelection(
          const TextSelection.collapsed(offset: 3),
          ChangeSource.local,
        );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tabel'));
    await tester.pumpAndSettle();

    // Niet alleen de inhoudsopgave: élke invoeging liep via de bron-cursor.
    final body = n.currentState.document!.body;
    expect(body.indexOf('|'), lessThan(body.indexOf('Tweede alinea.')));
  });

  testWidgets(
    'Invoegen → Afbeelding opent de carrousel, niet alleen Bladeren',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse('Tekst.'));
      await tester.pumpWidget(harness(n));
      await tester.pump();

      await tester.tap(find.text('Invoegen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Afbeelding'));
      await tester.pump();
      // De scan/I/O van de carrousel; font-overflow in tests is cosmetisch.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      while (tester.takeException() != null) {}

      expect(find.byType(ImageCarouselPicker), findsOneWidget);
      expect(find.text('Afbeelding kiezen'), findsOneWidget);
    },
  );

  testWidgets(
    'opmaakknop Afbeelding opent de carrousel, dumpt geen placeholder',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final n = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse('video en meer tekst'));
      await tester.pumpWidget(harness(n));
      await openSource(tester);

      await tester.tap(find.byTooltip('Afbeelding'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      while (tester.takeException() != null) {}

      expect(find.byType(ImageCarouselPicker), findsOneWidget);
      expect(n.currentState.document!.source, 'video en meer tekst');
      expect(n.currentState.document!.source, isNot(contains('pad-of-url')));
    },
  );

  testWidgets('Overzicht: klik springt in Visueel; inklappen werkt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Een\n\ntekst\n\n# Twee\n\nmeer\n'),
      );
    await tester.pumpWidget(harness(n));
    await tester.pump();

    expect(find.text('OVERZICHT'), findsOneWidget);
    final outlineTwee = find.descendant(
      of: find.byKey(const Key('document-outline-rail')),
      matching: find.text('Twee'),
    );
    await tester.tap(outlineTwee);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Overzicht inklappen'));
    await tester.pump();
    expect(find.text('OVERZICHT'), findsNothing);
    expect(find.byTooltip('Overzicht uitklappen'), findsOneWidget);
  });

  testWidgets('undo/redo-knoppen volgen canUndo/canRedo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    await tester.pumpWidget(harness(n));
    await openSource(tester);
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump();

    expect(n.currentState.canUndo, isTrue);
    await tester.tap(find.byTooltip('Ongedaan maken'));
    await tester.pump();
    expect(n.currentState.document!.source, 'a');
    expect(n.currentState.canRedo, isTrue);

    await tester.tap(find.byTooltip('Opnieuw'));
    await tester.pump();
    expect(n.currentState.document!.source, 'ab');
  });

  testWidgets('⋮-menu in documentmodus biedt Instellingen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('x'));
    await tester.pumpWidget(harness(n));
    await tester.pump();

    await tester.tap(find.byTooltip('Meer'));
    await tester.pumpAndSettle();
    expect(find.text('Instellingen'), findsOneWidget);
  });

  testWidgets(
    'de opmaak-knoppenbalk in bron muteert de bron en stroomt naar de notifier',
    (tester) async {
      final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
      await tester.pumpWidget(harness(n));
      await openSource(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      await tester.tap(find.byTooltip('Vet'));
      await tester.pump();

      expect(n.currentState.document!.source, contains('**'));
      expect(n.currentState.isDirty, isTrue);
    },
  );

  testWidgets(
    'het palet zet hoofdstukafbrekingen in de bron, ongedaan te maken',
    (tester) async {
      final n = DocumentNotifier()
        ..loadDocument(
          MarkdownDocument.parse(
            '---\ntheme: Zakelijk\n---\n\n'
            '# Een\n\nAlfa\n\n# Twee\n\nBeta\n',
          ),
        );
      await tester.pumpWidget(harness(n));
      await openSource(tester);

      await tester.tap(find.text('Invoegen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoofdstukken op nieuwe pagina'));
      await tester.pumpAndSettle();

      final source = n.currentState.document!.source;
      expect(source, contains('Alfa\n\n---\n\n# Twee'));
      // De frontmatter blijft staan: de bewerking raakt alleen de body.
      expect(source, startsWith('---\ntheme: Zakelijk\n---\n'));
      expect(
        find.text('Elk hoofdstuk begint nu op een nieuwe pagina'),
        findsOneWidget,
      );

      // Eén discrete stap in de geschiedenis: ongedaan maken brengt de bron
      // precies terug.
      expect(n.currentState.canUndo, isTrue);
      n.undo();
      expect(n.currentState.document!.source, isNot(contains('Alfa\n\n---')));
    },
  );

  testWidgets('een tweede keer toepassen verandert de bron niet', (
    tester,
  ) async {
    final n = DocumentNotifier()
      ..loadDocument(
        MarkdownDocument.parse('# Een\n\nAlfa\n\n---\n\n# Twee\n'),
      );
    await tester.pumpWidget(harness(n));
    await openSource(tester);

    await tester.tap(find.text('Invoegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoofdstukken op nieuwe pagina'));
    await tester.pumpAndSettle();

    expect(n.currentState.document!.source, '# Een\n\nAlfa\n\n---\n\n# Twee\n');
    // Niets veranderd, dus ook geen bewerking in de geschiedenis — en de
    // melding zegt eerlijk dat het al zo stond.
    expect(n.currentState.isDirty, isFalse);
    expect(
      find.text('Elk hoofdstuk begon al op een nieuwe pagina'),
      findsOneWidget,
    );
  });
}
