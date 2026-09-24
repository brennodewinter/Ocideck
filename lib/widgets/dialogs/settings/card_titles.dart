// De kaarttitels op Uitbreidingen en Integraties, uit één bron.
//
// Beide tabbladen sorteren hun kaarten alfabetisch op de vertaalde titel
// (#2187). Daarvoor moet de titel bekend zijn vóór de kaart gebouwd is —
// stond hij alleen ín de kaart, dan zou er een tweede lijstje naast lopen
// dat stil kan verschillen van wat er op het scherm staat. De kaarten zelf
// halen hun titel hier vandaan, dus sorteersleutel en getoonde tekst zijn
// gegarandeerd dezelfde.
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/integration_registry.dart';
import '../../../state/module_registry.dart';

/// De titel van een modulekaart op het tabblad Uitbreidingen.
String moduleCardTitle(ModuleId id, AppLocalizations l10n) => switch (id) {
  ModuleId.infoSafety => l10n.d('Informatieveiligheid'),
  ModuleId.ai => l10n.d('AI-assistentie'),
  ModuleId.onlineStorage => l10n.d('Online opslag'),
  ModuleId.imports => l10n.d('Importeren'),
  ModuleId.procesverbetering => l10n.d('Procesverbetering'),
  ModuleId.collaboration => l10n.d('Realtime samenwerken'),
  ModuleId.videoCalls => l10n.d('Videovergaderingen'),
  ModuleId.assetRights => l10n.d('Afbeeldingsrechten'),
  ModuleId.managementsysteem => l10n.d('Managementsysteem'),
  ModuleId.libreplan => l10n.d('LibrePlan-connector'),
  // "maken" onderscheidt deze uitbreiding (eLearning-diatypes schrijven)
  // van de integratie "eLearning volgen" (cursussen afnemen) — #2186.
  ModuleId.elearning => l10n.d('eLearning maken'),
};

/// De titel van een integratiekaart — op Integraties én op de
/// inschakelkaart op Uitbreidingen, zodat beide plekken dezelfde naam
/// tonen.
String integrationCardTitle(IntegrationId id, AppLocalizations l10n) =>
    switch (id) {
      IntegrationId.openKat => l10n.d('OpenKAT'),
      IntegrationId.ociServe => l10n.d('eLearning volgen'),
    };

/// Sorteer kaarten op hun vertaalde titel: Latin-folded en kleine letters,
/// zodat diakrieten en hoofdletters de volgorde niet verstoren — dezelfde
/// sleutel als de taalkeuzelijst gebruikt.
void sortCardsByTitle(List<({String title, Widget card})> cards) {
  cards.sort(
    (a, b) => AppLocalizations.sortKey(
      a.title,
    ).compareTo(AppLocalizations.sortKey(b.title)),
  );
}
