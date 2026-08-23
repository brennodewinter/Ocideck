import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/editors/finding_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The finding editor surfaces its group's evidence (screenshots / videos) and
/// gates the "add" actions on a finding id (evidence links to the finding by id).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<(ProviderContainer, Slide)> pump(
    WidgetTester tester, {
    required String findingId,
    List<Slide> evidence = const [],
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    final finding = Slide.create(
      SlideType.finding,
    ).copyWith(findingId: findingId, customMarkdown: '# Bevinding');
    notifier.updateSlide(0, finding);
    if (evidence.isNotEmpty) notifier.insertSlides(evidence, afterIndex: 0);

    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FindingEditor(
              slide: finding,
              onUpdate: (_) {},
              imageService: ImageService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, finding);
  }

  testWidgets('lists the finding\'s evidence slides', (tester) async {
    await pump(
      tester,
      findingId: 'F-03',
      evidence: [
        Slide.create(SlideType.image).copyWith(
          imagePath: 'bewijs/screenshot.png',
          findingId: 'F-03',
          findingRole: FindingRole.evidence,
        ),
      ],
    );
    expect(find.text('Bewijs'), findsOneWidget);
    expect(find.text('screenshot.png'), findsOneWidget);
    // The add actions are enabled because the finding has an id.
    expect(find.text('Screenshot toevoegen'), findsOneWidget);
    expect(find.text('Video toevoegen'), findsOneWidget);
  });

  testWidgets('evidence can be added even without a finding id', (
    tester,
  ) async {
    await pump(tester, findingId: '');
    // The buttons are enabled; a missing id is generated on the first evidence.
    expect(find.textContaining('automatisch'), findsOneWidget);
    final addButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Screenshot toevoegen'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(addButton.onPressed, isNotNull);
  });

  testWidgets('removing evidence drops the slide from the deck', (
    tester,
  ) async {
    final (container, _) = await pump(
      tester,
      findingId: 'F-03',
      evidence: [
        Slide.create(SlideType.image).copyWith(
          imagePath: 'shot.png',
          findingId: 'F-03',
          findingRole: FindingRole.evidence,
        ),
      ],
    );
    expect(container.read(deckProvider).deck!.slides, hasLength(2));
    await tester.tap(find.byTooltip('Bewijs verwijderen'));
    await tester.pumpAndSettle();
    expect(container.read(deckProvider).deck!.slides, hasLength(1));
  });
}
