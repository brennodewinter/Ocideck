import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/editors/callout_editor.dart';

/// Widget tests for [CalloutEditorDialog] — verifies the dialog renders with
/// its title, shows the slide's bullets, and has an add-callout button.

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: _delegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// The dialog content is 900×600, wider than the default 800×600 test surface.
Future<void> _setSurface(WidgetTester tester) =>
    tester.binding.setSurfaceSize(const Size(1200, 800));

/// A minimal valid 1×1 transparent PNG.
final _pngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ),
);

/// #1860: tik op het beeld om een doel te plaatsen (plaatsingsmodus).
/// Tikt op het midden van het beeldvlak (AspectRatio).
Future<void> _placeOnImage(WidgetTester tester) async {
  final box = tester.getRect(find.byType(AspectRatio));
  await tester.tapAt(Offset(box.center.dx, box.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  testWidgets('dialog renders with title Afbeeldingsverwijzingen', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt', 'Tweede punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Afbeeldingsverwijzingen'), findsOneWidget);
  });

  testWidgets('bullet list shows bullets', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt', 'Tweede punt', 'Derde punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Eerste punt'), findsOneWidget);
    expect(find.text('Tweede punt'), findsOneWidget);
    expect(find.text('Derde punt'), findsOneWidget);
  });

  testWidgets('add callout button exists', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    // The "Toevoegen" (Add) button is shown for bullets without a callout.
    expect(find.text('Toevoegen'), findsOneWidget);
  });

  testWidgets('clicking add assigns a callout and emits via onUpdate', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // #1860: "Toevoegen" gaat in plaatsingsmodus — nog geen doel geplaatst.
    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();
    expect(updated.callouts, isEmpty, reason: 'nog geen emit vóór plaatsing');

    // Tik op het beeld om het doel te plaatsen.
    await _placeOnImage(tester);

    // The callout is emitted via onUpdate with reference 'A'.
    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.reference, 'A');
    // En de zichtbare koppelsleutel staat in de bullet. Zonder die letter
    // hoort de callout bij niets: na opslaan en heropenen is hij weg, want de
    // koppeling bullet↔verwijzing loopt via precies deze `(A)` (§2.1).
    expect(updated.bullets, ['Eerste punt (A)']);
  });

  testWidgets('twee verwijzingen achter elkaar, zonder de dialoog te sluiten', (
    tester,
  ) async {
    // Zo gebruikt een mens hem: de dialoog blijft open. Hij wordt níet opnieuw
    // opgebouwd met de bijgewerkte dia, dus `widget.slide` loopt achter. Werd
    // daaruit gerekend, dan overschreef de tweede verwijzing de letter van de
    // eerste — die raakte los van haar callout en was in de dialoog niet meer
    // te bereiken, want de lijst koppelt op precies die letter.
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt', 'Tweede punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // #1860: plaats eerste verwijzing.
    await tester.tap(find.text('Toevoegen').first);
    await tester.pumpAndSettle();
    await _placeOnImage(tester);
    // Geen nieuwe pumpWidget: de dialoog blijft staan, precies als in de app.
    await tester.tap(find.text('Toevoegen').first);
    await tester.pumpAndSettle();
    await _placeOnImage(tester);

    expect(updated.bullets, ['Eerste punt (A)', 'Tweede punt (B)']);
    expect(updated.callouts.map((c) => c.reference), ['A', 'B']);
    // En de lijst laat het meteen zien: twee badges, geen 'Toevoegen' meer.
    expect(find.text('Toevoegen'), findsNothing);
  });

  testWidgets('verwijderen in een openstaande dialoog haalt de letter weg', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt', 'Tweede punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // #1860: plaats eerst een verwijzing, dan pas verwijderen.
    await tester.tap(find.text('Toevoegen').first);
    await tester.pumpAndSettle();
    await _placeOnImage(tester);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    expect(updated.callouts, isEmpty);
    expect(updated.bullets, [
      'Eerste punt',
      'Tweede punt',
    ], reason: 'een letter zonder verwijzing laat de zin naar niets verwijzen');
  });

  testWidgets('een tweede verwijzing landt op de tweede bullet', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt', 'Tweede punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    Widget dialog() => _host(
      CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s),
    );
    await tester.pumpWidget(dialog());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toevoegen').first);
    await tester.pumpAndSettle();
    await _placeOnImage(tester);

    // De dialoog opnieuw opbouwen met de bijgewerkte dia — zo werkt de editor
    // ook: elke wijziging gaat door de deckstand heen en komt terug.
    await tester.pumpWidget(dialog());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toevoegen').first);
    await tester.pumpAndSettle();
    await _placeOnImage(tester);

    expect(updated.bullets, ['Eerste punt (A)', 'Tweede punt (B)']);
    expect(updated.callouts.map((c) => c.reference), ['A', 'B']);
  });

  testWidgets('een verwijzing verwijderen haalt ook de letter weg', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt (A)'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.4, 0.2)],
          description: 'de klep',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    expect(updated.callouts, isEmpty);
    expect(
      updated.bullets,
      ['Eerste punt'],
      reason:
          'een letter zonder verwijzing leest een volgende opening als een '
          'callout die niet bestaat',
    );
  });

  testWidgets('close button dismisses the dialog', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sluiten'), findsOneWidget);
    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    expect(find.text('Afbeeldingsverwijzingen'), findsNothing);
  });

  testWidgets('presentation mode toggle exists (Pins / Gebieden)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pins'), findsOneWidget);
    expect(find.text('Gebieden'), findsOneWidget);
  });

  testWidgets('adding callout in region mode creates a CalloutRegion', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      calloutPresentation: CalloutPresentation.region,
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Switch to region mode.
    await tester.tap(find.text('Gebieden'));
    await tester.pumpAndSettle();

    // #1860: "Toevoegen" gaat in plaatsingsmodus — sleep op het beeld.
    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(AspectRatio));
    await tester.dragFrom(
      Offset(box.left + box.width * 0.3, box.top + box.height * 0.3),
      Offset(box.width * 0.3, box.height * 0.3),
    );
    await tester.pumpAndSettle();

    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.targets.first, isA<CalloutRegion>());
    expect(updated.calloutPresentation, CalloutPresentation.region);
  });

  testWidgets('adding callout in pin mode creates a CalloutPoint', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // #1860: "Toevoegen" gaat in plaatsingsmodus — tik op het beeld.
    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();
    await _placeOnImage(tester);

    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.targets.first, isA<CalloutPoint>());
  });

  testWidgets('reveal mode toggle exists (Alles tonen / Stap-voor-stap)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alles tonen'), findsOneWidget);
    expect(find.text('Stap-voor-stap'), findsOneWidget);
  });

  testWidgets('switching to Stap-voor-stap emits calloutReveal=steps', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Default is BulletRevealMode.all.
    expect(updated.calloutReveal, BulletRevealMode.all);

    await tester.tap(find.text('Stap-voor-stap'));
    await tester.pumpAndSettle();

    expect(updated.calloutReveal, BulletRevealMode.steps);
  });

  testWidgets('arrow mode toggle exists (Pijlen)', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pijlen'), findsOneWidget);
  });

  testWidgets('switching to Pijlen emits calloutPresentation=arrow', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Default is pin.
    expect(updated.calloutPresentation, CalloutPresentation.pin);

    await tester.tap(find.text('Pijlen'));
    await tester.pumpAndSettle();

    expect(updated.calloutPresentation, CalloutPresentation.arrow);
  });

  testWidgets('een doel buiten beeld toont een waarschuwing (#1853)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Een 1×1 PNG (vierkant) in een slot met aspect ≈ 0.71 (40% van 16:9).
    // Cover schaalt op slot-hoogte (want beeld is smaller dan slot), dus
    // de volledige hoogte is zichtbaar en de breedte overflows.
    // Een doel op x=0.01 valt buiten de zichtbare band (links afgesneden).
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.01, 0.5)],
          description: 'rand',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    // Pump extra frames to allow the image provider to resolve intrinsic dims.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Selecteer de callout door op de bullet te tikken.
    await tester.tap(find.textContaining('punt').first);
    await tester.pumpAndSettle();

    // De waarschuwingstekst bevat de reference en "buiten beeld".
    expect(
      find.textContaining('buiten beeld'),
      findsWidgets,
      reason: 'de editor toont dat doel (A) buiten beeld valt (#1853)',
    );
  });

  testWidgets('een doel in het midden toont geen waarschuwing (#1853)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      anchor: 'test',
      bullets: ['punt (A)'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.5, 0.5)],
          description: 'midden',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Selecteer de callout door op de bullet te tikken.
    await tester.tap(find.textContaining('punt').first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('buiten beeld'),
      findsNothing,
      reason: 'een doel in het midden is altijd zichtbaar',
    );
  });

  testWidgets('beschrijving editen springt niet weg (#1863)', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['punt (A)'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.5, 0.5)],
          description: '',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Selecteer de callout.
    await tester.tap(find.textContaining('punt').first);
    await tester.pumpAndSettle();

    // Typ in het beschrijvingsveld — elke aanpassing triggert een rebuild.
    // #1863: voor de fix maakte build() een nieuwe TextEditingController aan,
    // die de cursor naar het eind sprong. Nu de controller bij de State staat,
    // blijft de cursor staan.
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();

    expect(updated.callouts.first.description, 'abc');

    // Typ verder — als de controller bij de State staat blijft de tekst
    // aaneengesloten en gaat de cursor niet weg.
    await tester.enterText(find.byType(TextField), 'abcdef');
    await tester.pumpAndSettle();

    expect(updated.callouts.first.description, 'abcdef');
  });

  testWidgets(
    'Doel verwijderen haalt het geselecteerde doel weg, niet het laatste (#1864)',
    (tester) async {
      await _setSurface(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final slide = Slide.create(SlideType.bulletsImage).copyWith(
        bullets: ['punt (A)'],
        imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [
              CalloutPoint(0.2, 0.2),
              CalloutPoint(0.5, 0.5),
              CalloutPoint(0.8, 0.8),
            ],
            description: '',
          ),
        ],
      );

      var updated = slide;
      await tester.pumpWidget(
        _host(CalloutEditorDialog(slide: slide, onUpdate: (s) => updated = s)),
      );
      await tester.pumpAndSettle();

      // Selecteer de callout.
      await tester.tap(find.textContaining('punt').first);
      await tester.pumpAndSettle();

      // Tik op het middelste doel (0.5, 0.5) om het te selecteren.
      final imageStack = find.byType(Stack).first;
      final box = tester.getRect(imageStack);
      await tester.tapAt(Offset(box.center.dx, box.center.dy));
      await tester.pumpAndSettle();

      // Verwijder het geselecteerde doel.
      await tester.tap(find.text('Doel verwijderen'));
      await tester.pumpAndSettle();

      // Het middelste doel (0.5, 0.5) moet weg zijn, niet het laatste (0.8, 0.8).
      expect(updated.callouts.first.targets, hasLength(2));
      expect(
        updated.callouts.first.targets.map((t) => (t as CalloutPoint).x),
        containsAll([0.2, 0.8]),
        reason:
            'het geselecteerde middelste doel is weg, het laatste staat er nog',
      );
    },
  );

  testWidgets('laatste doel verwijderen toont undo-melding (#1864)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['punt (A)'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.5, 0.5)],
          description: 'test',
        ),
      ],
    );

    var updated = slide;
    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Selecteer de callout.
    await tester.tap(find.textContaining('punt').first);
    await tester.pumpAndSettle();

    // Selecteer het doel door op de marker te tikken.
    final imageStack = find.byType(Stack).first;
    final box = tester.getRect(imageStack);
    await tester.tapAt(Offset(box.center.dx, box.center.dy));
    await tester.pumpAndSettle();

    // Het enige doel verwijderen — de hele verwijzing valt weg.
    await tester.tap(find.text('Doel verwijderen'));
    await tester.pumpAndSettle();

    // De verwijzing is weg.
    expect(updated.callouts, isEmpty);

    // De undo-melding is verschenen.
    expect(find.text('Verwijzing verwijderd'), findsOneWidget);
    expect(find.text('Ongedaan maken'), findsOneWidget);

    // Tik op Ongedaan maken — de verwijzing komt terug.
    await tester.tap(find.text('Ongedaan maken'));
    await tester.pumpAndSettle();

    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.reference, 'A');
  });

  // #1854: de stage moet de aspectratio van het echte beeldslot gebruiken,
  // niet de dialoogverhouding — anders dekt cover een ander deel dan op de dia.
  testWidgets('stage gebruikt de slot-aspectratio (#1854)', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['punt (A)'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.5, 0.5)],
          description: '',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    // imgFraction = 0.40 (default), slot-aspect = 0.40 * 16/9 ≈ 0.7111.
    final aspect = tester
        .widget<AspectRatio>(find.byType(AspectRatio))
        .aspectRatio;
    expect(aspect, closeTo(0.40 * 16 / 9, 0.001));
  });

  // #1854: alle verwijzingen tonen, niet alleen de geselecteerde — anders
  // plaats je een tweede doel zonder te zien waar de eerste staat.
  testWidgets('alle verwijzingen tonen zonder selectie (#1854)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['eerste (A)', 'tweede (B)'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.3, 0.3)],
          description: '',
        ),
        ImageCallout(
          reference: 'B',
          targets: [CalloutPoint(0.7, 0.7)],
          description: '',
        ),
      ],
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Geen callout geselecteerd — toch moeten beide reference-letters als
    // statische markeringen zichtbaar zijn in het beeldvlak.
    expect(find.text('A'), findsWidgets);
    expect(find.text('B'), findsWidgets);
  });

  // #1854: het beeld is altijd aanwezig, ook zonder selectie — voorheen
  // toonde het werkvlak "Selecteer een regel" in plaats van de afbeelding.
  testWidgets('beeld toont altijd, ook zonder selectie (#1854)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Het beeld wordt gerenderd (Image widget aanwezig), ook zonder
    // callout-selectie.
    expect(find.byType(Image), findsWidgets);
  });

  // #1860: "Toevoegen" plaatst niet meteen op 0.5/0.5 maar toont een
  // instructie en wacht op een klik op het beeld.
  testWidgets('plaatsingsmodus toont instructie en wacht op klik (#1860)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Toevoegen'));
    await tester.pumpAndSettle();

    // Instructie is zichtbaar.
    expect(
      find.text('Klik op de afbeelding waar deze regel naar verwijst.'),
      findsOneWidget,
    );
    // Nog geen emit — de callout is incompleet.
    expect(updated.callouts, isEmpty);

    // Tik op het beeld plaatst het doel.
    await _placeOnImage(tester);
    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.targets, hasLength(1));
  });

  // #1860: in gebied-modus toont de plaatsingsmodus een sleep-instructie.
  testWidgets(
    'plaatsingsmodus in gebied-modus toont sleep-instructie (#1860)',
    (tester) async {
      await _setSurface(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final slide = Slide.create(SlideType.bulletsImage).copyWith(
        bullets: ['Eerste punt'],
        imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
        calloutPresentation: CalloutPresentation.region,
      );

      await tester.pumpWidget(
        _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Toevoegen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Sleep op de afbeelding om een gebied te markeren.'),
        findsOneWidget,
      );
    },
  );

  // #1860: "Toevoegen" op een andere bullet annuleert de vorige plaatsing.
  testWidgets('tweede Toevoegen annuleert onvoltooide plaatsing (#1860)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Eerste punt', 'Tweede punt'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Start plaatsing voor eerste bullet — niet afmaken.
    await tester.tap(find.text('Toevoegen').first);
    await tester.pumpAndSettle();
    expect(updated.callouts, isEmpty, reason: 'nog geen emit');

    // Start plaatsing voor tweede bullet — eerste moet worden geannuleerd.
    await tester.tap(find.text('Toevoegen').first);
    await tester.pumpAndSettle();

    // Plaats het doel voor de tweede bullet.
    await _placeOnImage(tester);

    expect(updated.callouts, hasLength(1));
    expect(updated.callouts.first.reference, 'A');
    // De eerste bullet heeft geen letter meer.
    expect(updated.bullets, ['Eerste punt', 'Tweede punt (A)']);
  });

  // #1860: letters volgen leesvolgorde, niet aanmaakvolgorde.
  testWidgets('letters hernummeren in leesvolgorde (#1860)', (tester) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var updated = Slide.create(SlideType.bulletsImage).copyWith(
      bullets: ['Punt 1', 'Punt 2', 'Punt 3', 'Punt 4'],
      imagePath: WebAssetStore.put(_pngBytes, name: 'test.png'),
    );

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: updated, onUpdate: (s) => updated = s)),
    );
    await tester.pumpAndSettle();

    // Voeg verwijzingen toe in volgorde 1, 2, 4, 3 — niet in leesvolgorde.
    // Punt 1 → A
    await tester.tap(find.text('Toevoegen').at(0));
    await tester.pumpAndSettle();
    await _placeOnImage(tester);
    // Punt 2 → B (enige Toevoegen-knop over voor punt 2)
    await tester.tap(find.text('Toevoegen').at(0));
    await tester.pumpAndSettle();
    await _placeOnImage(tester);
    // Punt 4 → C in aanmaakvolgorde (twee Toevoegen-knoppen: punt 3 en 4)
    await tester.tap(find.text('Toevoegen').at(1));
    await tester.pumpAndSettle();
    await _placeOnImage(tester);
    // Punt 3 → D in aanmaakvolgorde (enige Toevoegen-knop over: punt 3)
    await tester.tap(find.text('Toevoegen').at(0));
    await tester.pumpAndSettle();
    await _placeOnImage(tester);

    // Letters moeten in leesvolgorde staan: 1→A, 2→B, 3→C, 4→D.
    expect(updated.bullets, [
      'Punt 1 (A)',
      'Punt 2 (B)',
      'Punt 3 (C)',
      'Punt 4 (D)',
    ]);
    expect(updated.callouts.map((c) => c.reference), ['A', 'B', 'C', 'D']);
  });

  // #1860: hint onder de presentatiewijze-knoppen legt uit dat het dia-breed is.
  testWidgets('presentatiewijze toont hint over dia-brede werking (#1860)', (
    tester,
  ) async {
    await _setSurface(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(bullets: ['Eerste punt']);

    await tester.pumpWidget(
      _host(CalloutEditorDialog(slide: slide, onUpdate: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Geldt voor de hele dia'),
      findsOneWidget,
      reason: 'de hint legt uit dat de presentatiewijze dia-breed is',
    );
  });
}
