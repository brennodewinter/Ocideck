// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De inhoudsopgave van het instellingenvenster: welke tabbladen er zijn, in
// welke volgorde ze in de zijbalk staan, welk pictogram en welk opschrift erbij
// hoort. Eén lijst, want vóór dit bestand stonden de opschriften, de
// pictogrammen en de tabbladinhoud in drie losse lijsten die op volgnummer
// gelijk moesten lopen — een tabblad ertussen schuiven verschoof stilzwijgend
// de betekenis van elk nummer daarna, inclusief de 47 verwijzingen in de
// zoekindex.
//
// Daarom wijst alles hier naar een naam en niet naar een getal. Een tabblad
// verplaatsen is nu het verplaatsen van één regel in deze enum; er is geen
// nummer meer dat kan verschuiven.
part of '../settings_dialog.dart';

/// Een tabblad in de zijbalk van de instellingen.
///
/// De declaratievolgorde hieronder *is* de volgorde in de zijbalk. [about] moet
/// als laatste blijven staan: dat tabblad hangt niet in de gewone navigatielijst
/// maar onder de merkvoet onderaan de zijbalk.
enum SettingsSection {
  general(Icons.tune),
  storage(Icons.inventory_2_outlined),
  collaboration(Icons.groups_outlined),
  appearance(Icons.format_paint_outlined),
  presentation(Icons.slideshow_outlined),
  privacy(Icons.privacy_tip_outlined),
  security(Icons.shield_outlined),
  ai(Icons.smart_toy_outlined),
  libreplan(Icons.cloud_download_outlined),
  checklists(Icons.checklist_outlined),
  modules(Icons.extension_outlined),
  integrations(Icons.hub_outlined),
  documentation(Icons.menu_book_outlined),
  about(Icons.info_outline);

  const SettingsSection(this.icon);

  /// Het pictogram in de zijbalk.
  final IconData icon;

  /// Het opschrift in de zijbalk. Dezelfde bronstring als de zoekindex
  /// gebruikt, zodat een treffer in élke taal de kop aanwijst die op het scherm
  /// staat.
  String label(AppLocalizations l10n) => switch (this) {
    SettingsSection.general => l10n.t('settingsGeneral'),
    SettingsSection.storage => l10n.d('Opslag'),
    SettingsSection.collaboration => l10n.d('Samenwerken'),
    SettingsSection.appearance => l10n.d('Uiterlijk van de app'),
    SettingsSection.presentation => l10n.d('Uiterlijk van dia\'s'),
    SettingsSection.privacy => l10n.d('Privacy en classificatie'),
    SettingsSection.security => l10n.d('Beveiliging'),
    SettingsSection.ai => l10n.d('AI-assistentie'),
    SettingsSection.libreplan => l10n.d('LibrePlan-connector'),
    SettingsSection.checklists => l10n.d('Checklists'),
    SettingsSection.modules => l10n.d('Uitbreidingen'),
    SettingsSection.integrations => l10n.d('Integraties'),
    SettingsSection.documentation => l10n.d('Documentatie'),
    SettingsSection.about => l10n.d('Over OciDeck'),
  };

  /// De tabbladen die als gewone navigatieknop in de zijbalk staan — alles
  /// behalve [about], dat vanuit de merkvoet wordt geopend.
  ///
  /// [infoSafetyRevealed] is of de module Informatieveiligheid aan staat, en
  /// [hasChecklists] of de gebruiker al eigen checklists heeft.
  ///
  /// **Waarom die tweede.** De checklists-tab bouwt sjablonen die maar één
  /// afnemer hebben: het `checklist`-slidetype, en dat zit achter de module. Met
  /// de module uit kon je dus sjablonen maken, benoemen, vullen — en ze nergens
  /// laden. Elf tabbladen, en één ervan deed niets (#648).
  ///
  /// Maar verbergen op alléén de moduleschakelaar zou werk onbereikbaar maken
  /// dat er al ligt. Vandaar de vaste regel van dit project: **tonen zodra de
  /// inhoud er is.** Wie sjablonen heeft gemaakt en daarna de module uitzet,
  /// ziet ze nog steeds staan en kan ze weghalen. Dezelfde truc als bij de
  /// MIAUW-velden in `presentation_info_dialog.dart`.
  /// [aiRevealed] is dezelfde afweging voor AI-assistentie (#731): die is een
  /// module geworden en woont onder Uitbreidingen. Wie hem uit laat, ziet er
  /// niets van — behalve wanneer er al een backend is ingevuld, want ook daar
  /// geldt "tonen zodra de inhoud er is".
  /// [integrationsAvailable] is of dit platform überhaupt een integratie kan
  /// gebruiken (`anyIntegrationAvailableProvider`). Sinds #1158 leeft de
  /// schakelaar per integratie óp het tabblad Integraties zelf, dus het tabblad
  /// hoort zichtbaar te zijn zodra een koppeling beschikbaar is — anders is er
  /// geen plek om ze aan te zetten. Op web valt de enige integratie (OpenKAT)
  /// weg omdat haar mapkiezer daar niet bestaat, en dan is een leeg tabblad
  /// "Integraties" geen informatie maar ruis.
  static List<SettingsSection> navItems({
    required bool infoSafetyRevealed,
    required bool hasChecklists,
    required bool aiRevealed,
    required bool libreplanRevealed,
    required bool integrationsAvailable,
    required bool collaborationRevealed,
  }) => values.where((s) {
    if (s == SettingsSection.about) return false;
    if (s == SettingsSection.checklists) {
      return infoSafetyRevealed || hasChecklists;
    }
    if (s == SettingsSection.ai) return aiRevealed;
    if (s == SettingsSection.libreplan) return libreplanRevealed;
    if (s == SettingsSection.collaboration) return collaborationRevealed;
    if (s == SettingsSection.integrations) return integrationsAvailable;
    return true;
  }).toList();
}
