// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

class _WelcomeScreen extends ConsumerWidget {
  const _WelcomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final recentFiles = ref.watch(
      settingsProvider.select((s) => s.recentFiles),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final hub = _welcomeHub(
            context,
            ref,
            theme,
            palette,
            l10n,
            recentFiles,
            constraints,
          );
          if (constraints.maxWidth >= 820) return hub;
          return SingleChildScrollView(child: hub);
        },
      ),
    );
  }

  Widget _welcomeHub(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AppPalette palette,
    AppLocalizations l10n,
    List<RecentFile> recentFiles,
    BoxConstraints viewport,
  ) {
    final wide = viewport.maxWidth >= 820;
    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 340, child: _brandPanel(context, theme, l10n)),
              Expanded(child: _actionsPanel(context, ref, l10n)),
              if (recentFiles.isNotEmpty)
                SizedBox(
                  width: 300,
                  child: _recentFilesPanel(
                    context,
                    ref,
                    theme,
                    palette,
                    l10n,
                    recentFiles,
                  ),
                ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 400, child: _brandPanel(context, theme, l10n)),
              SizedBox(height: 520, child: _actionsPanel(context, ref, l10n)),
              if (recentFiles.isNotEmpty)
                SizedBox(
                  height: 360,
                  child: _recentFilesPanel(
                    context,
                    ref,
                    theme,
                    palette,
                    l10n,
                    recentFiles,
                  ),
                ),
            ],
          );
    // De voettekstband loopt onder de héle hub door — de streep uit het onderste
    // gedeelte 1-op-1 doorgetrokken over alle kolommen. De stille links staan
    // links, de Vigilis-credit rechtsonder, dus onder de rechterkolom (en op de
    // rechterrand als die kolom er niet is). Eén band i.p.v. een streep per
    // kolom, want kolomvoeten van ongelijke hoogte zouden niet op één lijn
    // liggen.
    final footer = _welcomeFooter(context, l10n, palette);
    return wide
        ? SizedBox(
            width: double.infinity,
            height: viewport.maxHeight,
            child: Column(
              children: [
                Expanded(child: body),
                footer,
              ],
            ),
          )
        : Column(mainAxisSize: MainAxisSize.min, children: [body, footer]);
  }

  /// De doorlopende voettekstband onder alle kolommen: de streep plus de stille
  /// links (links) en de Vigilis-sponsorvermelding (rechtsonder). Los van de
  /// panelen erboven zodat de streep over de volle breedte loopt en de credit op
  /// de rechterrand valt.
  Widget _welcomeFooter(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette palette,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: _footerLinks(context, l10n, palette),
          ),
        ],
      ),
    );
  }

  Widget _brandPanel(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    // Het merk in EU-geel — de merkkleur — met een terugval op EU-blauw als het
    // geel te weinig contrast heeft tegen de (thema-afhankelijke) paneel-
    // achtergrond, bijvoorbeeld een licht profiel waar het gele merk zou
    // wegvallen. Gemeten op de linksboven-hoek van het verloop, waar het logo
    // staat.
    const euYellow = AppTheme.amberVivid; // #FFCC00
    const euBlue = AppTheme.blueVivid; // #003399
    final logoBackground = Color.alphaBlend(
      theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
      theme.colorScheme.surfaceContainerLowest,
    );
    // WCAG-contrast (grafiek/groot: 3:1) tussen het gele merk en de
    // paneelachtergrond; valt het daaronder, dan EU-blauw. Inline gerekend met
    // computeLuminance zodat de app_shell-bibliotheek geen extra import nodig
    // heeft.
    final yellowLum = euYellow.computeLuminance();
    final bgLum = logoBackground.computeLuminance();
    final hi = yellowLum > bgLum ? yellowLum : bgLum;
    final lo = yellowLum > bgLum ? bgLum : yellowLum;
    final logoInk = (hi + 0.05) / (lo + 0.05) >= 3.0 ? euYellow : euBlue;
    return Container(
      // Bottom inset (14) geeft de welkomtekst lucht boven de doorlopende
      // voettekststreep die onder alle kolommen loopt ([_welcomeFooter]); de
      // versietag is inmiddels naar die voettekst verhuisd.
      padding: const EdgeInsets.fromLTRB(34, 34, 34, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
            theme.colorScheme.surface,
          ],
        ),
      ),
      // Bij 200% interface-tekst (WCAG-plafond) groeien de kop en de Markdown-
      // belofte tot voorbij de paneelhoogte. De Column met [Spacer] mag dan niet
      // overlopen — die regressie glipte via #1146 ongetoetst op main (RenderFlex
      // +266px bij 200% tekst). Scroll-wanneer-het-niet-past, met behoud van de
      // "logo boven, welkomtekst onder"-verdeling zolang het wél past
      // (minHeight = paneelhoogte + IntrinsicHeight laten de [Spacer] werken).
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Horizontaal gecentreerd in de baan: de Column houdt
                  // `CrossAxisAlignment.start` aan voor de welkomtekst eronder,
                  // maar het logo zelf hoort in het midden van de eerste baan,
                  // niet tegen de linkerrand. De [Align] rekt over de volle
                  // baanbreedte en zet het merk in het midden.
                  Align(
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      label: l10n.d('OciDeck'),
                      image: true,
                      // No plate behind the mark. The dark logo asset is an alpha mask
                      // (transparent ground, ink = coverage), so `srcIn` paints just the
                      // mark in [logoInk] and it reads directly on the gradient in either
                      // theme instead of sitting in a white card. Hover wisselt de inkt
                      // naar de 'andere' Europese kleur: blauw → geel, geel → Italiaans
                      // groen (zie [_HoverHueLogo]).
                      child: _HoverHueLogo(baseInk: logoInk, size: 170),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l10n.d('Welkom bij OciDeck'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.d(
                      'Presentaties die gewone Markdown-bestanden blijven: leesbaar, doorzoekbaar en te openen met elke editor.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
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

  Widget _actionsPanel(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    // Alleen de knoppenkolom; de links en de Vigilis-credit zijn naar de
    // doorlopende voettekstband onder de hele hub verhuisd ([_welcomeFooter]).
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 20),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _startColumn(context, ref, l10n),
            ),
          ),
        ),
      ),
    );
  }

  /// De handelingen waarmee iemand aan een presentatie begint. Eén duidelijke
  /// primaire actie, daarna pas de verschillende manieren om bestaand werk te
  /// openen; de merkbelofte staat in het paneel ernaast.
  List<Widget> _startColumn(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    // Eén gedeelde knopvorm en -uitlijning voor de hele startkolom. De inhoud
    // (icoon + label) staat links uitgelijnd, op dezelfde linkerlijn als de kop
    // en de subtekst erboven — de kop stond links maar de knoplabels
    // gecentreerd, en dat verschil las rommelig. De zachtere `outlineVariant`-
    // rand en de ruimere afronding geven de secundaire knoppen een rustiger,
    // verfijnder beeld dan de standaard OutlinedButton.
    final scheme = Theme.of(context).colorScheme;
    final primaryStyle = _primaryButtonStyle();
    final secondaryStyle = _secondaryButtonStyle(scheme);
    return [
      // De kop noemt niet één van de twee soorten: er beginnen hier twee wegen,
      // een presentatie en een document, en die staan naast elkaar. Het woord
      // 'nieuw' staat daarom één keer boven de groep en één keer in elk
      // knoplabel — de knop zegt zelf wat hij maakt, in plaats van 'Kiezen'
      // onder een kop die de soort noemde.
      Text(
        l10n.d('Nieuw'),
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 22),
      // Onder deze knop stond hoeveel sjablonen er klaarstonden. Een getal dat
      // niemand nodig heeft om te beginnen: het staat op de plek waar één
      // handeling hoort en vraagt om lezen en rekenen voordat je mag klikken,
      // en wélke sjablonen het zijn laat de kiezer zelf zien. De melding dat de
      // voorbeelddia's Engels zijn hing eraan en verhuist naar de knop — die
      // geldt alleen voor deze weg, want een document kent geen sjablonen.
      _withTemplateLanguageTooltip(
        l10n,
        _widePrimaryButton(
          style: primaryStyle,
          icon: Icons.slideshow_outlined,
          label: Text(l10n.t('newPresentation')),
          subtitle: Text(
            l10n.d("Dia's, presenteren, exporteren naar PDF of PowerPoint"),
          ),
          onPressed: () => _newDeck(context, ref),
        ),
      ),
      const SizedBox(height: 10),
      ..._newDocumentButton(context, ref, l10n),
      const SizedBox(height: 24),
      Divider(color: scheme.outlineVariant),
      const SizedBox(height: 16),
      _wideSecondaryButton(
        style: secondaryStyle,
        icon: Icons.folder_open_outlined,
        label: Text(l10n.t('open')),
        onPressed: () => _openWithSearch(context, ref),
      ),
      const SizedBox(height: 10),
      _wideSecondaryButton(
        style: secondaryStyle,
        icon: Icons.cloud_download_outlined,
        label: Text(l10n.t('importUrl')),
        onPressed: () => _importFromUrl(context, ref),
      ),
      // Op web: presentaties die al op de eigen webserver staan, via de
      // autoindex. De beheerder configureert dit met een config-bestand op
      // de server (zie HOSTING.md §7); zonder configuratie is de sectie
      // onzichtbaar — nul impact op bestaande deployments.
      ..._serverDecksSection(context, ref, l10n, scheme, secondaryStyle),
      if (supportsLocalProjectFolders) ...[
        const SizedBox(height: 10),
        _wideSecondaryButton(
          style: secondaryStyle,
          icon: Icons.travel_explore,
          label: Text(l10n.d('Zoek op deze computer')),
          onPressed: () => _scanLibrary(context, ref),
        ),
      ],
      // Beginnen met een OpenKAT-uitdraai is beginnen, net zo goed als
      // beginnen met een sjabloon — en juist wie hiermee werkt, komt het
      // vaakst op dit scherm terug om het overzicht te verversen. Zelfde poort
      // als het menu-item: desktop, en de koppeling aan (of er staat al een
      // map). Zonder ingestelde map vraagt de actie er zelf om.
      if (supportsLocalProjectFolders &&
          ref.watch(openKatIntegrationRevealProvider)) ...[
        const SizedBox(height: 10),
        _wideSecondaryButton(
          style: secondaryStyle,
          icon: Icons.radar_outlined,
          onPressed: () => importOpenKatReports(context, ref),
          // Dezelfde bronstring als in het menu: twee bijna gelijke zinnen
          // laten vertalen is hoe ze uit elkaar gaan lopen. Twee regels mag; hij
          // past niet op één in een knop van 220. Links uitgelijnd zoals de
          // andere knoplabels, zodat een tweede regel onder de eerste begint.
          label: Text(
            openKatLabel(l10n, updating: false),
            textAlign: TextAlign.start,
            maxLines: 2,
          ),
        ),
      ],
      // Dezelfde ingang als in het menu: één knop voor alle
      // soorten opslag. Hier stond alleen WebDAV, waardoor
      // wie met S3 of git werkte vanaf dit scherm nergens
      // heen kon.
      if (_remoteConnections(ref).isNotEmpty) ...[
        const SizedBox(height: 10),
        _wideSecondaryButton(
          style: secondaryStyle,
          icon: Icons.cloud_outlined,
          label: Text(l10n.d('Openen uit…')),
          onPressed: () => _openFromConnection(context, ref),
        ),
      ],
      // Onderhoud aan de afbeeldingenbibliotheek kan ook zonder open presentatie
      // (#1108). Bewust onderaan — het is geen "manier om te beginnen" maar een
      // beheertaak; de knop gate zichzelf en verdwijnt bij wie geen bibliotheek
      // heeft.
      ..._imageLibraryButton(context, ref, l10n),
      const SizedBox(height: 4),
    ];
  }

  /// Presentaties die op de eigen webserver staan, opgehaald via de autoindex
  /// van de webserver. Alleen op web, en alleen wanneer de beheerder een
  /// config-bestand op de server heeft gezet (zie HOSTING.md §7). Zonder
  /// configuratie of tijdens het laden is de sectie onzichtbaar.
  List<Widget> _serverDecksSection(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ColorScheme scheme,
    ButtonStyle style,
  ) {
    if (!isWebPlatform) return const [];
    final index = ref.watch(webDeckIndexProvider);
    final decks = index.value;
    if (decks == null || decks.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Divider(color: scheme.outlineVariant),
      const SizedBox(height: 16),
      Text(
        l10n.d('Presentaties op deze server'),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      for (final deck in decks) ...[
        _wideSecondaryButton(
          style: style,
          icon: Icons.description_outlined,
          label: Text(deck.name),
          onPressed: () => _importUrlWeb(context, ref, deck.url),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  /// De linkergroep van de voettekstband: het versienummer (links, klein en
  /// tikt door naar Over OciDeck) plus handleiding en instellingen als
  /// outlined knoppen — dezelfde vorm als de startknoppen in de middelste
  /// kolom, zodat ze herkenbaar als klikbaar zijn. Rechts blijft de
  /// Vigilis-sponsorvermelding staan.
  ///
  /// Eerder stonden deze twee als stille tekstlinks: klein, gedempt, zonder
  /// knopvorm of icoon. Dat was bewust gekozen om ze niet als een zesde en
  /// zevende "manier om te beginnen" te laten lezen. In de praktijk las
  /// niemand ze echter als klikbaar — de gebruiker zag geen verschil met
  /// gewone voettekst. De knopvorm is nu de hogere lat: vindbaarheid wint van
  /// rust.
  ///
  /// De handleiding stond alleen achter Instellingen → Documentatie: drie
  /// klikken diep, precies daar waar iemand die nog niets weet niet gaat
  /// kijken.
  Widget _footerLinks(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette palette,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final creditStyle = TextStyle(fontSize: 11.5, color: palette.mutedText);
    final buttonStyle = _secondaryButtonStyle(scheme);
    // Links het versienummer en de twee knoppen, rechts de sponsorvermelding
    // met het Vigilis-merk. `spaceBetween` duwt de twee groepen naar de
    // uiteinden van de schermbrede band — links links, credit rechtsonder — en
    // laat ze onder elkaar zakken zodra het te smal wordt (bv. 200% tekst),
    // zodat er niets overloopt.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _VersionTag(palette: palette),
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: () => DocumentReaderScreen.open(
                context,
                title: l10n.d('Gebruikershandleiding'),
                assetBase: 'docs/USER_GUIDE.md',
              ),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(l10n.d('Gebruikershandleiding')),
            ),
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: () => SettingsDialog.show(context),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(l10n.t('settings')),
            ),
          ],
        ),
        _madePossibleByVigilis(l10n, creditStyle),
      ],
    );
  }

  Widget _recentFilesPanel(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AppPalette palette,
    AppLocalizations l10n,
    List<RecentFile> recentFiles,
  ) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(
              l10n.t('recentFiles'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: palette.mutedText,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: recentFiles.length,
              itemBuilder: (itemContext, i) => _RecentFileTile(
                file: recentFiles[i],
                origin: ref.watch(
                  settingsProvider.select(
                    (s) => s.recentFileOrigins[recentFiles[i].path],
                  ),
                ),
                homeDir: ref.watch(
                  settingsProvider.select((s) => s.homeDirectory),
                ),
                onTap: () => _openRecent(itemContext, ref, recentFiles[i].path),
                onRemove: () => ref
                    .read(settingsProvider.notifier)
                    .removeRecentFile(recentFiles[i].path),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _newDeck(BuildContext context, WidgetRef ref) =>
      _createDeckFromDialog(context, ref, inNewTab: false);

  /// De knop 'Nieuw document' naast 'Nieuwe presentatie': opent een leeg,
  /// doorlopend tekstdocument in plaats van een presentatie (DOCUMENT_MODE.md) —
  /// dezelfde platte-.md-basis, andere modus. Dezelfde primaire vorm als de
  /// presentatieknop: het zijn twee gelijkwaardige manieren om te beginnen, en
  /// een omlijnde knop naast een gevulde las als 'dit is de mindere van de
  /// twee'. Losse methode zodat [_startColumn] onder de methodelengte-ratchet
  /// blijft.
  List<Widget> _newDocumentButton(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) => [
    _widePrimaryButton(
      style: _primaryButtonStyle(),
      icon: Icons.description_outlined,
      label: Text(l10n.d('Nieuw document')),
      subtitle: Text(
        l10n.d("Doorlopende tekst, pagina's, exporteren naar PDF of Word"),
      ),
      onPressed: () => ref.read(tabsProvider.notifier).newDocument(),
    ),
  ];

  /// De knop 'Afbeeldingen beheren' onderaan de startkolom: opent de bibliotheek
  /// in beheermodus, los van een presentatie (#1108). Zelf gated — alleen op
  /// desktop en zodra er bibliotheekmappen zijn ingesteld, want zonder mappen
  /// valt er niets te beheren. Losse methode zodat [_startColumn] onder de
  /// methodelengte-ratchet blijft.
  List<Widget> _imageLibraryButton(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final hasLibraries = ref.watch(
      settingsProvider.select((s) => s.libraries.isNotEmpty),
    );
    if (!supportsLocalProjectFolders || !hasLibraries) return const [];
    return [
      const SizedBox(height: 10),
      _wideSecondaryButton(
        style: _secondaryButtonStyle(Theme.of(context).colorScheme),
        icon: Icons.photo_library_outlined,
        onPressed: () => _manageImageLibrary(context, ref),
        // 'Afbeeldingen beheren' i.p.v. de langere bibliotheeknaam: het is een
        // beheeractie (zelfde titel als de dialoog) en de tekst mag in een
        // breedsprakige taal op twee regels vallen in plaats van over de rand.
        label: Text(
          l10n.d('Afbeeldingen beheren'),
          textAlign: TextAlign.start,
          maxLines: 2,
        ),
      ),
    ];
  }

  /// Opent de Afbeeldingenbibliotheek in beheermodus, los van een presentatie
  /// (#1108). De zoekwortels zijn de ingestelde bibliotheken; een gekozen
  /// afbeelding heeft hier geen bestemming, dus het resultaat wordt genegeerd —
  /// het gaat om het onderhoud (verwijderen, duplicaten opruimen) dat de
  /// bibliotheek zelf biedt. Eventueel in andere tabs geopende decks worden wél
  /// meegenomen, zodat opruimen hun verwijzingen niet stukmaakt.
  Future<void> _manageImageLibrary(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    await ImageCarouselPicker.show(
      context,
      manageOnly: true,
      searchPaths: settings.libraryPaths,
      captionService: ref.read(captionServiceProvider),
      descriptionService: ref.read(descriptionServiceProvider),
      usageOf: (absolutePath) => _imageUsages(ref, absolutePath),
      onReplaceUsages: (from, to) => _replaceImageUsages(ref, from, to),
      openDeckFiles: [
        for (final tab in ref.read(tabsProvider).tabs)
          ?tab.deckNotifierOrNull?.currentState.filePath,
      ],
    );
  }

  /// Open een recent bestand met dezelfde nette foutafhandeling als het
  /// openen-dialoog; een verdwenen bestand verdwijnt ook uit de lijst.
  Future<void> _openRecent(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final result = await ref.read(tabsProvider.notifier).openFileByPath(path);
    _reportOpenFailure(
      messenger,
      l10n,
      result,
      reason: ref.read(openFailureProvider),
    );
    if (result == OpenResult.unreadable && !File(path).existsSync()) {
      // Het bestand bestaat niet meer: opruimen i.p.v. blijven aanbieden.
      await ref.read(settingsProvider.notifier).removeRecentFile(path);
    }
  }
}

/// Het draaiende versienummer, in de hoek van het openscherm. Dezelfde
/// `kOciDeckVersion` als op het About-tabblad — een tik erop opent dat
/// tabblad meteen, want dat is precies het nummer dat bij een
/// beveiligingsmelding hoort (zie settings_dialog_about.dart).
class _VersionTag extends StatelessWidget {
  final AppPalette palette;

  const _VersionTag({required this.palette});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.t('settings'),
      child: InkWell(
        onTap: () =>
            SettingsDialog.show(context, initialSection: SettingsSection.about),
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            'v$kOciDeckVersion',
            style: TextStyle(fontSize: 10.5, color: palette.mutedText),
          ),
        ),
      ),
    );
  }
}

