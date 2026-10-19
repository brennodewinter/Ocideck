import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show ChangeSource, FlutterQuillLocalizations, QuillEditor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De Overzicht-markering volgt één caret, niet twee (#2141).
///
/// De broncontroller-listener berekende de actieve kop óók in de visuele
/// stand — uit `_controller.selection`, die daar juist náár de Quill-caret
/// wordt gezet. Elke schrijfactie in Quill liet de markering daardoor tussen
/// twee berekeningen flippen. In Visueel is de Quill-caret leidend; de
/// bronselectie doet er pas weer toe in de platte-bron-fallback.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  /// De titel die de rail als actief tekent (de EU-blauwe).
  String activeOutlineTitle(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('document-outline-rail')),
          matching: find.byType(Text),
        ),
      )
      .firstWhere((t) => t.style?.color == AppTheme.blueVivid)
      .data!;

  testWidgets('visuele caret wint van een schuivende bronselectie (#2141)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const doc = '# Een\n\nEerste tekst.\n\n# Twee\n\nTweede tekst.\n';
    final notifier = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse(doc));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentProvider.overrideWith((_) => notifier)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DocumentEditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(QuillEditor), findsOneWidget);

    // Zet de Quill-caret onder de tweede kop — de rail markeert "Twee".
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    tester
        .widget<WysiwygNotesField>(find.byType(WysiwygNotesField))
        .controller
        .updateSelection(
          const TextSelection.collapsed(offset: 30),
          ChangeSource.local,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(activeOutlineTitle(tester), 'Twee');

    // Nu schuift de bronselectie alsof een schrijfactie hem verplaatste —
    // in Visueel is die niet leidend, de markering mag niet mee flippen.
    tester
        .widget<MarkdownNotesEditor>(find.byType(MarkdownNotesEditor))
        .controller
        .selection = const TextSelection.collapsed(
      offset: 0,
    );
    // De post-frame die de markering bijwerkt draait pas zodra er een frame
    // gepland staat — in de app is dat na elke bewerking zo, in de test moet
    // dat expliciet.
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(
      activeOutlineTitle(tester),
      'Twee',
      reason:
          'de bronselectie staat op offset 0 (onder "Een") maar is in '
          'Visueel niet leidend',
    );
  });

  /// Overzicht-klikken en interne koplinks delen één coördinatenstelsel: de
  /// bódy die de controller bewerkt (#2465). Het overzicht en de linkroute
  /// bouwden hun koppen op de *source* — mét stijl-frontmatter — terwijl de
  /// caret body-offsets verwacht. Bij een document met `theme:` landde een
  /// interne koplink de lengte van het frontmatter-blok te ver.
  testWidgets('overzicht en koplinks volgen de body, niet de source (#2465)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const doc =
        '---\ntheme: Zakelijk\n---\n\n'
        '# Alfa\n\n'
        'Eerste tekst met [naar gamma](#gamma).\n\n'
        '# Beta\n\n'
        'Tweede tekst.\n\n'
        '# Gamma\n\n'
        'Derde tekst.\n';
    final parsed = MarkdownDocument.parse(doc);
    final body = parsed.body;
    final notifier = DocumentNotifier()..loadDocument(parsed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentProvider.overrideWith((_) => notifier)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DocumentEditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    int caret() {
      // Visueel: de Quill-caret gespiegeld op de broncontroller van de
      // notes-editor. Bron: de caret van het bronveld zelf.
      final notes = find.byType(MarkdownNotesEditor);
      if (notes.evaluate().isNotEmpty) {
        return tester
            .widget<MarkdownNotesEditor>(notes)
            .controller
            .selection
            .baseOffset;
      }
      return tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .selection
          .baseOffset;
    }

    Future<void> tapRailHeading(String title) async {
      final entry = find.descendant(
        of: find.byKey(const Key('document-outline-rail')),
        matching: find.text(title),
      );
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // De markering loopt via een post-frame callback vanuit de
      // caret-debounce — die staat pas na het volgende frame in de rail.
      await tester.pump();
    }

    // Visueel: rail-klik zet de caret op de kopregel. De gespiegelde
    // bronselectie landt dan ná de `# `-markering — in de koptekst zelf.
    expect(find.byType(QuillEditor), findsOneWidget);
    await tapRailHeading('Beta');
    expect(
      caret(),
      inInclusiveRange(body.indexOf('# Beta'), body.indexOf('# Beta') + 6),
    );

    // Bron: rail-klik en interne koplink landen allebei exact op de kop.
    await tester.tap(find.text('Bron'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapRailHeading('Gamma');
    expect(caret(), body.indexOf('# Gamma'));
    expect(activeOutlineTitle(tester), 'Gamma');

    await tester.tapOnText(find.textRange.ofSubstring('naar gamma'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(caret(), body.indexOf('# Gamma'));

    await tapRailHeading('Alfa');
    expect(caret(), body.indexOf('# Alfa'));
  });
}
