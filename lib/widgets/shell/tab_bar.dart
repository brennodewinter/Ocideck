// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

class _AppTabBar extends StatelessWidget {
  final TabsState tabsState;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;

  const _AppTabBar({
    required this.tabsState,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = Theme.of(context).extension<AppPalette>()!;
    return _tabRow(context, l10n, palette);
  }

  Widget _tabRow(
    BuildContext context,
    AppLocalizations l10n,
    AppPalette palette,
  ) {
    return Container(
      height: 36,
      color: palette.panel,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < tabsState.tabs.length; i++)
                    _TabChip(
                      tab: tabsState.tabs[i],
                      isActive: i == tabsState.clampedIndex,
                      showClose:
                          tabsState.tabs.length > 1 || tabsState.tabs[i].isOpen,
                      panelText: palette.panelText,
                      accent: Theme.of(context).colorScheme.secondary,
                      onTap: () => onSelect(i),
                      onClose: () => onClose(i),
                    ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: l10n.t('newTab'),
            child: InkWell(
              onTap: onAdd,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: palette.panelText.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  final TabInfo tab;
  final bool isActive;
  final bool showClose;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final Color panelText;
  final Color accent;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.showClose,
    required this.onTap,
    required this.onClose,
    required this.panelText,
    required this.accent,
  });

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  TabInfo get tab => widget.tab;
  bool get isActive => widget.isActive;
  bool get showClose => widget.showClose;
  Color get panelText => widget.panelText;
  Color get accent => widget.accent;
  VoidCallback get onTap => widget.onTap;
  VoidCallback get onClose => widget.onClose;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _scrollIntoView();
  }

  @override
  void didUpdateWidget(_TabChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _scrollIntoView();
  }

  /// Houd de actieve tab in beeld: met veel open decks kan die anders buiten
  /// het horizontaal scrollende deel van de balk vallen.
  void _scrollIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 80, maxWidth: 200),
        height: 36,
        decoration: BoxDecoration(
          color: isActive
              ? panelText.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Een documenttabblad draagt een klein icoon vooraan, zodat het in
            // één oogopslag te onderscheiden is van een presentatietabblad. De
            // soort volgt uit de afwezigheid van `marp: true` (zie MarkdownKind).
            if (tab.kind.isDocument)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Tooltip(
                  message: context.l10n.d('Document'),
                  child: Icon(
                    Icons.description_outlined,
                    size: 13,
                    color: panelText.withValues(alpha: isActive ? 0.9 : 0.6),
                  ),
                ),
              ),
            if (tab.isDirty)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: const BoxDecoration(
                  color: Colors.orangeAccent,
                  shape: BoxShape.circle,
                ),
              ),
            Flexible(
              child: Text(
                tab.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? panelText
                      : panelText.withValues(alpha: 0.72),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showClose) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: panelText.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Per-tab content ───────────────────────────────────────────────────────────

/// Eén tab-paneel, met alle providers die het deck lezen per tab opnieuw
/// gescoped.
///
/// Alles wat het deck leest hoort in deze `overrides` te staan. Een afgeleide
/// provider die ontbreekt, lost op in de root-container, ziet een leeg deck en
/// doet stilletjes niets — geen fout, geen melding, gewoon niets. Zo ging
/// `imageContrastIssuesProvider` ooit stuk. `provider_scope_test.dart` scant
/// `lib/state` en faalt als er hier een mist.
Widget _tabScope(TabInfo tab) {
  // Een documenttabblad krijgt een eigen, veel lichtere scope: het bewerkt de
  // platte bron via één DocumentNotifier, niet een deck met zijn afgeleide
  // privacy/kwaliteit-keten. De gedeelde tabbalk eromheen blijft soort-agnostisch.
  if (tab.content case DocumentTabContent(:final documentNotifier)) {
    return ProviderScope(
      key: ValueKey(tab.id),
      overrides: [
        documentProvider.overrideWith(
          (ref) =>
              documentNotifier.mounted ? documentNotifier : DocumentNotifier(),
        ),
      ],
      child: const DocumentEditorScreen(),
    );
  }
  return ProviderScope(
    key: ValueKey(tab.id),
    overrides: [
      // Bij sluiten kan de DeckNotifier al disposed zijn terwijl _TabContent
      // nog één rebuild doet (c542bf1e fixte TabInfo, niet de keten).
      deckProvider.overrideWith(
        (ref) => tab.deckNotifier.mounted
            ? tab.deckNotifier
            : DeckNotifier(
                ref.read(markdownServiceProvider),
                ref.read(fileServiceProvider),
              ),
      ),
      editorProvider.overrideWith((ref) => tab.editorNotifier),
      collabSessionProvider.overrideWith(
        (ref) => CollabSessionNotifier(ref, tab),
      ),
      deckQualityRawProvider.overrideWith(computeDeckQualityRaw),
      deckQualityProvider.overrideWith(computeDeckQuality),
      imageContrastIssuesProvider.overrideWith(computeImageContrastIssues),
      themeLogoIssuesProvider.overrideWith(computeThemeLogoIssues),
      privacyRawScanProvider.overrideWith(computePrivacyRawScan),
      imagePrivacyRawIssuesProvider.overrideWith(computeImagePrivacyRawIssues),
      imagePrivacyIssuesProvider.overrideWith(computeImagePrivacyIssues),
      privacyScanProvider.overrideWith(computePrivacyScan),
      privacyQualityIssuesProvider.overrideWith(computePrivacyQualityIssues),
      improvementQualityIssuesProvider.overrideWith(
        computeImprovementQualityIssues,
      ),
      privacyExportSummaryProvider.overrideWith(computePrivacyExportSummary),
    ],
    child: const _TabContent(),
  );
}

class _TabContent extends ConsumerWidget {
  const _TabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Zolang dit tabblad leeft blijft zijn afgeleide keten aangesloten, zodat
    // een deckwijziging vóór het frame wordt verwerkt en niet pas in de build
    // van de eerste widget die hem toevallig leest. Zie warmTabDerivedProviders.
    warmTabDerivedProviders(ref);
    final isOpen = ref.watch(deckProvider.select((s) => s.isOpen));
    if (!isOpen) return const _WelcomeScreen();
    // 'Alleen afspelen'-vergrendeling: het volledige bewerk-scherm (toolbar,
    // menu's, sneltoetsen, editor) wordt dan niet opgebouwd — enkel het
    // afspeel-scherm. Sluiten van het tabblad geeft de normale werking terug.
    final playOnly = ref.watch(
      deckProvider.select((s) => s.deck?.playOnly ?? false),
    );
    if (playOnly) return const _PlayOnlyScreen();
    return _MainLayout(exportService: ExportService());
  }
}

// ── Welcome screen ────────────────────────────────────────────────────────────
