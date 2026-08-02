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
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 76).clamp(0, 10000),
                ),
                child: Center(
                  child: _welcomeHub(
                    context,
                    ref,
                    theme,
                    palette,
                    l10n,
                    recentFiles,
                    constraints,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 12,
            child: _VersionTag(palette: palette),
          ),
        ],
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
    final baseHubHeight = (viewport.maxHeight - 88).clamp(460, 590).toDouble();
    final requiredBrandHeight = _requiredBrandPanelHeight(context, theme, l10n);
    final hubHeight = requiredBrandHeight > baseHubHeight
        ? requiredBrandHeight
        : baseHubHeight;
    final hub = wide
        ? SizedBox(
            height: hubHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 340,
                  child: _brandPanel(context, theme, l10n, fillHeight: true),
                ),
                Expanded(child: _actionsPanel(context, ref, l10n, palette)),
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
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: _brandPanel(context, theme, l10n, fillHeight: false),
              ),
              SizedBox(
                height: 520,
                child: _actionsPanel(context, ref, l10n, palette),
              ),
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

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: recentFiles.isEmpty ? 840 : 1120),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: hub,
      ),
    );
  }

  double _requiredBrandPanelHeight(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    double textHeight(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: 272);
      return painter.height;
    }

    return 68 +
        170 +
        textHeight(l10n.d('Welkom bij OciDeck'), _brandHeadingStyle(theme)) +
        12 +
        textHeight(
          l10n.d(
            'Presentaties die gewone Markdown-bestanden blijven: leesbaar, doorzoekbaar en te openen met elke editor.',
          ),
          _brandBodyStyle(theme),
        );
  }

  TextStyle? _brandHeadingStyle(ThemeData theme) =>
      theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600);

  TextStyle? _brandBodyStyle(ThemeData theme) => theme.textTheme.bodyMedium
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45);

  Widget _brandPanel(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n, {
    required bool fillHeight,
  }) {
    return Container(
      padding: const EdgeInsets.all(34),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: l10n.d('OciDeck'),
            image: true,
            child: Container(
              width: 170,
              height: 170,
              padding: const EdgeInsets.all(12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Image.asset(
                BrandLogo.ociDeck.assetKey,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          if (fillHeight) const Spacer() else const SizedBox(height: 48),
          Text(l10n.d('Welkom bij OciDeck'), style: _brandHeadingStyle(theme)),
          const SizedBox(height: 12),
          Text(
            l10n.d(
              'Presentaties die gewone Markdown-bestanden blijven: leesbaar, doorzoekbaar en te openen met elke editor.',
            ),
            style: _brandBodyStyle(theme),
          ),
        ],
      ),
    );
  }

  Widget _actionsPanel(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AppPalette palette,
  ) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 30, 32, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _startColumn(context, ref, l10n, palette),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: _footerLinks(context, l10n, palette),
          ),
        ],
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
    AppPalette palette,
  ) {
    return [
      Text(
        l10n.t('newPresentation'),
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 7),
      _withTemplateLanguageTooltip(
        l10n,
        Text(
          '${_visibleTemplateCount(ref)} '
          '${l10n.d('sjablonen om mee te beginnen, of leeg')}',
          style: TextStyle(color: palette.mutedText),
        ),
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          onPressed: () => _newDeck(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.d('Kiezen')),
        ),
      ),
      const SizedBox(height: 24),
      Divider(color: Theme.of(context).colorScheme.outlineVariant),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onPressed: () => _openWithSearch(context, ref),
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(l10n.t('open')),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onPressed: () => _importFromUrl(context, ref),
          icon: const Icon(Icons.cloud_download_outlined, size: 18),
          label: Text(l10n.t('importUrl')),
        ),
      ),
      if (supportsLocalProjectFolders) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _scanLibrary(context, ref),
            icon: const Icon(Icons.travel_explore, size: 18),
            label: Text(l10n.d('Zoek op deze computer')),
          ),
        ),
      ],
      // Beginnen met een OpenKAT-uitdraai is beginnen, net zo goed als
      // beginnen met een sjabloon — en juist wie hiermee werkt, komt het
      // vaakst op dit scherm terug om het overzicht te verversen. Zelfde poort
      // als het menu-item: desktop, en de module aan (of er staat al een map).
      // Zonder ingestelde map vraagt de actie er zelf om.
      if (supportsLocalProjectFolders &&
          ref.watch(importModuleRevealProvider)) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => importOpenKatReports(context, ref),
            icon: const Icon(Icons.radar_outlined, size: 18),
            // Dezelfde bronstring als in het menu: twee bijna gelijke zinnen
            // laten vertalen is hoe ze uit elkaar gaan lopen. Twee regels mag;
            // hij past niet op één in een knop van 220.
            label: Text(
              openKatLabel(l10n, updating: false),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ),
      ],
      // Dezelfde ingang als in het menu: één knop voor alle
      // soorten opslag. Hier stond alleen WebDAV, waardoor
      // wie met S3 of git werkte vanaf dit scherm nergens
      // heen kon.
      if (_remoteConnections(ref).isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openFromConnection(context, ref),
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: Text(l10n.d('Openen uit…')),
          ),
        ),
      ],
      const SizedBox(height: 4),
    ];
  }

  /// De twee tekstlinks onderaan: handleiding en instellingen.
  ///
  /// Bewust stil: klein, gedempte kleur, geen knopvorm en geen icoon. Ze
  /// stonden eerst als [TextButton.icon] vlak onder de knoppenkolom — zelfde
  /// blauw, bijna dezelfde lettergrootte — en lazen daardoor als een zesde en
  /// zevende "manier om te beginnen" in plaats van de bijzaak die het is. Hoe
  /// meer opties er even zwaar ogen, hoe langer het kiezen duurt (Hick-Hyman);
  /// een stille, losstaande voettekst laat de knoppenkolom weer als dé keuze
  /// staan.
  ///
  /// De handleiding stond alleen achter Instellingen → Documentatie: drie
  /// klikken diep, precies daar waar iemand die nog niets weet niet gaat
  /// kijken.
  Widget _footerLinks(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette palette,
  ) {
    final style = TextStyle(fontSize: 11.5, color: palette.mutedText);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      children: [
        _QuietLink(
          label: l10n.d('Gebruikershandleiding'),
          style: style,
          onTap: () => DocumentReaderScreen.open(
            context,
            title: l10n.d('Gebruikershandleiding'),
            assetBase: 'docs/USER_GUIDE.md',
          ),
        ),
        _QuietLink(
          label: l10n.t('settings'),
          style: style,
          onTap: () => SettingsDialog.show(context),
        ),
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
              l10n.t('recentPresentations'),
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

  /// Hoeveel sjablonen deze gebruiker straks te kiezen krijgt. Dezelfde
  /// zichtbaarheidsregel als de kiezer zelf: de module-sjablonen tellen pas mee
  /// als hun uitbreiding aan staat, anders belooft het openscherm er te veel.
  int _visibleTemplateCount(WidgetRef ref) {
    final secRevealed = ref.watch(infoSafetyRevealProvider);
    final impRevealed = ref.watch(procesverbeteringRevealProvider);
    return deckTemplates
        .where(
          (template) => deckTemplateVisible(
            template,
            infoSafetyRevealed: secRevealed,
            procesverbeteringRevealed: impRevealed,
          ),
        )
        .length;
  }

  Future<void> _newDeck(BuildContext context, WidgetRef ref) =>
      _createDeckFromDialog(context, ref, inNewTab: false);

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

/// Eén tekstlinkje in de stille voettekst: geen knopvorm, geen icoon — de
/// stijl van [style] (klein, gedempt) draagt het onderscheid met de echte
/// knoppen erboven, niet padding of een rand.
class _QuietLink extends StatelessWidget {
  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  const _QuietLink({
    required this.label,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(label, style: style),
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
    final name = p.basename(file.path).replaceAll('.md', '');

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
                child: Icon(
                  Icons.slideshow_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
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

/// Alleen buiten nl/en zit er een melding op de sjabloonbelofte; in die twee
/// talen komt de tekst kaal terug, zodat er geen leeg zweefvenster ontstaat.
Widget _withTemplateLanguageTooltip(AppLocalizations l10n, Widget child) {
  if (l10n.languageCode == 'nl' || l10n.languageCode == 'en') return child;
  return Tooltip(
    message: l10n.d(
      "De voorbeelddia's van een sjabloon staan in het Engels. Naam en omschrijving volgen je eigen taal; de inhoud pas je na het aanmaken aan.",
    ),
    child: child,
  );
}
