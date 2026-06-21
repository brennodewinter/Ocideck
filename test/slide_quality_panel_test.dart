import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/panels/slide_quality_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

DeckNotifier _deckNotifier(Deck deck) {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  final notifier = DeckNotifier(md, file);
  notifier.loadDeck(deck);
  return notifier;
}

Widget _host(Deck deck) {
  AppLocalizations.setActiveLanguageCode('nl');
  return ProviderScope(
    overrides: [deckProvider.overrideWith((ref) => _deckNotifier(deck))],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(body: SlideQualityPanel()),
    ),
  );
}

void main() {
  Deck overfullDeck() => Deck(
    title: 'Demo',
    slides: [
      Slide.create(SlideType.bulletsImage).copyWith(
        title: 'blah blah blah',
        imagePath: 'images/pasted.png',
        bullets: List.generate(
          13,
          (i) =>
              'Controleer op een SPECI: Kijk of er tussentijds een speciaal '
              'weerrapport is uitgegeven vanwege plotseling veranderde '
              'omstandigheden ${i + 1}.',
        ),
      ),
    ],
  );

  testWidgets('shows quality issues for an overfull split bullet slide', (
    tester,
  ) async {
    await tester.pumpWidget(_host(overfullDeck()));
    await tester.pump();

    expect(
      find.textContaining('Geen kwaliteitsproblemen gevonden'),
      findsNothing,
    );
    expect(find.textContaining('Slidekwaliteit'), findsOneWidget);
    expect(find.textContaining('fout(en)'), findsOneWidget);
    expect(find.textContaining('waarschuwing(en)'), findsOneWidget);
  });

  testWidgets('app shell tab scope shows quality issues for overfull deck', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    AppLocalizations.setActiveLanguageCode('nl');

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container.read(tabsProvider).current!.deckNotifier.loadDeck(overfullDeck());
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Geen kwaliteitsproblemen gevonden'),
      findsNothing,
    );
    expect(find.textContaining('fout(en)'), findsOneWidget);
    expect(find.textContaining('waarschuwing(en)'), findsOneWidget);
  });
}
