@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/integration_registry.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/state/openkat_provider.dart';

/// Het integratieregister (#1158): de laag waarop het tabblad Integraties en de
/// "alles aan/uit"-bediening leunen. De poortregels leven in de afgeleide
/// providers; deze test pint ze, zodat een tweede integratie erbij ze niet stil
/// kan verschuiven.
void main() {
  ProviderContainer maak({
    required bool openKatAvailable,
    bool openKatEnabled = false,
    bool ociServeAvailable = true,
    bool ociServeEnabled = false,
  }) {
    final c = ProviderContainer(
      overrides: [
        openKatAvailableProvider.overrideWithValue(openKatAvailable),
        openKatIntegrationEnabledProvider.overrideWithValue(openKatEnabled),
        ociServeAvailableProvider.overrideWithValue(ociServeAvailable),
        ociServeEnabledProvider.overrideWithValue(ociServeEnabled),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('het register kent beide integraties in kaartvolgorde', () {
    expect(integrationRegistry.map((entry) => entry.id), [
      IntegrationId.openKat,
      IntegrationId.ociServe,
    ]);
  });

  group('beschikbaarheid', () {
    test('een beschikbare integratie telt mee', () {
      final c = maak(openKatAvailable: true);
      expect(c.read(availableIntegrationsProvider), hasLength(2));
      expect(c.read(anyIntegrationAvailableProvider), isTrue);
    });

    test('zonder beschikbare integratie is de lijst leeg', () {
      // Op web valt OpenKAT weg; dan hoort het tabblad er niet te zijn.
      final c = maak(openKatAvailable: false, ociServeAvailable: false);
      expect(c.read(availableIntegrationsProvider), isEmpty);
      expect(c.read(anyIntegrationAvailableProvider), isFalse);
    });
  });

  group('alles aan/uit leest de stand', () {
    test('alles aan wanneer beide integraties aan staan', () {
      final c = maak(
        openKatAvailable: true,
        openKatEnabled: true,
        ociServeEnabled: true,
      );
      expect(c.read(allIntegrationsEnabledProvider), isTrue);
      expect(c.read(anyIntegrationEnabledProvider), isTrue);
    });

    test('één actieve integratie is niet alles, maar wel minstens één', () {
      final c = maak(openKatAvailable: true, ociServeEnabled: true);
      expect(c.read(allIntegrationsEnabledProvider), isFalse);
      expect(c.read(anyIntegrationEnabledProvider), isTrue);
    });

    test('een lege lijst telt niet als "alles aan"', () {
      // Niets beschikbaar is niet hetzelfde als alles ingeschakeld: dan valt er
      // niets aan te zetten, en "Alles inschakelen" hoort bruikbaar te blijven.
      final c = maak(
        openKatAvailable: false,
        openKatEnabled: true,
        ociServeAvailable: false,
        ociServeEnabled: true,
      );
      expect(c.read(allIntegrationsEnabledProvider), isFalse);
      expect(c.read(anyIntegrationEnabledProvider), isFalse);
    });
  });
}
