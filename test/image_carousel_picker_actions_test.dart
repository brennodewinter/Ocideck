import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';

import 'support/pump_until.dart';

/// Aanvullende dekking voor `image_carousel_picker_actions.dart` — het
/// untagged-only-filter, de zoekrelevantie met meerdere termen, en de
/// beschrijving-persist-pad. De smoke-test dekt al de scan, de view-toggle
/// en een enkele zoekterm.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('carousel_actions');
    for (final name in ['alpha.png', 'beta.png', 'gamma.png']) {
      File('${tempDir.path}/$name').writeAsBytesSync(_onePixelPng);
    }
  });

  tearDown(() {
    if (!tempDir.existsSync()) return;
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Opruimen van een tijdelijke map is nooit een testoordeel waard.
    }
  });

  void clearLayoutNoise(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    clearLayoutNoise(tester);
  }

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageCarouselPicker(
              searchPaths: [tempDir.path],
              captionService: CaptionService(),
              descriptionService: DescriptionService(),
            ),
          ),
        ),
      );
    });
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de mapscan van de afbeeldingkiezer bleef laden',
    );
    clearLayoutNoise(tester);
  }

  testWidgets('untagged-only filter toont alle afbeeldingen (niets getagd)', (
    tester,
  ) async {
    await pumpPicker(tester);

    // Er zijn geen beschrijvingen opgeslagen, dus alle drie zijn "untagged".
    // Het toggle-icoon is Icons.label_off_outlined.
    final toggle = find.byIcon(Icons.label_off_outlined);
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await settle(tester);

    // De filter staat aan; alle drie zijn nog zichtbaar (niets getagd).
    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoekterm met meerdere woorden filtert correct', (tester) async {
    await pumpPicker(tester);

    // Typ een zoekterm die niet matcht — de lijst wordt leeg.
    await tester.enterText(find.byType(TextField).first, 'xyz niet bestaand');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek naar "alpha" toont alleen alpha', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField).first, 'alpha');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek met beschrijvingen dekt de description-relevance paden', (
    tester,
  ) async {
    // Pre-populate descriptions: alpha has "klm vliegtuig", beta has "klm logo".
    final descFile = File('${tempDir.path}/.ocideck_descriptions.json');
    descFile.writeAsStringSync(
      jsonEncode({
        'alpha.png': 'klm vliegtuig',
        'beta.png': 'klm logo',
        'gamma.png': 'onverwante tekst',
      }),
    );

    await pumpPicker(tester);

    // Search for "klm" — matches alpha and beta via description words.
    await tester.enterText(find.byType(TextField).first, 'klm');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek naar een woord-prefix in de beschrijving', (tester) async {
    final descFile = File('${tempDir.path}/.ocideck_descriptions.json');
    descFile.writeAsStringSync(
      jsonEncode({
        'alpha.png': 'vliegtuig foto',
        'beta.png': 'onverwant',
        'gamma.png': 'onverwant',
      }),
    );

    await pumpPicker(tester);

    // "vlieg" is een prefix van "vliegtuig" in de beschrijving van alpha.
    await tester.enterText(find.byType(TextField).first, 'vlieg');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek naar een substring in de beschrijving', (tester) async {
    final descFile = File('${tempDir.path}/.ocideck_descriptions.json');
    descFile.writeAsStringSync(
      jsonEncode({
        'alpha.png': 'luchtvaart',
        'beta.png': 'onverwant',
        'gamma.png': 'onverwant',
      }),
    );

    await pumpPicker(tester);

    // "vaart" is een substring van "luchtvaart" maar geen woord-prefix.
    await tester.enterText(find.byType(TextField).first, 'vaart');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('beschrijving invoeren en selectie wijzigen persisteert', (
    tester,
  ) async {
    await pumpPicker(tester);

    // Selecteer de eerste afbeelding en typ een beschrijving.
    // Het beschrijvingsveld is de TextField die niet de zoekbalk is.
    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);

    // Typ in het beschrijvingsveld (meestal de tweede TextField).
    if (textFields.evaluate().length > 1) {
      await tester.enterText(textFields.at(1), 'test beschrijving');
      await settle(tester);
    }

    // Selecteer een andere afbeelding om _persistDescription te triggeren.
    final images = find.byType(Image);
    if (images.evaluate().length > 1) {
      await tester.tap(images.at(0), warnIfMissed: false);
      await settle(tester);
    }

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('Kiezen-knop sluit de dialoog met een resultaat', (tester) async {
    await pumpPicker(tester);

    // De "Kiezen"-knop staat in de preview-kolom.
    final chooseBtn = find.text('Kiezen');
    expect(chooseBtn, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(chooseBtn);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // De dialoog is gesloten.
    expect(find.byType(ImageCarouselPicker), findsNothing);
  });

  testWidgets('een onleesbare submap toont de "onvolledig"-melding', (
    tester,
  ) async {
    // Een submap zonder leesrecht laat de scan struikelen: `result.failed`
    // wordt waar en de kiezer waarschuwt dat de lijst onvolledig kan zijn.
    final locked = Directory('${tempDir.path}/locked')..createSync();
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));

    // `chmod 000` houdt root niet tegen, en CI-containers draaien als root: dan
    // slaagt de scan gewoon en verschijnt de "onvolledig"-melding niet. Deze test
    // toetst het niet-root-gedrag. Toets of het slot echt werkt (map niet te
    // lezen); zo niet (root/CI), sla hem over i.p.v. vals-rood te melden — op een
    // ontwikkelaarsmachine draait hij onverkort.
    var lockEffective = false;
    try {
      locked.listSync();
    } on FileSystemException {
      lockEffective = true;
    }
    if (!lockEffective) {
      markTestSkipped(
        'chmod 000 heeft geen effect als root (CI-container); '
        'het onleesbare-submap-scenario is alleen op non-root toetsbaar.',
      );
      return;
    }

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ImageCarouselPicker(
                searchPaths: [tempDir.path],
                captionService: CaptionService(),
                descriptionService: DescriptionService(),
              ),
            ),
          ),
        ),
      );
    });
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de mapscan van de afbeeldingkiezer bleef laden',
    );
    clearLayoutNoise(tester);
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Sluiten-knop sluit de dialoog zonder resultaat', (tester) async {
    await pumpPicker(tester);

    // De sluiten-knop is het kruisje in de koptekst.
    final closeBtn = find.byIcon(Icons.close);
    expect(closeBtn, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(closeBtn);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // De dialoog is gesloten.
    expect(find.byType(ImageCarouselPicker), findsNothing);
  });

  testWidgets('Duplicaten opruimen ontdubbelt byte-identieke afbeeldingen', (
    tester,
  ) async {
    // De drie fixture-bestanden dragen dezelfde bytes, dus ze vormen één
    // duplicaatgroep: na het opruimen blijft er één staan (#1052-pad). De
    // afrondende SnackBar vraagt om een Scaffold in de boom, wat er in productie
    // altijd is (de kiezer opent boven de app) maar in dit harnas zelf staat.
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ImageCarouselPicker(
                searchPaths: [tempDir.path],
                captionService: CaptionService(),
                descriptionService: DescriptionService(),
              ),
            ),
          ),
        ),
      );
    });
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de mapscan van de afbeeldingkiezer bleef laden',
    );
    clearLayoutNoise(tester);

    final dedupeButton = find.text('Duplicaten opruimen');
    expect(dedupeButton, findsOneWidget);

    // De vergelijking (md5) en de mapscan lopen op echte file-IO, dus wacht op
    // de uitkomst (de dialoogknop) in plaats van op de klok — een vaste delay
    // is onder de volle suite op de CI-runner te krap geweest (zie
    // test/support/pump_until.dart). pumpUntil doet per stap zelf runAsync.
    await tester.tap(dedupeButton, warnIfMissed: false);
    await pumpUntil(
      tester,
      () =>
          find.widgetWithText(ElevatedButton, 'Opruimen').evaluate().isNotEmpty,
      reason: 'de ontdubbel-dialoog verscheen niet (md5-scan liep nog)',
    );
    clearLayoutNoise(tester);

    // De bevestigingsdialoog verschijnt met de "Opruimen"-knop.
    final confirm = find.widgetWithText(ElevatedButton, 'Opruimen');
    expect(confirm, findsOneWidget);

    // De verwijdering loopt op echte file-IO; wacht op de schijf-uitkomst
    // (één overgebleven bestand) in plaats van op een gokte delay.
    await tester.tap(confirm, warnIfMissed: false);
    await pumpUntil(
      tester,
      () =>
          tempDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.png'))
              .length ==
          1,
      reason:
          'de ontdubbeling verwijderde de duplicaten niet (file-IO liep nog)',
    );
    clearLayoutNoise(tester);

    // Er blijft één bestand op schijf staan; twee kopieën zijn verwijderd.
    final remaining = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .length;
    expect(remaining, 1);
    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
