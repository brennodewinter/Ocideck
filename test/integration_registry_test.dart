@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/integration_registry.dart';
import 'package:ocideck/state/openkat_provider.dart';

/// Het integratieregister (#1158): de laag waarop het tabblad Integraties en de
/// "alles aan/uit"-bediening leunen. De poortregels leven in de afgeleide
/// providers; deze test pint ze, zodat een tweede integratie erbij ze niet stil
/// kan verschuiven.
void main() {
  ProviderContainer maak({required bool available, bool enabled = false}) {
    final c = ProviderContainer(
      overrides: [
        openKatAvailableProvider.overrideWithValue(available),
        openKatIntegrationEnabledProvider.overrideWithValue(enabled),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('OpenKAT staat als eerste integratie in het register', () {
    expect(integrationRegistry, hasLength(1));
    expect(integrationRegistry.single.id, IntegrationId.openKat);
  });

  group('beschikbaarheid', () {
    test('een beschikbare integratie telt mee', () {
      final c = maak(available: true);
      expect(c.read(availableIntegrationsProvider), hasLength(1));
      expect(c.read(anyIntegrationAvailableProvider), isTrue);
    });

    test('zonder beschikbare integratie is de lijst leeg', () {
      // Op web valt OpenKAT weg; dan hoort het tabblad er niet te zijn.
      final c = maak(available: false);
      expect(c.read(availableIntegrationsProvider), isEmpty);
      expect(c.read(anyIntegrationAvailableProvider), isFalse);
    });
  });

  group('alles aan/uit leest de stand', () {
    test('alles aan met de enige integratie aan', () {
      final c = maak(available: true, enabled: true);
      expect(c.read(allIntegrationsEnabledProvider), isTrue);
      expect(c.read(anyIntegrationEnabledProvider), isTrue);
    });

    test('alles uit met de enige integratie uit', () {
      final c = maak(available: true, enabled: false);
      expect(c.read(allIntegrationsEnabledProvider), isFalse);
      expect(c.read(anyIntegrationEnabledProvider), isFalse);
    });

    test('een lege lijst telt niet als "alles aan"', () {
      // Niets beschikbaar is niet hetzelfde als alles ingeschakeld: dan valt er
      // niets aan te zetten, en "Alles inschakelen" hoort bruikbaar te blijven.
      final c = maak(available: false, enabled: true);
      expect(c.read(allIntegrationsEnabledProvider), isFalse);
      expect(c.read(anyIntegrationEnabledProvider), isFalse);
    });
  });
}
