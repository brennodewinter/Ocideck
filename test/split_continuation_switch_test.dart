import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/split_run.dart';
import 'package:ocideck/widgets/editors/bullets_editor.dart';
import 'package:ocideck/widgets/editors/bullets_image_editor.dart';
import 'package:ocideck/widgets/editors/two_bullets_editor.dart';

/// `continuesSplit` bepaalt hoe groot je tekst wordt weergegeven — pagina's van
/// één reeks delen de grootte van de volste pagina — maar was alleen in de
/// Markdown te zien of te wijzigen. Deze schakelaar zet dat recht: de vlag hoort
/// in de editor te staan, niet alleen in de brontekst.
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 1400, height: 2000, child: child)),
  ),
);

const _label = 'Voortzetting van vorige slide';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('canContinueSplitFrom', () {
    Slide bullets({ListStyle style = ListStyle.bullets}) =>
        Slide.create(SlideType.bullets).copyWith(listStyle: style);

    test('de eerste slide heeft geen voorganger', () {
      expect(canContinueSplitFrom([bullets()], 0), isFalse);
    });

    test('twee gelijksoortige bulletslides kunnen een reeks vormen', () {
      expect(canContinueSplitFrom([bullets(), bullets()], 1), isTrue);
    });

    test('een andere liststyle vormt geen reeks', () {
      expect(
        canContinueSplitFrom([
          bullets(),
          bullets(style: ListStyle.checklist),
        ], 1),
        isFalse,
      );
    });

    test('een ander slidetype vormt geen reeks', () {
      expect(
        canContinueSplitFrom([Slide.create(SlideType.chart), bullets()], 1),
        isFalse,
      );
    });
  });

  testWidgets('bullets: de schakelaar zet en wist continuesSplit', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.bullets).copyWith(bullets: ['Een']);
    await tester.pumpWidget(
      _host(
        BulletsEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          canContinueSplit: true,
        ),
      ),
    );

    expect(find.text(_label), findsOneWidget);
    // De ondertitel noemt het gevolg, want dát is de reden om hem uit te zetten.
    expect(
      find.textContaining('deelt daarmee één lettergrootte'),
      findsOneWidget,
    );

    await tester.tap(find.text(_label));
    await tester.pump();
    expect(updated.continuesSplit, isTrue);

    await tester.tap(find.text(_label));
    await tester.pump();
    expect(updated.continuesSplit, isFalse);
  });

  testWidgets('bullets+image: dezelfde schakelaar, en hij toont de huidige '
      'stand van een slide die al een voortzetting is', (tester) async {
    var updated = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Een'], continuesSplit: true);
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
          canContinueSplit: true,
        ),
      ),
    );

    final tile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text(_label),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(tile.value, isTrue, reason: 'toont de bestaande vlag');

    // Uitzetten is precies de fix voor een slide die per ongeluk vastzit.
    await tester.tap(find.text(_label));
    await tester.pump();
    expect(updated.continuesSplit, isFalse);
  });

  testWidgets('twee kolommen: ook daar bedienbaar', (tester) async {
    var updated = Slide.create(
      SlideType.twoBullets,
    ).copyWith(bullets: ['Links'], bullets2: ['Rechts']);
    await tester.pumpWidget(
      _host(
        TwoBulletsEditor(
          slide: updated,
          onUpdate: (s) => updated = s,
          canContinueSplit: true,
        ),
      ),
    );

    await tester.tap(find.text(_label));
    await tester.pump();
    expect(updated.continuesSplit, isTrue);
  });

  testWidgets('geen schakelaar zonder gelijksoortige voorganger', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BulletsEditor(
          slide: Slide.create(SlideType.bullets).copyWith(bullets: ['Een']),
          onUpdate: (_) {},
        ),
      ),
    );
    expect(find.text(_label), findsNothing);
  });

  testWidgets('een stale vlag wordt gewist zodra de reeks niet meer kan', (
    tester,
  ) async {
    // De slide draagt de vlag nog uit de Markdown, maar zijn voorganger past er
    // niet meer bij. De editor mag die vlag dan niet stilzwijgend laten staan.
    var updated = Slide.create(
      SlideType.bullets,
    ).copyWith(bullets: ['Een'], continuesSplit: true);
    await tester.pumpWidget(
      _host(BulletsEditor(slide: updated, onUpdate: (s) => updated = s)),
    );

    await tester.enterText(find.byType(TextField).first, 'Nieuwe titel');
    await tester.pump();

    expect(updated.continuesSplit, isFalse);
  });
}
