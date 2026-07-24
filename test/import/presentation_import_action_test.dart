import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/shell/presentation_import_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het deck van het actieve tabblad, of `null` als er geen open staat.
Deck? _openDeck(ProviderContainer container) =>
    container.read(tabsProvider).current?.deckNotifier.currentState.deck;

/// Het invoerpunt van de presentatie-import (#772): waarschuwing →
/// bestandskiezer → conversie → nieuwe tab.
///
/// De bestandskiezer zelf laat zich onder `flutter test` niet aansturen
/// (statische `FilePicker`), dus de tests gaan door de `fileOverride`-route —
/// dezelfde code op de keuze na. Wat hier bewaakt wordt is dat een import nooit
/// stil half slaagt: geen deck zonder melding, en geen melding zonder deck.
void main() {
  const dismissedKey = 'presentationImportWarningDismissed';
  const p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
  const a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  const r =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

  /// Een minimale, echte `.pptx`: één dia met een titel en twee opsommingen.
  /// Geen namaakimporter — dit gaat door de echte parser, want het pad dat de
  /// gebruiker loopt is precies wat hier op het spel staat.
  Uint8List pptx({String titel = 'Plan'}) {
    final slide =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="$a" xmlns:p="$p" xmlns:r="$r"><p:cSld><p:spTree>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/>'
        '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$titel</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/><p:cNvSpPr/>'
        '<p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:spPr/>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:t>Eerste</a:t></a:r></a:p>'
        '<a:p><a:r><a:t>Tweede</a:t></a:r></a:p>'
        '</p:txBody></p:sp>'
        '</p:spTree></p:cSld></p:sld>';
    final parts = <String, String>{
      'ppt/presentation.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<p:presentation xmlns:a="$a" xmlns:p="$p" xmlns:r="$r">'
          '<p:sldSz cx="12192000" cy="6858000"/>'
          '<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>'
          '</p:presentation>',
      'ppt/_rels/presentation.xml.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="$pkg"><Relationship Id="rId1" '
          'Type="$r/slide" Target="slides/slide1.xml"/></Relationships>',
      'ppt/slides/slide1.xml': slide,
    };
    final archive = Archive();
    parts.forEach((name, content) {
      final data = Uint8List.fromList(content.codeUnits);
      archive.addFile(ArchiveFile.bytes(name, data));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    WebAssetStore.clear();
    // De waarschuwing is elders getoetst; hier staat ze standaard uit zodat de
    // tests over de import zelf gaan.
    SharedPreferences.setMockInitialValues({dismissedKey: true});
  });
  tearDown(WebAssetStore.clear);

  Future<(ProviderContainer, BuildContext, WidgetRef)> pump(
    WidgetTester tester,
  ) async {
    late BuildContext ctx;
    late WidgetRef reff;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScaffoldMessenger(
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ctx = context;
                  reff = ref;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    return (container, ctx, reff);
  }

  testWidgets('een gekozen presentatie opent als deck in een nieuwe tab', (
    tester,
  ) async {
    final (container, ctx, ref) = await pump(tester);
    // runAsync: `TabsNotifier` start een periodieke autosave-timer, en een
    // FakeTimer blijft na afloop van de test hangen. Zelfde route als de
    // OpenKAT-actietest hiernaast.
    await tester.runAsync(
      () => importPresentation(
        ctx,
        ref,
        fileOverride: (bytes: pptx(titel: 'Kwartaal'), name: 'kwartaal.pptx'),
      ),
    );
    await tester.pumpAndSettle();

    final deck = container
        .read(tabsProvider)
        .current
        ?.deckNotifier
        .currentState
        .deck;
    expect(deck, isNotNull);
    expect(deck!.slides, isNotEmpty);
    expect(
      deck.slides.any((s) => s.title.contains('Kwartaal')),
      isTrue,
      reason: 'de titel van de brondia komt mee',
    );
    expect(find.textContaining('geïmporteerd'), findsOneWidget);
  });

  testWidgets('een onleesbaar bestand meldt de fout en opent geen tab', (
    tester,
  ) async {
    final (container, ctx, ref) = await pump(tester);
    await tester.runAsync(
      () => importPresentation(
        ctx,
        ref,
        fileOverride: (
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          name: 'kapot.pptx',
        ),
      ),
    );
    await tester.pumpAndSettle();

    var opened = true;
    await tester.runAsync(() async {
      opened = _openDeck(container) != null;
    });
    expect(
      opened,
      isFalse,
      reason: 'geen half deck openen op een bestand dat niet te lezen is',
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('de waarschuwing afbreken houdt de hele import tegen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final (container, ctx, ref) = await pump(tester);
    final done = importPresentation(
      ctx,
      ref,
      fileOverride: (bytes: pptx(), name: 'plan.pptx'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    await done;

    // De leestap zit in runAsync omdat `TabsNotifier` bij aanmaak een
    // periodieke timer start; een FakeTimer blijft na de test hangen.
    var opened = true;
    await tester.runAsync(() async {
      opened = _openDeck(container) != null;
    });
    expect(opened, isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  test('het menulabel komt uit de vertaling, niet uit de aanroeper', () {
    AppLocalizations.setActiveLanguageCode('nl');
    final label = presentationImportLabel(const AppLocalizations(Locale('nl')));
    expect(label, isNotEmpty);
    expect(label.toLowerCase(), contains('importeren'));
  });
}
