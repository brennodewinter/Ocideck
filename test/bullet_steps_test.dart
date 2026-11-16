import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/presentation_step_plan.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/widgets/editors/bullets_editor.dart';
import 'package:ocideck/widgets/editors/bullets_image_editor.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:ocideck/widgets/presentation/audience_controls_bar.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Slide _slide(
  SlideType type, {
  List<String> bullets = const ['Eerste punt', '\tSubpunt', 'Tweede punt'],
}) => Slide.create(type).copyWith(
  title: 'Mijn punten',
  imagePath: type == SlideType.bulletsImage ? 'beelden/foto.png' : '',
  bullets: bullets,
  calloutReveal: BulletRevealMode.steps,
);

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ),
);

void main() {
  test('groepskop verschijnt met het volgende hoofdpunt', () {
    final plan = BulletRevealStepPlan([
      '${kGroupHeadingMarker}Groep A',
      'Een',
      '\tSubpunt',
      '${kGroupHeadingMarker}Groep B',
      'Twee',
    ]);
    expect(plan.remainingSteps, 2);
    expect(plan.revealedBulletCount(1), 3);
    expect(plan.revealedBulletCount(2), 5);
  });

  testWidgets('navigatieknoppen werken binnen de eerste en laatste slide', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        FullscreenPresenter(
          slides: [_slide(SlideType.bullets)],
          projectPath: null,
          themeProfile: const ThemeProfile(),
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();
    AudienceControlsBar controls() =>
        tester.widget(find.byType(AudienceControlsBar));
    expect(controls().onPrev, isNull);
    expect(controls().onNext, isNotNull);
    controls().onNext!();
    await tester.pump();
    expect(find.text('Eerste punt').hitTestable(), findsOneWidget);
    expect(controls().onPrev, isNotNull);
    controls().onPrev!();
    await tester.pump();
    expect(find.text('Eerste punt').hitTestable(), findsNothing);
  });

  test('hoofdpunten en subpunten vormen stappen, lege regels niet', () {
    final plan = PresentationStepPlan.forSlide(
      _slide(
        SlideType.bullets,
        bullets: ['', 'Eerste punt', '\tSubpunt', '  ', 'Tweede punt'],
      ),
    );
    expect(plan, isA<BulletRevealStepPlan>());
    expect(plan.remainingSteps, 2);
    expect(bulletRevealedCountForSlide(_slide(SlideType.bullets), 0), 0);
    expect(bulletRevealedCountForSlide(_slide(SlideType.bullets), 1), 2);
    expect(bulletRevealedCountForSlide(_slide(SlideType.bullets), 99), 3);
    expect(
      PresentationStepPlan.forSlide(
        _slide(SlideType.bullets, bullets: []),
      ).hasSteps,
      isFalse,
    );
    expect(
      PresentationStepPlan.forSlide(
        _slide(SlideType.bullets, bullets: ['Een']),
      ).remainingSteps,
      1,
    );
    expect(
      PresentationStepPlan.forSlide(
        _slide(SlideType.bullets).copyWith(listStyle: ListStyle.richText),
      ).hasSteps,
      isFalse,
    );
  });

  for (final type in [SlideType.bullets, SlideType.bulletsImage]) {
    test('keuze overleeft opslaan, heropenen en uitschakelen: $type', () {
      final md = MarkdownService();
      final source = md.generateDeck(
        Deck(title: 'Stappen', slides: [_slide(type)]),
      );
      expect(source, contains('bullet-steps'));
      final parsed = md.parseDeck(source)!.slides.single;
      expect(parsed.type, type);
      expect(parsed.calloutReveal, BulletRevealMode.steps);
      expect(parsed.cssClass, isNot(contains('bullet-steps')));
      final disabled = md.generateDeck(
        Deck(
          title: 'Stappen',
          slides: [parsed.copyWith(calloutReveal: BulletRevealMode.all)],
        ),
      );
      expect(disabled, isNot(contains('bullet-steps')));
      expect(
        md.parseDeck(disabled)!.slides.single.calloutReveal,
        BulletRevealMode.all,
      );
    });

    testWidgets(
      'editor biedt stapkeuze en bewaart die bij een titelbewerking: $type',
      (tester) async {
        var slide = _slide(type).copyWith(calloutReveal: BulletRevealMode.all);
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) {
                void update(Slide value) => setState(() => slide = value);
                return type == SlideType.bullets
                    ? BulletsEditor(slide: slide, onUpdate: update)
                    : BulletsImageEditor(
                        slide: slide,
                        onUpdate: update,
                        imageService: ImageService(),
                      );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Stap-voor-stap'));
        await tester.pump();
        expect(slide.calloutReveal, BulletRevealMode.steps);
        await tester.enterText(find.byType(TextField).first, 'Nieuwe titel');
        await tester.pump();
        expect(slide.calloutReveal, BulletRevealMode.steps);
        expect(slide.title, 'Nieuwe titel');
      },
    );

    testWidgets(
      'onthullen behoudt posities; statische preview toont alles: $type',
      (tester) async {
        final slide = _slide(type);
        Future<void> show(int? count) async {
          await tester.pumpWidget(
            _app(
              Center(
                child: SizedBox(
                  width: 700,
                  height: 394,
                  child: SlidePreviewWidget(
                    slide: slide,
                    calloutRevealedBulletCount: count,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        }

        await show(0);
        expect(find.text('Eerste punt').hitTestable(), findsNothing);
        expect(find.text('Tweede punt').hitTestable(), findsNothing);
        final position = tester.getTopLeft(find.text('Tweede punt'));
        await show(2);
        expect(find.text('Eerste punt').hitTestable(), findsOneWidget);
        expect(find.text('Subpunt').hitTestable(), findsOneWidget);
        expect(find.text('Tweede punt').hitTestable(), findsNothing);
        expect(tester.getTopLeft(find.text('Tweede punt')), position);
        await show(null);
        expect(find.text('Tweede punt').hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(find.text('Tweede punt')), position);
      },
    );

    testWidgets(
      'presentatie onthult, gaat terug en bladert pas na het laatste punt: $type',
      (tester) async {
        await tester.pumpWidget(
          _app(
            FullscreenPresenter(
              slides: [
                _slide(type),
                Slide.create(SlideType.title).copyWith(title: 'Volgende dia'),
              ],
              projectPath: null,
              themeProfile: const ThemeProfile(),
              initialIndex: 0,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Eerste punt').hitTestable(), findsNothing);
        await tester.tapAt(const Offset(400, 250));
        await tester.pump();
        expect(find.text('Eerste punt').hitTestable(), findsOneWidget);
        expect(find.text('Subpunt').hitTestable(), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.text('Eerste punt').hitTestable(), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(find.text('Tweede punt').hitTestable(), findsOneWidget);
        expect(find.text('Volgende dia').hitTestable(), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(find.text('Volgende dia').hitTestable(), findsOneWidget);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }),
    );
  }
}
