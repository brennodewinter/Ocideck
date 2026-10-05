import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/widgets/slides/previews/retrying_image.dart';
import 'package:ocideck/widgets/slides/previews/slide_preview_support.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// #2282 — een deck dat op web via `?deck=` of URL-import is geopend heeft geen
/// projectPath, en relatieve mediapaden (`images/foto.png`) verdwenen op een
/// grijze placeholder. De deck-URL zelf is dan de resolutiebasis; deze tests
/// leggen vast dat die via [DeckAssetScope] bij de renderers aankomt én dat de
/// grenzen (same-origin, deckmap, geen scheme-verwijzingen) daar gelden.

const _deckUrl = 'https://deck.example/decks/presentatie.md';

Widget _preview(String imagePath, {String? deckUrl, String? projectPath}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: DeckAssetScope(
            deckUrl: deckUrl,
            child: SlidePreviewWidget(
              slide: Slide(
                id: 'x',
                type: SlideType.image,
                title: 'Beeld',
                imagePath: imagePath,
              ),
              projectPath: projectPath,
            ),
          ),
        ),
      ),
    ),
  );
}

/// De provider waarmee de slide-iafbeelding is opgebouwd — `null` als er geen
/// [RetryingImage] in de boom staat (de placeholder wint dan).
Object? _imageCacheKey(WidgetTester tester) {
  final finder = find.byType(RetryingImage);
  if (finder.evaluate().isEmpty) return null;
  final provider = tester.widget<RetryingImage>(finder.first).image;
  return provider is CappedImage ? provider.cacheKey : provider;
}

void main() {
  testWidgets(
    'een relatief pad in een URL-geopend deck resolveert tegen de deckmap',
    (tester) async {
      await tester.pumpWidget(_preview('images/foto.png', deckUrl: _deckUrl));
      await tester.pump();
      expect(
        _imageCacheKey(tester),
        'https://deck.example/decks/images/foto.png',
        reason: 'zonder resolutiebasis verdwijnt dit op de missing-placeholder',
      );
    },
  );

  testWidgets('zonder deck-URL blijft een relatief pad de placeholder tonen', (
    tester,
  ) async {
    await tester.pumpWidget(_preview('images/foto.png'));
    await tester.pump();
    expect(_imageCacheKey(tester), isNull);
  });

  testWidgets('een verwijzing die buiten de deckmap ontsnapt krijgt geen URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      _preview('../../../etc/passwd.png', deckUrl: _deckUrl),
    );
    await tester.pump();
    expect(_imageCacheKey(tester), isNull);
  });

  testWidgets('een absolute remote URL blijft achter de remote-media-gate', (
    tester,
  ) async {
    // `allowRemoteMedia` staat standaard uit: een volledige URL in het deck
    // mag niet stil via de deck-basis doorgeladen worden — die tak hoort bij
    // de bestaande poort, niet bij deze fix.
    await tester.pumpWidget(
      _preview('https://elders.example/track.png', deckUrl: _deckUrl),
    );
    await tester.pump();
    expect(_imageCacheKey(tester), isNull);
  });

  testWidgets('een ongeldige deck-URL levert geen resolutie', (tester) async {
    await tester.pumpWidget(
      _preview('images/foto.png', deckUrl: 'git: repo @ main'),
    );
    await tester.pump();
    expect(_imageCacheKey(tester), isNull);
  });
}
