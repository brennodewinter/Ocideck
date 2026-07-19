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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Leest je dia\'s na op identificatienummers, contactgegevens en andere privacygevoelige gegevens, en meldt ze bij de kwaliteitscontrole. Dit gebeurt volledig op dit apparaat; er wordt niets verstuurd. Het is een hulpmiddel, geen garantie: tekst in afbeeldingen en gegevens zonder herkenbaar patroon blijven buiten beeld.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.d(
                  'De controle garandeert niet dat alles wordt gevonden; ze verkleint de kans dat er persoonsgegevens onbedoeld uitlekken.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
            ],
          ),
          value: ref.watch(
            settingsProvider.select((s) => s.privacyChecksEnabled),
          ),
          onChanged: (value) => ref
              .read(settingsProvider.notifier)
              .setPrivacyChecksEnabled(value),
        ),
        _privacyImageFaceDetection(l10n),
        _disabledPrivacyRules(l10n),
        _privacyRegions(l10n),
        const SizedBox(height: 10),
        _privacyExportGate(l10n),
        const SizedBox(height: 10),
        _privacyOwnIdentity(l10n),
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
        Row(
          children: [
            _sectionTitle(l10n.d('CVE opzoeken')),
            const SizedBox(width: 8),
            // De badge blokkeert niets — hij maakt zichtbaar wát er weglekt als
            // je dit aanzet: niet dát je zoekt, maar wáárnaar.
            PrivacyBadge(
              tooltip: l10n.d(
                'Je zoekterm gaat naar de ingestelde CVE-mirror, en als die niets vindt ook naar ENISA en MITRE. Wie die servers beheert, kan daaruit afleiden naar welk specifiek lek je zoekt — en dus welk lek je onderzoekt.',
              ),
            ),
          ],
        ),
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
        // Alleen op desktop: op het web is er geen bestandssysteem voor een
        // index van honderden megabytes, en een download van 550 MB hoort niet
        // in een browsertab. Dan tonen we de sectie niet, in plaats van een
        // knop die niets kan.
        if (localCveSupported) ...[
          const SizedBox(height: 20),
          _localCveSection(l10n),
        ],
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
  /// De beeldcontrole-schakelaar.
  ///
  /// Uitgeklapt in een eigen methode omdat de toelichting lang is — en dat is
  /// met opzet: dit is de enige controle die niet naar tekst maar naar mensen
  /// kijkt, en de gebruiker hoort te lezen wat er wél en niet gebeurt voordat
  /// hij hem aan laat staan.
  ///
  /// Grijs zolang de hoofdschakelaar uit staat: een deelcontrole van een
  /// uitgezette controle aan kunnen zetten is een knop die liegt.
  Widget _privacyImageFaceDetection(AppLocalizations l10n) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        l10n.d('Afbeeldingen nakijken op herkenbare gezichten'),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        l10n.d(
          'Een afbeelding waarop iemand herkenbaar staat is een persoonsgegeven, ook zonder naam erbij. Dit is de zwaarste controle: elke afbeelding wordt lokaal doorgerekend. Er wordt geteld of er een gezicht op staat — nooit wie het is, en er wordt niets opgeslagen.',
        ),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      value: ref.watch(
        settingsProvider.select((s) => s.privacyImageFaceDetection),
      ),
      onChanged:
          ref.watch(settingsProvider.select((s) => s.privacyChecksEnabled))
          ? (value) => ref
                .read(settingsProvider.notifier)
                .setPrivacyImageFaceDetection(value)
          : null,
    );
  }

  /// De landpakketten (OCIWACHT §5.7).
  ///
  /// Alleen zichtbaar wanneer de privacycontrole draait: een lijst regio's onder
  /// een uitgezette controle suggereert dat er iets te kiezen valt.
  ///
  /// De uitleg eronder is geen bijzaak. "Heel Europa" klinkt als de ruizige
  /// keuze, en dat is het hier juist niet — de meeste Europese persoonsnummers
  /// zijn zelfvaliderend, en een checksum kóst geen precisie maar wínt precisie.
  /// Zonder die zin zet een voorzichtige gebruiker pakketten uit die hem niets
  /// kosten, en mist hij gegevens die er wél toe doen.
  Widget _privacyRegions(AppLocalizations l10n) {
    if (!ref.watch(settingsProvider.select((s) => s.privacyChecksEnabled))) {
      return const SizedBox.shrink();
    }
    final active = ref.watch(settingsProvider.select((s) => s.privacyRegions));
    final sorted = allPrivacyRegions.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Landpakketten voor identificatienummers'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.d(
              'Nummers als het BSN of het PESEL zijn landgebonden. Heel Europa staat aan omdat de meeste van die nummers een controlegetal hebben: die aanzetten kost vrijwel geen valse meldingen. IBAN, e-mail, geheimen en paspoortstroken staan hier los van en worden altijd nagekeken.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final region in sorted)
                FilterChip(
                  label: Text(
                    region.toUpperCase(),
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  selected: active.contains(region),
                  onSelected: (value) => ref
                      .read(settingsProvider.notifier)
                      .setPrivacyRegionEnabled(region, value),
                ),
            ],
          ),
        ],
      ),
    );
  }

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

  /// Wat er bij exporteren gebeurt met bevindingen waarvoor nog geen keuze is
  /// gemaakt.
  ///
  /// Waarschuwen is de standaard, want een gate die *altijd* blokkeert is een
  /// gate die wordt weggeklikt. De harde blokkade is er voor omgevingen waar het
  /// een procedure-eis is — en die keuze hoort bij de organisatie, niet bij ons.
  Widget _privacyExportGate(AppLocalizations l10n) {
    final gate = ref.watch(settingsProvider.select((s) => s.privacyExportGate));
    String label(PrivacyExportGate g) => switch (g) {
      PrivacyExportGate.off => l10n.d('Niets doen'),
      PrivacyExportGate.warn => l10n.d('Waarschuwen vóór export'),
      PrivacyExportGate.block => l10n.d('Export blokkeren'),
    };

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.d('Bij onafgehandelde persoonsgegevens'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<PrivacyExportGate>(
            value: gate,
            isDense: true,
            borderRadius: BorderRadius.circular(6),
            style: TextStyle(fontSize: 12, color: AppTheme.ink),
            items: [
              for (final g in PrivacyExportGate.values)
                DropdownMenuItem(value: g, child: Text(label(g))),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(settingsProvider.notifier).setPrivacyExportGate(v);
              }
            },
          ),
        ),
      ],
    );
  }

  /// Je eigen gegevens — die zijn geen bevinding maar de afzender.
  ///
  /// Dit is in de praktijk de grootste vals-positieven-bron van de hele scanner:
  /// je naam op de titelslide, je adres in de footer, je nummer op de
  /// contactslide. Zonder deze lijst vuurt vrijwel élk deck onterecht, en wel op
  /// de ene slide die er altijd in zit.
  ///
  /// Bewust een lijst en geen slimmigheid: een heuristiek die probeert te raden
  /// wie de auteur is, zit er soms naast — en dan onderdrukt hij juist wél een
  /// echte bevinding.
  Widget _privacyOwnIdentity(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.d('Je eigen gegevens'), style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 2),
        Text(
          l10n.d(
            'Eén per regel: je naam, e-mailadres, telefoonnummer of het domein van je organisatie. Wat hier staat wordt niet gemeld en niet geredigeerd — het is de afzender, geen bevinding. Een domein (politie.nl) dekt elk adres eronder.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: ref.read(settingsProvider).privacyOwnIdentity,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: 'brenno@dewinter.com\ndewinter.com',
            hintStyle: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setPrivacyOwnIdentity(value),
        ),
      ],
    );
  }
}