/// Het OciDeck-merk als alpha-masker, met een hover-wissel van inktkleur. In
/// rust toont het merk [baseInk] (EU-geel of EU-blauw, zie [_brandPanel]).
/// Bij hover gaat het naar de 'andere' Europese kleur: is de rustkleur blauw,
/// dan wordt het geel; is de rustkleur geel, dan wordt het Italiaans
/// vlaggroen. Eén widget met eigen state, want de inktkleur hangt af van
/// muisstatus die de bovenliggende [StatelessWidget] niet bijhoudt.
class _HoverHueLogo extends StatefulWidget {
  final Color baseInk;
  final double size;

  const _HoverHueLogo({required this.baseInk, required this.size});

  @override
  State<_HoverHueLogo> createState() => _HoverHueLogoState();
}

class _HoverHueLogoState extends State<_HoverHueLogo> {
  bool _hovering = false;

  Color get _hoverInk {
    // Blauw → geel, geel → Italiaans groen. De twee rustkleuren uit
    // [_brandPanel] krijgen zo elk een eigen hoverkleur uit het Europese
    // kleurgebaar; andere basisinkleuren vallen terug op geel (de merkkleur).
    if (widget.baseInk == AppTheme.blueVivid) return AppTheme.amberVivid;
    if (widget.baseInk == AppTheme.amberVivid) return AppTheme.italianGreen;
    return AppTheme.amberVivid;
  }

