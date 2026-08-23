import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';

// De 'Bron'-schakelaar in de editor-kopregel (#1160) is het per-dia
// ontsnappingsluik: één klik brengt je van de gestructureerde editor naar de
// rauwe markdown van díe ene dia. Mechanisch leunt hij op de bestaande
// markdown-modus, dus deze test bewaakt alleen de bedrading van het instappunt:
// dat de knop er is en dat hij de markdown-modus op slide-omvang zet.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    SlideType initialType = SlideType.bullets,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    if (initialType != SlideType.title) {
      notifier.updateSlide(0, Slide.create(initialType));
    }

    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  final sourceButton = find.byTooltip('Bewerk deze dia als markdown-bron');

  testWidgets('the source toggle sits in the structured editor header', (
    tester,
  ) async {
    await pump(tester);
    expect(sourceButton, findsOneWidget);
    expect(find.text('Bron'), findsOneWidget);
  });

  testWidgets('tapping it enters markdown mode scoped to the active slide', (
    tester,
  ) async {
    final container = await pump(tester);

    // Vooraf: visuele modus, deck-omvang (de standaard).
    expect(container.read(editorProvider).mode, EditorMode.visual);

    await tester.tap(sourceButton);
    await tester.pumpAndSettle();

    final editor = container.read(editorProvider);
    expect(editor.mode, EditorMode.markdown);
    expect(editor.markdownScope, MarkdownScope.slide);
    // Het instappunt vult de buffer met de markdown van déze dia, niet het
    // hele deck: geen front-matter-scheidingsregel bovenaan.
    expect(editor.markdownBuffer, isNot(startsWith('---')));
    // En de buffer opent schoon (buffer == baseline), zodat een schone editor
    // deck-wijzigingen als undo/redo blijft volgen.
    expect(editor.hasMarkdownDraft, isFalse);
  });
}
