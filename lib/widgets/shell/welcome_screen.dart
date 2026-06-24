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
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          // ── Midden: logo + knoppen ─────────────────────────────────────
          Expanded(
            child: Align(
              alignment: const Alignment(-0.15, 0.12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'De Winter Information Solutions',
                    image: true,
                    child: Image.asset(
                      'assets/images/de-winter-wittegeheel.png',
                      width: 320,
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
                      onPressed: () => _openWithSearch(context, ref, homeDir),
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: Text(l10n.t('open')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton.icon(
                      onPressed: () => _scanLibrary(context, ref),
                      icon: const Icon(Icons.travel_explore, size: 18),
                      label: Text(l10n.d('Zoek op deze computer')),
                    ),
                  ),
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
          // ── Rechts: recente bestanden ──────────────────────────────────
          if (recentFiles.isNotEmpty)
            Container(
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
                      itemBuilder: (_, i) {
                        final path = recentFiles[i];
                        final name = path.split('/').last.replaceAll('.md', '');
                        return InkWell(
                          onTap: () => ref
                              .read(tabsProvider.notifier)
                              .openFileByPath(path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.slideshow_outlined,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        path,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: palette.mutedText,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _newDeck(BuildContext context, WidgetRef ref) async {
    final title = await NewDeckDialog.show(context);
    if (title != null) {
      ref.read(tabsProvider.notifier).newDeckInCurrentTab(title);
    }
  }
}

// ── Main 2-panel layout ───────────────────────────────────────────────────────
