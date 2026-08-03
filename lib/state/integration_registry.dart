// Het register van de integraties (#1158): koppelingen met andere systemen, elk
// los in en uit te schakelen, met een bediening om ze allemaal tegelijk aan of
// uit te zetten.
//
// Bewust een broertje van `module_registry.dart` en niet één gedeeld framework:
// een module is een stuk functionaliteit dat OciDeck zélf meebrengt, een
// integratie is een koppeling naar buiten met eigen instellingen (waar staan de
// bestanden, welke map). De poortregels overlappen — standaard uit, tonen zodra
// de inhoud er is, uitzetten maakt bestaand werk nooit onbereikbaar — maar de
// afnemers verschillen, en één abstractie zou ze weer op één hoop vegen.
//
// Wat er wél gedeeld is, staat hier als contract: elke integratie kent een
// **beschikbaarheid** (kan dit platform de koppeling aan?), een **schakelaar**
// (staat ze aan?) en een **reveal** (aan, óf er is al inhoud). De "alles
// aan/uit"-bediening op het tabblad Integraties leunt op precies deze drie, en
// een tweede integratie erbij zetten is één regel in [integrationRegistry] —
// het tabblad, het register en de bulkbediening lopen dan vanzelf mee.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'openkat_provider.dart';

/// De integraties, in de volgorde waarin het tabblad Integraties ze toont.
enum IntegrationId { openKat }

/// Eén integratie in het register: wie ze is, waar haar poorten staan, en hoe je
/// haar schakelaar omzet.
///
/// De poortvelden zijn concrete `Provider<bool>`-handvatten (het abstracte
/// listenable-type exporteert flutter_riverpod niet); [setEnabled] is de brug
/// naar de notifier die de keuze bewaart, zodat de bulkbediening niet elk
/// integratietype apart hoeft te kennen.
class IntegrationEntry {
  const IntegrationEntry({
    required this.id,
    required this.available,
    required this.enabled,
    required this.revealed,
    required this.setEnabled,
  });

  final IntegrationId id;

  /// Of dit platform de koppeling kan gebruiken. Een integratie die hier `false`
  /// is, hoort niet op het tabblad en telt niet mee in "alles aan/uit".
  final Provider<bool> available;

  /// Of de schakelaar aan staat.
  final Provider<bool> enabled;

  /// Of de instellingen zichtbaar zijn: aan, óf er is al inhoud. Altijd
  /// minstens zo ruim als [enabled].
  final Provider<bool> revealed;

  /// Zet de schakelaar van deze integratie om en bewaart de keuze. Neemt een
  /// [WidgetRef] omdat de enige aanroepers de schakelkaart en de bulkbediening
  /// op het tabblad zijn; een test schakelt rechtstreeks via de notifier.
  final Future<void> Function(WidgetRef ref, bool value) setEnabled;
}

/// Het register. Volgorde = sectievolgorde op het tabblad Integraties.
final List<IntegrationEntry> integrationRegistry = [
  IntegrationEntry(
    id: IntegrationId.openKat,
    available: openKatAvailableProvider,
    enabled: openKatIntegrationEnabledProvider,
    revealed: openKatIntegrationRevealProvider,
    setEnabled: (WidgetRef ref, value) =>
        ref.read(openKatProvider.notifier).setEnabled(value),
  ),
];

/// De integraties die dít platform kan gebruiken. Op web valt OpenKAT weg en is
/// de lijst leeg — dan hoort het tabblad Integraties er niet te zijn.
final availableIntegrationsProvider = Provider<List<IntegrationEntry>>((ref) {
  return [
    for (final entry in integrationRegistry)
      if (ref.watch(entry.available)) entry,
  ];
});

/// Of er op dit platform überhaupt een integratie te gebruiken is: de poort
/// waar het tabblad Integraties en de zoekindex op kijken.
final anyIntegrationAvailableProvider = Provider<bool>((ref) {
  return ref.watch(availableIntegrationsProvider).isNotEmpty;
});

/// Of álle beschikbare integraties aan staan — de stand die "alles aan/uit"
/// afleest. Een lege lijst telt niet als "alles aan": dan is er niets om aan te
/// zetten.
final allIntegrationsEnabledProvider = Provider<bool>((ref) {
  final available = ref.watch(availableIntegrationsProvider);
  return available.isNotEmpty &&
      available.every((entry) => ref.watch(entry.enabled));
});

/// Of er minstens één beschikbare integratie aan staat.
final anyIntegrationEnabledProvider = Provider<bool>((ref) {
  return ref
      .watch(availableIntegrationsProvider)
      .any((entry) => ref.watch(entry.enabled));
});
