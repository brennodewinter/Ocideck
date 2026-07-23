import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/brand_logo.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In donkere modus stond het OciDeck-logo als groot wit vlak op het openscherm
/// (#735). De oorzaak zat niet in de weergave maar in de asset:
/// `ocideck-logo.png` is volledig ondoorzichtig — alle hoeken `#FFFFFF` bij
/// alfa 255 — dus de witte plaat rondom de tekening was op een donker
/// oppervlak het enige wat je zag.
///
/// Daarom toetst dit bestand eerst de *bestanden* en pas daarna de code. Een
/// widgettest had deze fout nooit gevangen: elke aanroepplek deed precies wat
/// er stond. Alleen een test die in de pixels kijkt, ziet een logo met een
/// ingebakken achtergrond aankomen — bijvoorbeeld wanneer iemand een variant
/// opnieuw exporteert en de transparantie eruit laat lopen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Gedeelde static — altijd terugzetten, anders draaien volgende tests donker.
  tearDown(() => AppTheme.isDark = false);

  Future<img.Image> decode(String assetKey) async {
    final bytes = await rootBundle.load(assetKey);
    final decoded = img.decodePng(bytes.buffer.asUint8List());
    expect(decoded, isNotNull, reason: '$assetKey is geen leesbare PNG');
    return decoded!;
  }

  group('de assets zelf', () {
    test('elke variant staat in pubspec en is te laden', () async {
      for (final logo in BrandLogo.values) {
        await decode(logo.lightAsset);
        await decode(logo.darkAsset);
      }
    });

    test(
      'de donkere variant heeft een écht transparante achtergrond',
      () async {
        for (final logo in BrandLogo.values) {
          final image = await decode(logo.darkAsset);
          final w = image.width, h = image.height;
          for (final corner in [
            [0, 0],
            [w - 1, 0],
            [0, h - 1],
            [w - 1, h - 1],
          ]) {
            expect(
              image.getPixel(corner[0], corner[1]).a,
              0,
              reason:
                  '${logo.darkAsset}: hoek ${corner[0]},${corner[1]} is niet '
                  'transparant — dit is precies de witte plaat uit #735',
            );
          }
        }
      },
    );

    test(
      'de inkt van de donkere variant is licht genoeg voor donker',
      () async {
        for (final logo in BrandLogo.values) {
          final image = await decode(logo.darkAsset);
          var opaque = 0;
          var light = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final p = image.getPixel(x, y);
              if (p.a < 200) continue;
              opaque++;
              // Verzadigde kleuren dragen betekenis (het gele Vigilis-merk) en
              // lezen al op donker; alleen de neutrale inkt moet licht zijn.
              final chroma =
                  [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b) -
                  [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
              if (chroma > 40 || p.luminanceNormalized > 0.6) light++;
            }
          }
          expect(opaque, greaterThan(0), reason: '${logo.darkAsset} is leeg');
          expect(
            light / opaque,
            greaterThan(0.95),
            reason:
                '${logo.darkAsset}: de inkt is donker, dus onzichtbaar op een '
                'donker oppervlak',
          );
        }
      },
    );

    test('licht en donker zijn dezelfde tekening op dezelfde maat', () async {
      for (final logo in BrandLogo.values) {
        final light = await decode(logo.lightAsset);
        final dark = await decode(logo.darkAsset);
        expect(
          [dark.width, dark.height],
          [light.width, light.height],
          reason: '${logo.darkAsset} wijkt in afmeting af van zijn lichte paar',
        );
      }
    });
  });

  group('de keuze per modus', () {
    test('assetKey volgt AppTheme.isDark', () {
      for (final logo in BrandLogo.values) {
        AppTheme.isDark = false;
        expect(logo.assetKey, logo.lightAsset);
        AppTheme.isDark = true;
        expect(logo.assetKey, logo.darkAsset);
      }
    });

    test('geen aanroepplek in lib/ kiest zelf een merklogo', () {
      // De vijfde aanroepplek die iemand toevoegt, is de plek waar dit terugkomt
      // — die krijgt geen compilerfout, alleen een wit vlak. Uitgezonderd:
      // brand_logo.dart zelf, en het LibreKAT-*themaprofiel* in models/, want
      // dát logo staat op een dia. Een dia is een vast wit canvas in beide modi
      // en reist mee in de export, dus daar hoort de lichte variant.
      final literals = {
        for (final logo in BrandLogo.values) ...[
          logo.lightAsset,
          logo.darkAsset,
        ],
      };
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('theme/brand_logo.dart')) continue;
        final source = entity.readAsStringSync();
        for (final literal in literals) {
          if (source.contains("Image.asset(\n") &&
              source.contains("'$literal'")) {
            offenders.add('${entity.path} → $literal');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'gebruik BrandLogo.<merk>.assetKey in plaats van het pad',
      );
    });
  });

  group('"Over OciDeck" in donkere modus', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> openAbout(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => SettingsDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.info_outline).first);
      await tester.pumpAndSettle();
    }

    Set<String> renderedAssetKeys(WidgetTester tester) => {
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        if (image.image case final AssetImage a) a.assetName,
    };

    testWidgets('de merken staan er in hun donkere variant', (tester) async {
      AppTheme.isDark = true;
      await openAbout(tester);

      final keys = renderedAssetKeys(tester);
      expect(keys, contains(BrandLogo.libreKat.darkAsset));
      expect(keys, contains(BrandLogo.vigilis.darkAsset));
      expect(keys, isNot(contains(BrandLogo.libreKat.lightAsset)));
      expect(keys, isNot(contains(BrandLogo.vigilis.lightAsset)));
    });

    testWidgets('in lichte modus blijven het de lichte varianten', (
      tester,
    ) async {
      AppTheme.isDark = false;
      await openAbout(tester);

      final keys = renderedAssetKeys(tester);
      expect(keys, contains(BrandLogo.libreKat.lightAsset));
      expect(keys, contains(BrandLogo.vigilis.lightAsset));
      expect(keys, isNot(contains(BrandLogo.libreKat.darkAsset)));
    });

    testWidgets('de kaarten zijn niet meer hardgecodeerd wit', (tester) async {
      AppTheme.isDark = true;
      await openAbout(tester);

      // De kaart onder "Uitgever" draagt het LibreKAT-merk; die mag in donkere
      // modus niet wit blijven, anders staat er een lichtbak in een donker
      // paneel — dezelfde klacht als #735, één laag hoger.
      final cards = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.borderRadius == BorderRadius.circular(10));
      expect(cards, isNotEmpty, reason: 'geen kaart gevonden om te toetsen');
      expect(
        cards.every((d) => d.color != Colors.white),
        isTrue,
        reason: 'een kaart in "Over OciDeck" staat nog op Colors.white',
      );
    });
  });
}
