// Het registerlicht van de optionele modules (#570).
//
// Toen de derde module aankwam was de vraag uit `info_safety_provider.dart`
// niet langer uitstelbaar: "a second module needs a real registry". Dit is het
// antwoord, en het is bewust líchter dan die zin suggereert. Elke module houdt
// zijn eigen state en zijn eigen voorkeursleutel — Informatieveiligheid draagt
// een legacy-sleutel die niet mag hernoemen, AI-assistentie leeft in
// `AiSettings`, Online opslag volgt zonder keuze de inhoud — dus een
// geparametriseerd sleutel-framework zou drie werkende patronen breken om er
// één abstract voor terug te geven. Wat er wél ontbrak was één plek die
// opsomt wélke modules er zijn en wat hun poort is, zodat het
// Uitbreidingen-tabblad en de tests niet elk hun eigen lijstje bijhouden dat
// stil uiteen kan lopen.
//
// De vaste regel die elke module deelt staat hier dan ook als contract, niet
// als code: **tonen zodra de inhoud er is.** Uitzetten mag bestaand werk nooit
// onbereikbaar maken (#648, #731, #570).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collaboration_provider.dart';
import 'info_safety_provider.dart';
import 'online_storage_provider.dart';
import 'import_module_provider.dart';
import 'procesverbetering_provider.dart';
import 'settings_provider.dart';

/// De optionele modules, in de volgorde waarin het Uitbreidingen-tabblad ze
/// toont.
enum ModuleId {
  infoSafety,
  ai,
  onlineStorage,
  imports,
  procesverbetering,
  collaboration,
}

/// Eén module in het register: wie hij is en waar zijn poorten staan.
///
/// De velden zijn concrete `Provider<bool>`-handvatten (het abstracte
/// listenable-type exporteert flutter_riverpod niet), dus elke module krijgt
/// zo nodig een klein afgeleid providertje — dat is ook meteen de plek waar
/// zijn poortregel een naam en een doc-kop heeft.
class ModuleEntry {
  const ModuleEntry({
    required this.id,
    required this.enabled,
    required this.revealed,
  });

  final ModuleId id;

  /// Of de schakelaar aan staat.
  final Provider<bool> enabled;

  /// Of de functies zichtbaar zijn: aan, óf er is al inhoud. Altijd minstens
  /// zo ruim als [enabled].
  final Provider<bool> revealed;
}

/// Of de Informatieveiligheid-schakelaar aan staat, als los handvat voor het
/// register; de poort zelf blijft [infoSafetyRevealProvider].
final infoSafetyEnabledProvider = Provider<bool>((ref) {
  return ref.watch(infoSafetyProvider.select((s) => s.enabled));
});

/// Of de AI-schakelaar aan staat (de bewaarde stand, niet het formulier).
final aiModuleEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider.select((s) => s.aiSettings.enabled));
});

/// AI-reveal op providerniveau: het tabblad bestaat zodra de module aan staat
/// óf er een backend geconfigureerd is (#731). Het instellingenvenster rekent
/// tijdens het bewerken met zijn formulier in plaats van hiermee — een
/// omgezette schakelaar moet het tabblad meteen tonen, niet pas na Opslaan —
/// maar buiten dat venster is dít de waarheid.
final aiModuleRevealProvider = Provider<bool>((ref) {
  final ai = ref.watch(settingsProvider.select((s) => s.aiSettings));
  return ai.enabled || ai.hasBackend;
});

/// Het register. Volgorde = kaartvolgorde op Uitbreidingen; de test op het
/// tabblad telt hierop, zodat een vierde module niet stil zonder kaart kan
/// blijven.
final List<ModuleEntry> moduleRegistry = [
  ModuleEntry(
    id: ModuleId.infoSafety,
    enabled: infoSafetyEnabledProvider,
    revealed: infoSafetyRevealProvider,
  ),
  ModuleEntry(
    id: ModuleId.ai,
    enabled: aiModuleEnabledProvider,
    revealed: aiModuleRevealProvider,
  ),
  ModuleEntry(
    id: ModuleId.onlineStorage,
    enabled: onlineStorageEnabledProvider,
    revealed: onlineStorageRevealProvider,
  ),
  ModuleEntry(
    id: ModuleId.imports,
    enabled: importModuleEnabledProvider,
    revealed: importModuleRevealProvider,
  ),
  ModuleEntry(
    id: ModuleId.procesverbetering,
    enabled: procesverbeteringEnabledProvider,
    revealed: procesverbeteringRevealProvider,
  ),
  ModuleEntry(
    id: ModuleId.collaboration,
    enabled: collaborationEnabledProvider,
    revealed: collaborationRevealProvider,
  ),
];
