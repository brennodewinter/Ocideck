import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/dialogs/tlp_audience_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  Widget host({
    DocumentNotifier? documents,
    DeckNotifier? decks,
    required void Function(BuildContext, WidgetRef) onTap,
  }) {
    return ProviderScope(
      overrides: [
        if (documents != null)
          documentProvider.overrideWith((ref) => documents),
        if (decks != null) deckProvider.overrideWith((ref) => decks),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => onTap(context, ref),
              child: const Text('zet'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> confirmRed(WidgetTester tester, {bool slide = false}) async {
    await tester.tap(find.text('zet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tlp-recipients')), 'Alice');
    await tester.pump();
    if (slide) {
      await tester.tap(find.text('Als dia invoegen'));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('tlp-audience-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('een document krijgt de toelichting één keer onder de titel', (
    tester,
  ) async {
    final docs = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Rapport\n\nTekst.\n'));
    await tester.pumpWidget(
      host(
        documents: docs,
        onTap: (context, ref) => applyDocumentTlp(context, ref, TlpLevel.red),
      ),
    );
    await confirmRed(tester);

    final source = docs.currentState.document!.source;
    expect(source, contains('tlp: red'));
    expect(source, contains('Bestemd voor: Alice'));
    expect('# Rapport\n\nTLP:RED'.allMatches(source), hasLength(1));

    await tester.tap(find.text('zet'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tlp-audience-confirm')), findsNothing);
    expect(docs.currentState.document!.source, source);
  });

  testWidgets('een presentatie kan er een gewone dia bij krijgen', (
    tester,
  ) async {
    final md = MarkdownService();
    final decks = DeckNotifier(
      md,
      FileService(md, ImageService(), () => const ThemeProfile()),
    )..loadDeck(Deck(title: 'Deck', slides: [Slide.create(SlideType.title)]));
    await tester.pumpWidget(
      host(
        decks: decks,
        onTap: (context, ref) =>
            applyPresentationTlp(context, ref, TlpLevel.red),
      ),
    );
    await confirmRed(tester, slide: true);

    final deck = decks.currentState.deck!;
    expect(deck.tlp, TlpLevel.red);
    expect(deck.slides, hasLength(2));
    expect(deck.slides.first.type, SlideType.bullets);
    expect(deck.slides.first.title, 'TLP:RED');
    expect(deck.slides.first.bullets, contains('Bestemd voor: Alice'));
  });
}
