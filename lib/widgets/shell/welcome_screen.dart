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
    final homeDir = ref.watch(settingsProvider.select((s) => s.homeDirectory));
    final recentFiles = ref.watch(
      settingsProvider.select((s) => s.recentFiles),
    );

    return Scaffold(
      // Wit i.p.v. het lichtgrijze scaffold-vlak, zodat het openscherm één
      // egaal wit oppervlak is dat aansluit op de (witte) recente-bestanden­kolom.
      backgroundColor: theme.colorScheme.surface,
      body: Row(
        children: [
          // ── Midden: logo + knoppen ─────────────────────────────────────
          Expanded(
            // Scroll-safe: bij sterk vergrote interfacetekst (tot 200%) passen
            // logo + knoppen niet meer op de hoogte; dan scrollt het in plaats
            // van te overlopen. Bij genoeg ruimte blijft het gecentreerd.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: const Alignment(-0.15, 0.12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: 'OciDeck',
                          image: true,
                          child: Image.asset(
                            'assets/images/ocideck-logo.png',
                            width: 200,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: 220,
                          child: ElevatedButton.icon(
                            onPressed: () => _newDeck(context, ref),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(l10n.t('newPresentation')),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 220,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _openWithSearch(context, ref, homeDir),
                            icon: const Icon(
                              Icons.folder_open_outlined,
                              size: 18,
                            ),
                            label: Text(l10n.t('open')),
                          ),
                        ),
                        // URL-import werkt overal: op desktop via het
                        // gehardende dart:io-pad, op web via de browser
                        // (CORS + CSP `connect-src https:`) met dezelfde
                        // security-gate. Nextcloud blijft een netwerkbron
                        // achter [supportsNetworkDeckSources]; de
                        // bibliotheekscan doorzoekt het lokale
                        // bestandssysteem en kan op web niet.
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 220,
                          child: OutlinedButton.icon(
                            onPressed: () => _importFromUrl(context, ref),
                            icon: const Icon(
                              Icons.cloud_download_outlined,
                              size: 18,
                            ),
                            label: Text(l10n.t('importUrl')),
                          ),
                        ),
                        if (supportsLocalProjectFolders) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 220,
                            child: OutlinedButton.icon(
                              onPressed: () => _scanLibrary(context, ref),
                              icon: const Icon(Icons.travel_explore, size: 18),
                              label: Text(l10n.d('Zoek op deze computer')),
                            ),
                          ),
                        ],
                        if (supportsNetworkDeckSources) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 220,
                            child: OutlinedButton.icon(
                              onPressed: () => _openFromNextcloud(context, ref),
                              icon: const Icon(Icons.cloud_outlined, size: 18),
                              label: Text(l10n.d('Openen vanaf Nextcloud')),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => SettingsDialog.show(context),
                          icon: const Icon(Icons.settings_outlined, size: 17),
                          label: Text(l10n.t('settings')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── Rechts: recente bestanden ──────────────────────────────────
          if (recentFiles.isNotEmpty)
            _recentFilesPanel(context, ref, theme, palette, l10n, recentFiles),
        ],
      ),
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

  Future<void> _newDeck(BuildContext context, WidgetRef ref) async {
    final choice = await NewDeckDialog.show(context);
    if (choice == null) return;
    // Profielkeuze is globaal (het actieve profiel bepaalt de stijl van elk
    // deck); eerst selecteren, dan aanmaken zodat het nieuwe deck hem erft.
    await ref
        .read(settingsProvider.notifier)
        .selectThemeProfile(choice.profileName);
    ref
        .read(tabsProvider.notifier)
        .newDeckInCurrentTab(choice.title, template: choice.template);
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
    _reportOpenFailure(messenger, l10n, result);
    if (result == OpenResult.unreadable && !File(path).existsSync()) {
      // Het bestand bestaat niet meer: opruimen i.p.v. blijven aanbieden.
      await ref.read(settingsProvider.notifier).removeRecentFile(path);
    }
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
                              color: theme.colorScheme.primary,
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
