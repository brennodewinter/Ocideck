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
  appearance(Icons.format_paint_outlined),
  presentation(Icons.slideshow_outlined),
  cockpit(Icons.speed_outlined),
  privacy(Icons.privacy_tip_outlined),
  security(Icons.shield_outlined),
  ai(Icons.smart_toy_outlined),
  checklists(Icons.checklist_outlined),
  modules(Icons.extension_outlined),
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
    SettingsSection.appearance => l10n.d('App-thema'),
    SettingsSection.presentation => l10n.d('Presentatiestijl'),
    SettingsSection.cockpit => l10n.d('Cockpit'),
    SettingsSection.privacy => l10n.d('Licentie en Privacy'),
    SettingsSection.security => l10n.d('Beveiliging'),
    SettingsSection.ai => l10n.d('AI-assistentie'),
    SettingsSection.checklists => l10n.d('Checklists'),
    SettingsSection.modules => l10n.d('Uitbreidingen'),
    SettingsSection.documentation => l10n.d('Documentatie'),
    SettingsSection.about => l10n.d('Over OciDeck'),
  };

  /// De tabbladen die als gewone navigatieknop in de zijbalk staan — alles
  /// behalve [about], dat vanuit de merkvoet wordt geopend.
  static List<SettingsSection> get navItems =>
      values.where((s) => s != SettingsSection.about).toList();
}
