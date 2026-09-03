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
            'Deze instellingen bepalen wat OciDeck vanaf het internet mag laden en welke sporen op dit apparaat achterblijven. Ze staan los van je privacyverklaring en toestemming, die je bij "Privacy en classificatie" vindt.',
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
        _privacyStrictSeverity(l10n),
        const DisabledPrivacyRules(),
        const SetAsidePrivacyFindings(),
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
        // De twee CVE-blokken horen bij de module Informatieveiligheid: de
        // enige plek waar een CVE-opzoeking te openen is, is de bevindingen-
        // editor, en die zit achter de module. Met de module uit bood dit
        // tabblad dus aan om een online opzoeking aan te zetten die nergens te
        // bereiken is — en op desktop om honderden megabytes binnen te halen
        // voor een zoekfunctie die niet opengaat (#648).
        //
        // Tonen zodra de inhoud er is: wie de lokale database al heeft
        // gedownload, moet hem kunnen zien en weghalen. Anders laat een
        // schakelaar stilzwijgend een gigabyte achter zonder route terug.
        if (ref.watch(infoSafetyRevealProvider) ||
            ref.watch(localCveProvider).stats != null) ...[
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
        ],
        const SizedBox(height: 20),
        _diskTracesSection(l10n),
      ],
    );
  }

  /// Wat OciDeck op dit apparaat achterlaat, en de knoppen om het weg te halen.
  ///
  /// Bij elkaar in één blok, want los van elkaar zijn het drie weetjes en samen
  /// zijn ze het antwoord op één vraag: wat weet deze machine straks nog van
  /// mij? Dat is de vraag van iemand die zijn laptop inlevert, of die de app op
  /// een gedeelde machine heeft gebruikt.
  Widget _diskTracesSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('Sporen op dit apparaat')),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            l10n.d(
              'OciDeck bewaart naast je instellingen ook een recente lijst en, bij een crash, een herstelbestand met de volledige inhoud van je presentatie. Niets daarvan verlaat dit apparaat, maar het staat er wel — in platte tekst, beschermd door je account op dit besturingssysteem en niet meer dan dat.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        _traceRow(
          l10n.d('Recent geopende presentaties'),
          l10n.d(
            'De lijst bewaart het volledige pad en de classificatie van elk deck dat open is geweest — samen een gegeven over waar je aan werkt en voor wie.',
          ),
          l10n.d('Recente lijst wissen'),
          Icons.history_toggle_off,
          _clearRecentFiles,
        ),
        _traceRow(
          l10n.d('Herstelbestanden'),
          l10n.d(
            'Crash-herstelbestanden bevatten de volledige inhoud van je presentaties in platte tekst. Ze worden na 7 dagen automatisch opgeruimd, en bij een nette afsluiting meteen.',
          ),
          l10n.d('Herstelbestanden nu wissen'),
          Icons.delete_sweep_outlined,
          _clearRecoveryFiles,
        ),
        _traceRow(
          l10n.d('Alles terugzetten'),
          l10n.d(
            'Wist elke instelling, de recente lijst, de herstelbestanden, de git-werkkopieën en de wachtwoorden in je sleutelbos. Je presentaties blijven staan: die zijn van jou, niet van OciDeck.',
          ),
          l10n.d('Zet alles terug naar de begintoestand'),
          Icons.restart_alt,
          _resetEverything,
          destructive: true,
        ),
      ],
    );
  }

  Widget _traceRow(
    String title,
    String explanation,
    String action,
    IconData icon,
    Future<void> Function() onPressed, {
    bool destructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            explanation,
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => onPressed(),
            icon: Icon(icon, size: 16),
            label: Text(action),
            style: destructive
                ? OutlinedButton.styleFrom(foregroundColor: AppTheme.dangerFg)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _clearRecentFiles() async {
    final l10n = context.l10n;
    final had = ref.read(settingsProvider).recentFiles.length;
    await ref.read(settingsProvider.notifier).clearRecentFiles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          had == 0
              ? l10n.d('De recente lijst was al leeg.')
              : '$had ${l10n.d('vermelding(en) uit de recente lijst gewist.')}',
        ),
      ),
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

  /// Terug naar de begintoestand — met twee drempels, niet één.
  ///
  /// De eerste is de gewone bevestiging. De tweede is wachtend git-werk: dat
  /// bestaat nergens anders, en een knop die "alles terugzetten" heet mag daar
  /// niet stilzwijgend overheen. Wie dat niet wil kwijtraken, sluit eerst zijn
  /// werk af en komt terug.
  Future<void> _resetEverything() async {
    final l10n = context.l10n;
    final notifier = ref.read(settingsProvider.notifier);
    final pending = await notifier.pendingCommitCount();
    if (!mounted) return;
    final confirmed = await _confirmReset(l10n, pending);
    if (!confirmed || !mounted) return;
    final done = await notifier.resetToInitialState(discardPendingWork: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? l10n.d('Alles is teruggezet naar de begintoestand.')
              : l10n.d('Terugzetten is niet gelukt.'),
        ),
      ),
    );
    if (!done || !mounted) return;
    // Niet "geannuleerd": het venster sluit omdat alles wat erin stond zojuist
    // is gewist. Zonder deze vlag schrijft `_restoreLanguageIfDiscarded` de taal
    // van vóór het openen terug en is de begintoestand meteen weer bezoedeld.
    _saved = true;
    Navigator.pop(context);
  }

  Future<bool> _confirmReset(AppLocalizations l10n, int pending) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('Alles terugzetten naar de begintoestand?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Je instellingen, de recente lijst, de herstelbestanden, de git-werkkopieën en de opgeslagen wachtwoorden worden gewist. Dit kan niet ongedaan worden gemaakt. Je presentaties blijven staan.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            if (pending > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$pending ${l10n.d('wijziging(en) zijn nog niet naar een git-server gestuurd en bestaan alleen op dit apparaat. Ook die gaan weg.')}',
                style: TextStyle(fontSize: 12.5, color: AppTheme.dangerFg),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.d('Annuleren')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.d('Alles terugzetten')),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// De beeldcontrole-schakelaar.
  ///
  /// Uitgeklapt in een eigen methode omdat de toelichting lang is — en dat is
  /// met opzet: dit is de enige controle die niet naar tekst maar naar mensen
  /// kijkt, en de gebruiker hoort te lezen wat er wél en niet gebeurt voordat
  /// hij hem aan laat staan.
  ///
  /// Grijs zolang de hoofdschakelaar uit staat: een deelcontrole van een
  /// uitgezette controle aan kunnen zetten is een knop die liegt.
  ///
  /// Op web draait de controle helemaal niet — gezichtsherkenning is een
  /// systeembibliotheek via FFI, die de browser niet heeft. De schakelaar staat
  /// daar uit en uitgeschakeld, met de reden erbij: een aangevinkte schakelaar
  /// die belooft dat "elke afbeelding lokaal wordt doorgerekend" terwijl er
  /// niets gebeurt, is precies de knop die liegt — en juist bij een
  /// privacycontrole mag dat niet.
  Widget _privacyImageFaceDetection(AppLocalizations l10n) {
    if (isWebPlatform) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          l10n.d('Afbeeldingen nakijken op herkenbare gezichten'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d(
            'Deze controle draait niet in de webversie: gezichtsherkenning vergt een systeembibliotheek die de browser niet heeft. Gebruik de desktopversie om afbeeldingen op gezichten na te kijken.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        value: false,
        onChanged: null,
      );
    }
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

  /// De strenge stand (OCIWACHT §7).
  ///
  /// De ondertitel noemt het gevolg en niet de instelling. "Behandel zeker als
  /// fout" zegt een gebruiker niets; "een export kan geblokkeerd worden" wel, en
  /// dát is wat er verandert. Wie de blokkade juist wíl, herkent zich er ook in.
  Widget _privacyStrictSeverity(AppLocalizations l10n) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        l10n.d('Zekere vondsten als fout behandelen'),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        l10n.d(
          'Normaal is een zekere vondst — een BSN, een IBAN, een e-mailadres — een waarschuwing die je kunt negeren. Aan maakt er een fout van, en dan kan de export erop blokkeren als je die instelling ook aan hebt staan. Bedoeld voor omgevingen waar zulke gegevens er echt niet doorheen mogen. Onzekere vondsten blijven een waarschuwing.',
        ),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      value: ref.watch(settingsProvider.select((s) => s.privacyStrictSeverity)),
      onChanged:
          ref.watch(settingsProvider.select((s) => s.privacyChecksEnabled))
          ? (value) => ref
                .read(settingsProvider.notifier)
                .setPrivacyStrictSeverity(value)
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

    return _settingFieldRow(
      context,
      label: Text(
        l10n.d('Bij onafgehandelde persoonsgegevens'),
        style: const TextStyle(fontSize: 13),
      ),
      control: DropdownButtonHideUnderline(
        child: DropdownButton<PrivacyExportGate>(
          value: gate,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(6),
          style: TextStyle(fontSize: 12, color: AppTheme.ink),
          items: [
            for (final g in PrivacyExportGate.values)
              DropdownMenuItem(
                value: g,
                child: Text(label(g), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) {
              ref.read(settingsProvider.notifier).setPrivacyExportGate(v);
            }
          },
        ),
      ),
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
            'Eén per regel: je naam, e-mailadres, telefoonnummer of het domein van je organisatie. Wat hier staat wordt niet gemeld en niet geredigeerd — het is de afzender, geen bevinding. Een domein (example.org) dekt elk adres eronder.',
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
            hintText: l10n.d('naam@example.org\nexample.org'),
            hintStyle: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setPrivacyOwnIdentity(value),
        ),
      ],
    );
  }
}