  @override
  Widget build(BuildContext context) {
    final ink = _hovering ? _hoverInk : widget.baseInk;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
          child: Image.asset(
            BrandLogo.ociDeck.darkAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

// ── Main 2-panel layout ───────────────────────────────────────────────────────

/// Eén rij in de recente-bestandenlijst: naam plus de vindplaats en een
/// metadataregel met datum, aantal slides, TLP-badge en het laatst
/// geëxporteerde formaat — zodat terugvinden niet op naam alleen hoeft. Het
/// volledige pad (en de exportdatum) staat in de tooltip, zodat de rij zelf
/// rustig blijft.
class _RecentFileTile extends StatelessWidget {
  final RecentFile file;

  /// Herkomst van een remote opgehaald bestand (Nextcloud-server of
  /// import-URL); null voor lokale bestanden.
  final String? origin;
  final String? homeDir;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentFileTile({
    required this.file,
    required this.origin,
    required this.homeDir,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>()!;
    final material = MaterialLocalizations.of(context);
    final name = p.basenameWithoutExtension(file.path);

    final tooltip = StringBuffer(file.path);
    if (file.lastExportFormat != null) {
      tooltip.write(
        '\n${l10n.d('Laatst geëxporteerd als')} ${file.lastExportFormat}',
      );
      if (file.lastExportAt != null) {
        tooltip.write(' · ${material.formatShortDate(file.lastExportAt!)}');
      }
    }

    final metaText = [
      if (file.openedAt != null) material.formatShortDate(file.openedAt!),
      if (file.slideCount > 0) '${file.slideCount} ${l10n.t('slides')}',
    ].join(' · ');

    return Tooltip(
      message: tooltip.toString(),
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                // Presentatie of document: hetzelfde onderscheid als in de
                // openschermen, zodat je vóór het klikken weet wat je opent.
                child: Tooltip(
                  message: markdownKindLabel(l10n, file.kind),
                  child: Icon(
                    markdownKindIcon(file.kind),
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (origin != null) ...[
                          const SizedBox(width: 6),
                          // Remote opgehaald (Nextcloud/URL): de tooltip
                          // toont de bron zelf, dus die heeft geen vertaling
                          // nodig.
                          Tooltip(
                            message: origin!,
                            child: Icon(
                              Icons.cloud_outlined,
                              size: 13,
                              color: palette.accentInk,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // De vindplaats kort en betekenisvol (thuismap-relatief);
                    // het volledige pad zit in de tooltip.
                    Text(
                      displayFolder(
                        file.path,
                        homeDir: homeDir,
                        osHome: osHomeDirectory,
                      ),
                      style: TextStyle(fontSize: 10, color: palette.mutedText),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (metaText.isNotEmpty)
                          Text(
                            metaText,
                            style: TextStyle(
                              fontSize: 10,
                              color: palette.mutedText,
                            ),
                          ),
                        if (file.tlp != TlpLevel.none)
                          _RecentBadge(
                            label: file.tlp.label,
                            foreground: Color(file.tlp.foreground),
                            background: Colors.black,
                          ),
                        if (file.lastExportFormat != null)
                          _RecentBadge(
                            label: file.lastExportFormat!,
                            foreground: theme.colorScheme.onSurfaceVariant,
                            background:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: l10n.d('Uit recente bestanden verwijderen'),
                child: InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: palette.mutedText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Klein badge-blokje in de metadataregel (TLP in officiële kleuren op
/// zwart, exportformaat in neutrale tint).
class _RecentBadge extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;

  const _RecentBadge({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: foreground,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
