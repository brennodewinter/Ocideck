// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (security tab); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsSecurity on _SettingsDialogState {
  Widget _securityTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'Deze instellingen bepalen wat OciDeck vanaf het internet mag laden en welke sporen op dit apparaat achterblijven. Ze staan los van je privacyverklaring en toestemming, die je bij "Licentie en Privacy" vindt.',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Privacycontrole')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Waarschuw bij mogelijke persoonsgegevens'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Leest je dia\'s na op identificatienummers, contactgegevens en andere privacygevoelige gegevens, en meldt ze bij de kwaliteitscontrole. Dit gebeurt volledig op dit apparaat; er wordt niets verstuurd. Het is een hulpmiddel, geen garantie: tekst in afbeeldingen en gegevens zonder herkenbaar patroon blijven buiten beeld.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          value: ref.watch(
            settingsProvider.select((s) => s.privacyChecksEnabled),
          ),
          onChanged: (value) => ref
              .read(settingsProvider.notifier)
              .setPrivacyChecksEnabled(value),
        ),
        _disabledPrivacyRules(l10n),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Online media')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Online media toestaan'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Sta het live laden toe van afbeeldingen en video\'s via een URL en van YouTube/Vimeo-embeds. Standaard uit voor je privacy en veiligheid.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          value: ref.watch(settingsProvider.select((s) => s.allowRemoteMedia)),
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setAllowRemoteMedia(value),
        ),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('CVE opzoeken')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('CVE opzoeken (online)'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Sta toe om in de bevinding-editor online in CVE\'s te zoeken via een NVD-mirror. Standaard uit; vereist ook je toestemming en werkt alleen op desktop.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          value: ref.watch(settingsProvider.select((s) => s.allowCveLookup)),
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setAllowCveLookup(value),
        ),
        if (ref.watch(settingsProvider.select((s) => s.allowCveLookup)))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextFormField(
              initialValue: ref.read(settingsProvider).cveApiBaseUrl,
              decoration: InputDecoration(
                labelText: l10n.d('CVE-mirror (basis-URL)'),
                hintText: AppSettings.defaultCveApiBaseUrl,
                isDense: true,
              ),
              onFieldSubmitted: (value) =>
                  ref.read(settingsProvider.notifier).setCveApiBaseUrl(value),
            ),
          ),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Herstelbestanden')),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.d(
              'Crash-herstelbestanden bevatten de volledige inhoud van je presentaties in platte tekst. Ze worden na 7 dagen automatisch opgeruimd; hier kun je ze direct wissen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _clearRecoveryFiles,
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: Text(l10n.d('Herstelbestanden nu wissen')),
          ),
        ),
      ],
    );
  }

  Future<void> _clearRecoveryFiles() async {
    final l10n = context.l10n;
    final removed = await RecoveryService().discardAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? l10n.d('Er waren geen herstelbestanden.')
              : '$removed ${l10n.d('herstelbestand(en) gewist.')}',
        ),
      ),
    );
  }

  /// De uitgezette detectieregels, als chips die je weer aanzet.
  ///
  /// Dit is de tegenkant van de "nooit meer melden"-knop in het kwaliteitspaneel:
  /// wat je daar wegklikt, kun je hier terugzetten. Zonder die tegenkant is
  /// uitzetten een eenrichtingsstraat, en dan durft niemand het te doen.
  ///
  /// Standaard staan hier de drie zwaarste art. 9-categorieën in — politiek,
  /// etniciteit en seksuele geaardheid. Niet omdat ze onbelangrijk zijn, maar
  /// omdat hun trefwoorden op gewone zakelijke slides te vaak voorkomen. Wie in
  /// die hoek werkt, zet ze hier met één tik aan.
  Widget _disabledPrivacyRules(AppLocalizations l10n) {
    final disabled = ref.watch(
      settingsProvider.select((s) => s.privacyDisabledRules),
    );
    if (disabled.isEmpty) return const SizedBox.shrink();

    final sorted = disabled.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Uitgezette regels. Deze worden niet gemeld en niet geredigeerd. Tik om weer aan te zetten.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final rule in sorted)
                InputChip(
                  label: Text(
                    privacyRuleLabel(l10n, rule),
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add, size: 14),
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .setPrivacyRuleEnabled(rule, true),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
