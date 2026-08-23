import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression: het Vigilis-merk in de voettekst van het openscherm is het enige
/// `Image.asset` op dat scherm dat niet in een vaste breedte of `Flexible` zit.
/// Faalt de asset (stale build, corrupte installatie, ontbrekend bestand), dan
/// kan de broken-image placeholder in de onbegrensde `Row`-slot de rij breder
/// maken dan de `ConstrainedBox(maxWidth: 220)` eromheen — een RenderFlex-
/// overflow op de voettekst, die op macOS samen met de `AssetManifest.bin`-
/// melding opdook. Het logo is nu begrensd, dus een failed load mag de voettekst
/// niet meer laten overlopen.
void main() {
  setUp(() {
    // Voorbij de consent-gate zodat de app-shell en het openscherm renderen.
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  testWidgets('voettekst loopt niet over als het Vigilis-merk niet laadt', (
    tester,
  ) async {
    // Vang elke fout afzonderlijk op — `tester.takeException()` geeft bij
    // meerdere fouten één samengevatte string terug, waarin het woord
    // 'overflowed' niet voorkomt en de regressie zich dus aan de assert
    // zou onttrekken.
    final details = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = details.add;
    try {
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _VigilisFailingBundle(),
          child: const ProviderScope(child: OciDeckApp()),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = previous;
    }

    // De "Unable to load asset"-fout voor het logo hoort er te zijn — dat is
    // precies de situatie die we forceren. Een RenderFlex-overflow hoort er
    // níet te zijn: dat is de regressie.
    final overflow = details.where((d) => d.toString().contains('overflowed'));
    expect(
      overflow,
      isEmpty,
      reason:
          'een failed Vigilis-asset mag de voettekst-Rij niet laten '
          'overlopen',
    );
  });
}

/// Een asset-bundel die het Vigilis-merk laat falen (lege bytes → niet te
/// decoderen) en voor al het restanten doordelegeert naar de echte root-bundel,
/// zodat alleen de situatie wordt nagebootst die de regressie triggerde.
class _VigilisFailingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.contains('vigilis-logo')) return ByteData(0);
    return rootBundle.load(key);
  }
}
