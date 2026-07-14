import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';

/// Een ingeklapte [ExpansionTile] bouwt zijn children niet, dus de aanwezigheid
/// van de notitie-editor ís de uitgeklapte staat.
Finder _speakerEditor(String slideId) =>
    find.byKey(ValueKey('speaker-notes-$slideId-p0'));

Finder _userEditor(String slideId) =>
    find.byKey(ValueKey('user-notes-$slideId-p0'));

Future<void> _pumpEditor(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EditorPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('lege notities beginnen ingeklapt', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container.read(deckProvider).deck!.slides.single;

    await _pumpEditor(tester, container);

    // De koppen staan er wel — alleen de editors eronder niet.
    expect(find.text('Sprekersnotities'), findsOneWidget);
    expect(find.text('Gebruikersnotities'), findsOneWidget);
    expect(_speakerEditor(slide.id), findsNothing);
    expect(_userEditor(slide.id), findsNothing);
  });

  testWidgets('notities met tekst beginnen uitgeklapt', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: 'Spreker tekst');
    deckNotifier.updateSlide(0, slide);
    deckNotifier.setUserNoteForSlide(slide.id, 'Cursusnotitie');

    await _pumpEditor(tester, container);

    expect(_speakerEditor(slide.id), findsOneWidget);
    expect(_userEditor(slide.id), findsOneWidget);
  });

  testWidgets('alleen het gevulde veld klapt uit', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: 'Alleen de spreker');
    deckNotifier.updateSlide(0, slide);

    await _pumpEditor(tester, container);

    expect(_speakerEditor(slide.id), findsOneWidget);
    expect(_userEditor(slide.id), findsNothing);
  });

  testWidgets('witruimte telt niet als tekst', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: '   \n\n  ');
    deckNotifier.updateSlide(0, slide);

    await _pumpEditor(tester, container);

    expect(_speakerEditor(slide.id), findsNothing);
  });

  testWidgets('de stand wordt per slide opnieuw bepaald', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final withNotes = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: 'Spreker tekst');
    deckNotifier.updateSlide(0, withNotes);
    deckNotifier.addSlide(SlideType.bullets);
    final empty = container.read(deckProvider).deck!.slides[1];

    await _pumpEditor(tester, container);
    expect(_speakerEditor(withNotes.id), findsOneWidget);

    // De tweede slide heeft geen notities: de tegel hoort dicht te gaan, ook al
    // stond hij open voor de vorige slide. Dat is precies wat de sleutel op de
    // ExpansionTile afdwingt.
    container.read(editorProvider.notifier).select(1);
    await tester.pumpAndSettle();
    expect(_speakerEditor(empty.id), findsNothing);

    // En terug: de gevulde slide staat weer open.
    container.read(editorProvider.notifier).select(0);
    await tester.pumpAndSettle();
    expect(_speakerEditor(withNotes.id), findsOneWidget);
  });
}
