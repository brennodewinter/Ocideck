import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/image_limits.dart';
import 'package:ocideck/widgets/slides/previews/retrying_image.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'support/pump_until.dart';
import 'support/temp_dir.dart';

/// #2159 — een transiënte lees-/decodefout zette een dia-afbeelding sessie-lang
/// op de placeholder: de gefaalde completer bleef in `ImageCache._pendingImages`
/// staan en replayde zijn fout naar elke latere resolve. Op het
/// presentatorscherm — met precache die de sleutel vroeg aanraakt — viel dat op
/// als "publiek ziet het beeld, presentator niet". Deze tests leggen vast dat
/// een mislukte lading de cachesleutel opruimt én dat een zichtbare dia
/// vanzelf herstelt.

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

bool _hasDecodedImage() => find
    .byType(RawImage)
    .evaluate()
    .map((e) => (e.widget as RawImage).image)
    .any((image) => image != null);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('CappedImage (#2159)', () {
    testWidgets('een mislukte lading vergiftigt de cachesleutel niet', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const key = 'retry-poison-test';
        final failed = Completer<Object>();
        final failing = CappedImage(
          key,
          () => Future<Uint8List>.error(StateError('transiënt')),
        );
        failing
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener(
                (_, _) => failed.completeError(StateError('had beeld')),
                onError: (e, _) => failed.complete(e),
              ),
            );
        expect(await failed.future, isA<StateError>());
        // De evict draait als microtask ná de error-listeners (ephemeral
        // listeners lopen als laatste in reportError) — een ronde wachten
        // voordat dezelfde key opnieuw opgelost wordt.
        await pumpEventQueue();

        // Dezelfde key met een werkende lading moet nu slagen. Vóór de fix
        // kreeg deze resolve de geparkeerde mislukte completer terug — de
        // loader werd nooit meer aangeroepen en dezelfde fout kwam terug.
        var loads = 0;
        final healthy = CappedImage(key, () {
          loads++;
          return Future<Uint8List>.value(_png());
        });
        final decoded = Completer<bool>();
        healthy
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener(
                (info, _) => decoded.complete(true),
                onError: (_, _) => decoded.complete(false),
              ),
            );
        expect(await decoded.future, isTrue);
        expect(loads, 1, reason: 'de loader moest opnieuw draaien');
      });
    });
  });

  group('RetryingImage', () {
    testWidgets('een transiënte fout herstelt zonder navigatie', (
      tester,
    ) async {
      var loads = 0;
      var errors = 0;
      final provider = CappedImage('flaky', () {
        loads++;
        return loads == 1
            ? Future<Uint8List>.error(StateError('hik'))
            : Future<Uint8List>.value(_png());
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RetryingImage(
              image: provider,
              errorBuilder: (_, _, _) {
                errors++;
                return const Text('placeholder');
              },
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => errors > 0,
        reason: 'eerste fout kwam niet',
      );
      expect(_hasDecodedImage(), isFalse);

      // De retry-pauze zit in nep-tijd; pumpUntil geeft hem echte lus-stappen
      // om de nieuwe lezing en decode af te maken.
      await pumpUntil(
        tester,
        _hasDecodedImage,
        reason: 'de afbeelding herstelde niet na de transiënte fout',
      );
      expect(loads, greaterThanOrEqualTo(2));
    });

    testWidgets('een permanente fout blijft de placeholder tonen', (
      tester,
    ) async {
      var errors = 0;
      final provider = CappedImage(
        'always-broken',
        () => Future<Uint8List>.error(StateError('kapot')),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RetryingImage(
              image: provider,
              errorBuilder: (_, _, _) {
                errors++;
                return const Text('placeholder');
              },
            ),
          ),
        ),
      );
      // Wachten op de uitkomst die de test beweert: twee errorBuilder-ronden
      // betekenen dat de eerste fout géén definitieve staat was maar een nieuwe
      // poging kreeg — en dat de placeholder daarna gewoon weer staat.
      await pumpUntil(
        tester,
        () => errors >= 2,
        reason: 'de afbeelding kreeg geen tweede poging na een fout',
      );
      expect(find.text('placeholder'), findsOneWidget);
      expect(_hasDecodedImage(), isFalse);
    });
  });

  group('dia-afbeelding', () {
    testWidgets('een bestand dat later arriveert verschijnt alsnog', (
      tester,
    ) async {
      // Het gemelde gedrag in miniatuur: de dia staat, het bestand is er nog
      // niet (sync-map levert later). De placeholder moet weggaan zonder dat
      // de gebruiker heen-en-weer navigeert.
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ocideck-retry'),
      );
      if (dir == null) return;
      addTearDown(() => deleteTempDir(dir));
      final projectPath = dir.resolveSymbolicLinksSync();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: SlidePreviewWidget(
                slide: Slide(
                  id: 'x',
                  type: SlideType.image,
                  title: 'Titel',
                  imagePath: 'foto.png',
                ),
                projectPath: projectPath,
              ),
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => find.text('Bestand niet gevonden').evaluate().isNotEmpty,
        reason: 'de placeholder voor het ontbrekende bestand kwam niet',
      );

      await tester.runAsync(
        () => File('$projectPath/foto.png').writeAsBytes(_png()),
      );
      await pumpUntil(
        tester,
        _hasDecodedImage,
        reason: 'de dia herstelde niet toen het bestand arriveerde',
      );
    });
  });
}
