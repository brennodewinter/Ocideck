import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/gallery_layout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/editors/image_gallery_editor.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
  FlutterQuillLocalizations.delegate,
];

Widget _host(Widget child, {ImageService? imageService}) => ProviderScope(
  overrides: [
    if (imageService != null)
      imageServiceProvider.overrideWithValue(imageService),
  ],
  child: MaterialApp(
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1400, height: 2000, child: child)),
  ),
);

/// Geeft een bekend pad terug uit de afbeeldingenkiezer zonder een echt
/// bestand of venster aan te raken.
class _FakeImageService extends ImageService {
  final String? pickedPath;
  _FakeImageService({this.pickedPath});

  @override
  Future<ImageImportOutcome> pickImageDetailed({String? projectPath}) async =>
      pickedPath == null
      ? const ImageImportOutcome.failed(ImageImportFailure.cancelled)
      : ImageImportOutcome.success(pickedPath!);
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Slide gallery({
    List<String> images = const ['![een](a.png)', '![twee](b.png)'],
    GalleryLayout layout = GalleryLayout.grid,
  }) => Slide(
    id: 'g1',
    type: SlideType.imageGallery,
    title: 'Koppen',
    galleryImages: images,
    galleryLayout: layout,
  );

  testWidgets('toont titel, beeldrijen met alt-veld en de toevoegknop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(ImageGalleryEditor(slide: gallery(), onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Koppen'), findsWidgets);
    expect(find.text('Afbeelding toevoegen'), findsOneWidget);
    expect(find.text('Stapel'), findsOneWidget);
    expect(find.text('Raster'), findsOneWidget);
    // Elke rij toont pad + een alt-veld.
    expect(find.textContaining('a.png'), findsOneWidget);
    expect(find.textContaining('b.png'), findsOneWidget);
  });

  testWidgets('een gewijzigde alt-tekst landt in de entry zelf', (
    tester,
  ) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(ImageGalleryEditor(slide: gallery(), onUpdate: (s) => emitted = s)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'nieuwe alt');
    await tester.pump();

    expect(emitted, isNotNull);
    expect(emitted!.galleryImages[0], '![nieuwe alt](a.png)');
  });

  testWidgets('verwijderen haalt de rij weg', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(ImageGalleryEditor(slide: gallery(), onUpdate: (s) => emitted = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Afbeelding verwijderen').first);
    await tester.pump();

    expect(emitted!.galleryImages, ['![twee](b.png)']);
  });

  testWidgets('omlaag verplaatst de rij', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(ImageGalleryEditor(slide: gallery(), onUpdate: (s) => emitted = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Omlaag').first);
    await tester.pump();

    expect(emitted!.galleryImages, ['![twee](b.png)', '![een](a.png)']);
  });

  testWidgets('de lay-outkeuze zet galleryLayout op stapel', (tester) async {
    Slide? emitted;
    await tester.pumpWidget(
      _host(ImageGalleryEditor(slide: gallery(), onUpdate: (s) => emitted = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stapel'));
    await tester.pump();

    expect(emitted!.galleryLayout, GalleryLayout.stack);
  });

  testWidgets('toevoegen voegt een lege-alt entry van de kiezer toe', (
    tester,
  ) async {
    Slide? emitted;
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        ImageGalleryEditor(slide: gallery(), onUpdate: (s) => emitted = s),
        imageService: _FakeImageService(pickedPath: 'images/nieuw.png'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Afbeelding toevoegen'));
    await tester.pumpAndSettle();

    expect(emitted!.galleryImages, [
      '![een](a.png)',
      '![twee](b.png)',
      '![](images/nieuw.png)',
    ]);
  });
}
