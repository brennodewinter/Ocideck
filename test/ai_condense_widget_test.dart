import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/ai_condense_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/dialogs/ai_condense_dialog.dart';
import 'package:ocideck/widgets/editors/ai_condense_button.dart';

DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('nl'),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  group('AiCondenseDialog', () {
    testWidgets('samenvatting genereren en toepassen', (tester) async {
      AiCondenseResult? popped;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                popped = await showAiCondenseDialog(
                  ctx,
                  generate: (mode, style) async => const AiCondenseResult(
                    mode: AiCondenseMode.summary,
                    summary: 'Korte alinea.',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Tekst inkorten met AI'), findsOneWidget);
      await tester.tap(find.text('Genereer'));
      await tester.pumpAndSettle();

      expect(find.text('Korte alinea.'), findsOneWidget);
      await tester.tap(find.text('Toepassen'));
      await tester.pumpAndSettle();

      expect(popped?.mode, AiCondenseMode.summary);
      expect(popped?.summary, 'Korte alinea.');
    });

    testWidgets('kernpunten geeft de gekozen lijststijl mee', (tester) async {
      ListStyle? usedStyle;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showAiCondenseDialog(
                ctx,
                generate: (mode, style) async {
                  usedStyle = style;
                  return const AiCondenseResult(
                    mode: AiCondenseMode.keyPoints,
                    listStyle: ListStyle.numbered,
                    points: ['punt'],
                  );
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kernpunten (max. 8)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nummering'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Genereer'));
      await tester.pumpAndSettle();

      expect(usedStyle, ListStyle.numbered);
      expect(find.text('1. punt'), findsOneWidget);
    });

    testWidgets('een leeg modelantwoord toont een melding en past niets toe', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  showAiCondenseDialog(ctx, generate: (_, _) async => null),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Genereer'));
      await tester.pumpAndSettle();

      expect(find.text('Het model gaf geen tekst terug.'), findsOneWidget);
      expect(find.text('Toepassen'), findsNothing);
    });
  });

  group('AiCondenseButton', () {
    Slide richTextSlide([String body = 'Lange lopende tekst.']) => Slide(
      id: 's1',
      type: SlideType.bulletsImage,
      title: 'Titel',
      listStyle: ListStyle.richText,
      customMarkdown: body,
    );

    void configureAi() => SharedPreferences.setMockInitialValues({
      'aiSettings': jsonEncode(
        const AiSettings(
          enabled: true,
          mode: AiBackendMode.local,
          baseUrl: 'http://127.0.0.1:11434/v1',
          model: 'gemma3:4b',
        ).toJson(),
      ),
    });

    testWidgets('verstopt zich als AI uit staat', (tester) async {
      await tester.pumpWidget(_host(AiCondenseButton(slide: richTextSlide())));
      await tester.pumpAndSettle();

      expect(find.text('Vat samen met AI…'), findsNothing);
    });

    testWidgets('verstopt zich bij een leeg tekstveld', (tester) async {
      configureAi();
      await tester.pumpWidget(
        _host(AiCondenseButton(slide: richTextSlide(' '))),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Vat samen met AI…'), findsNothing);
    });

    testWidgets('opent de keuzedialoog als AI geconfigureerd is', (
      tester,
    ) async {
      configureAi();
      await tester.pumpWidget(_host(AiCondenseButton(slide: richTextSlide())));
      // Laat settingsProvider de AI-config uit de mock store laden.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Vat samen met AI…'), findsOneWidget);

      await tester.tap(find.text('Vat samen met AI…'));
      await tester.pumpAndSettle();

      expect(find.text('Tekst inkorten met AI'), findsOneWidget);
      expect(find.text('Genereer'), findsOneWidget);
    });
  });

  group('undo', () {
    test('verdichten is één ongedaan-stap die alles terugzet', () {
      final n = _notifier()
        ..newDeck(
          'D',
          slides: [
            Slide.create(SlideType.bulletsImage).copyWith(
              title: 'Zet de inhoud centraal',
              listStyle: ListStyle.richText,
              customMarkdown: 'De volledige lange tekst.',
              imagePath: 'images/foto.png',
            ),
          ],
        );

      n.updateSlide(
        0,
        applyCondenseToSlide(
          n.state.deck!.slides.single,
          const AiCondenseResult(
            mode: AiCondenseMode.keyPoints,
            listStyle: ListStyle.bullets,
            points: ['kernachtig'],
          ),
          notesHeading: 'Oorspronkelijke tekst',
        ),
        bumpRevision: true,
      );

      var slide = n.state.deck!.slides.single;
      expect(slide.listStyle, ListStyle.bullets);
      expect(slide.bullets, ['kernachtig']);
      expect(slide.notes, contains('De volledige lange tekst.'));

      n.undo();
      slide = n.state.deck!.slides.single;
      expect(slide.listStyle, ListStyle.richText);
      expect(slide.customMarkdown, 'De volledige lange tekst.');
      expect(slide.notes, isEmpty);
      expect(n.state.canUndo, isFalse);
    });
  });
}
