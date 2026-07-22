import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/audio_attachment_editor.dart';

/// Een kiezer die niet naar het systeemvenster gaat maar teruggeeft wat de test
/// hem meegeeft — de enige stap in dit blokje die onder `flutter test` niet
/// bestaat.
class _FakeImageService extends ImageService {
  _FakeImageService(this.result);

  final String? result;
  final gevraagd = <String?>[];

  @override
  Future<String?> pickAudio({String? projectPath}) async {
    gevraagd.add(projectPath);
    return result;
  }
}

/// Audio bij een dia: kiezen, wissen en automatisch afspelen.
///
/// De regel die hier telt is de koppeling tussen die twee: automatisch
/// afspelen zonder bestand is geen instelling maar een belofte die niemand kan
/// waarmaken, en die moet bij het wissen van het bestand meevallen — anders
/// staat er in het opgeslagen deck `audioAutoplay: true` op een dia die geen
/// geluid heeft.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Slide videoSlide({String audio = '', bool autoplay = false}) =>
      Slide.create(SlideType.video).copyWith(
        audioPath: audio,
        audioAutoplay: autoplay,
      );

  /// Pompt de editor en verzamelt elke dia die hij teruggeeft.
  Future<List<Slide>> pump(
    WidgetTester tester,
    Slide slide,
    ImageService service, {
    String? projectPath,
  }) async {
    final updates = <Slide>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioAttachmentEditor(
            slide: slide,
            imageService: service,
            projectPath: projectPath,
            onUpdate: updates.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return updates;
  }

  testWidgets('zonder bestand staat er dat er niets gekozen is', (
    tester,
  ) async {
    await pump(tester, videoSlide(), _FakeImageService(null));

    expect(find.text('Geen audiobestand gekozen'), findsOneWidget);
    // Geen wisknop: er valt niets te wissen.
    expect(find.byIcon(Icons.clear), findsNothing);
    // En automatisch afspelen staat uit — er is niets om af te spelen.
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
      reason: 'automatisch afspelen zonder bestand is een lege belofte',
    );
  });

  testWidgets('een gekozen bestand komt in de dia terecht', (tester) async {
    final service = _FakeImageService('media/uitleg.mp3');
    final updates = await pump(
      tester,
      videoSlide(),
      service,
      projectPath: '/projecten/rapport',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Kiezen'));
    await tester.pumpAndSettle();

    expect(updates.single.audioPath, 'media/uitleg.mp3');
    expect(
      service.gevraagd,
      ['/projecten/rapport'],
      reason: 'de kiezer moet in de projectmap importeren, niet ernaast',
    );
  });

  testWidgets('afbreken in het kiesvenster verandert de dia niet', (
    tester,
  ) async {
    final updates = await pump(tester, videoSlide(), _FakeImageService(null));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Kiezen'));
    await tester.pumpAndSettle();

    expect(updates, isEmpty);
  });

  testWidgets('met een bestand staat het pad er en mag automatisch afspelen', (
    tester,
  ) async {
    final updates = await pump(
      tester,
      videoSlide(audio: 'media/uitleg.mp3'),
      _FakeImageService(null),
    );

    expect(find.text('media/uitleg.mp3'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(updates.single.audioAutoplay, isTrue);
  });

  testWidgets('het bestand wissen zet automatisch afspelen mee uit', (
    tester,
  ) async {
    final updates = await pump(
      tester,
      videoSlide(audio: 'media/uitleg.mp3', autoplay: true),
      _FakeImageService(null),
    );

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(updates.single.audioPath, isEmpty);
    expect(
      updates.single.audioAutoplay,
      isFalse,
      reason: 'anders blijft "automatisch afspelen" staan op een stille dia',
    );
  });
}
