// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De schil van het instellingenvenster: de zijbalk met zijn navigatieknoppen,
// de merkvoet die "Over OciDeck" opent, de kopregel met het zoekveld en de
// voetbalk met Annuleren/Opslaan. Alles wat er omheen staat, niets van wat
// erin staat.
//
// Los van settings_dialog.dart omdat dit blok als enige puur presentatie is:
// het leest de gekozen sectie en schrijft hem terug, en raakt geen van de
// instellingen zelf aan. Dat maakt het ook het enige blok dat je kunt lezen
// zonder de rest van de toestand erbij te houden.
//
// Let op `_rebuild` in plaats van `setState`: dit is een extension, en setState
// is protected — vandaar dat de klasse die helper heeft.
part of '../settings_dialog.dart';

extension _SettingsChrome on _SettingsDialogState {
  /// De breedte van de zijbalk bij de standaard tekstgrootte.
  static const double _sidebarWidth = 234;

  /// Hoeveel de zijbalk hoogstens meegroeit met de tekstschaal.
  ///
  /// Eén-op-één meegroeien zou bij 200% op 468 px uitkomen en het venster
  /// opeten — dan is de navigatie leesbaar en de inhoud niet. Anderhalf keer
  /// haalt de meeste labels heel; wat dan nog niet past breekt over twee
  /// regels af in [_navItem]. Verticale ruimte is hier goedkoper dan
  /// horizontale, want de lijst scrolt toch al.
  static const double _sidebarMaxGrowth = 1.5;

  Widget _sidebar(AppLocalizations l10n) {
    // Bij schaal 1.0 exact 234, zodat er voor wie niets instelt niets verandert.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Container(
      // Benoemd zodat een test de zijbalk kan aanwijzen zonder op een breedte
      // of een kleurverloop te moeten raden — die veranderen, de rol niet.
      key: const Key('settings-sidebar'),
      width: _sidebarWidth * scale.clamp(1.0, _sidebarMaxGrowth),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.navySoft, AppTheme.navy],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.blue500, AppTheme.accent],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.settings_suggest_outlined,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.t('settings'),
                    // Ook de kop, en om dezelfde reden: "Einstellungen" past bij
                    // 17px al niet naast het logo op één regel.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // "Over OciDeck" ontbreekt hier met opzet: dat tabblad wordt vanuit
          // de merkvoet hieronder geopend. De lijst scrollt, zodat extra
          // tabbladen de zijbalk nooit doen overlopen; de voet blijft staan.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in SettingsSection.navItems(
                    infoSafetyRevealed: ref.watch(infoSafetyRevealProvider),
                    hasChecklists: ref
                        .watch(settingsProvider)
                        .customChecklists
                        .isNotEmpty,
                    // Uit het formulier en niet uit de opgeslagen instelling:
                    // zet je de module op Uitbreidingen aan, dan hoort het
                    // tabblad meteen te verschijnen en niet pas na Opslaan.
                    aiRevealed: _ai.revealsTab,
                  ))
                    _navItem(section, l10n),
                ],
              ),
            ),
          ),
          _aboutFooter(SettingsSection.about.label(l10n)),
        ],
      ),
    );
  }

  /// The branded footer at the bottom of the sidebar. Doubles as the entry
  /// point to the "Over OciDeck" pane: tapping it selects that tab and the
  /// footer lights up like a selected nav item.
  Widget _aboutFooter(String aboutLabel) {
    final selected = _selectedTab == SettingsSection.about;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => _rebuild(() => _selectedTab = SettingsSection.about),
          child: Tooltip(
            message: aboutLabel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.13)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // EU-yellow recolour of the logo, so it reads on the dark
                  // sidebar without a backing plate.
                  Semantics(
                    label: context.l10n.d('OciDeck'),
                    image: true,
                    child: Image.asset(
                      'assets/images/ocideck-logo-eu.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.d('OciDeck'),
                      style: TextStyle(
                        // EU-vlaggeel: leesbaar op de donkere/EU-blauwe
                        // zijbalk, passend bij het geel-hertinte logo ernaast.
                        color: AppTheme.amberVivid,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(SettingsSection section, AppLocalizations l10n) {
    final selected = _selectedTab == section;
    final icon = section.icon;
    final label = section.label(l10n);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => _rebuild(() => _selectedTab = section),
          child: Tooltip(
            message: label,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.13)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 3,
                    height: 18,
                    margin: const EdgeInsets.only(right: 11),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.blue400 : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Icon(
                    icon,
                    size: 19,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.62),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // Twee regels in plaats van afkappen. Bij 200% — een schaal
                    // die dit product zelf aanbiedt als WCAG 1.4.4-instelling —
                    // werden de labels "Einste…", "App-De…", "Präsent…": een
                    // navigatie waar je niet meer op kunt navigeren. Een tooltip
                    // eromheen vangt het uiterste geval, maar de tooltip is het
                    // vangnet en niet de oplossing; die moet je immers eerst
                    // ontdekken.
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.72),
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contentHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 18, 14, 16),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: const Border(bottom: BorderSide(color: AppTheme.iceBlue)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              // Begrensd, anders groeit de kop bij grote tekst ongelimiteerd en
              // duwt hij de inhoud en de opslaanknop uit het venster. Twee
              // regels voor een tabbladtitel is ruim.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
                letterSpacing: 0.1,
              ),
            ),
          ),
          _settingsSearchField(),
          IconButton(
            tooltip: context.l10n.t('cancel'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
            color: AppTheme.slate400,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _footerBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: const Border(top: BorderSide(color: AppTheme.iceBlue)),
      ),
      // Wrap in plaats van Row: bij 200% tekstschaal passen "Abbrechen" en
      // "Einstellungen speichern" niet meer naast elkaar en liep deze balk 261
      // pixels buiten het venster — met de opslaanknop aan de kant die
      // wegviel. Dan stapelen ze liever onder elkaar.
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(l10n.t('saveSettings')),
          ),
        ],
      ),
    );
  }

  Widget _tabBody(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 24, 22),
      child: child,
    );
  }
}
