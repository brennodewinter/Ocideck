part of '../app_shell.dart';

/// The command palette (Ctrl/Cmd+K), split into a `part of` extension to keep
/// `app_shell_main_layout.dart` under the line limit. Same library, so it keeps
/// access to `_MainLayoutState`'s `context`/`ref` and the shell's private
/// actions.
extension _MainLayoutCommandPalette on _MainLayoutState {
  /// Commandopalet (Ctrl/Cmd+K): één doorzoekbare lijst van alle acties. Labels
  /// hergebruiken de bestaande menu-/tooltipteksten, zodat ze niet uit de pas
  /// lopen en geen extra vertalingen kosten. De export-gate volgt [_canExport].
  void _openCommandPalette() {
    final l10n = context.l10n;
    final deck = ref.read(deckProvider).deck!;
    final deckNotifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);
    final isMarkdownMode = ref.read(editorProvider).mode == EditorMode.markdown;

    final commands = <PaletteCommand>[
      PaletteCommand(
        label: l10n.d('Presenteren'),
        icon: Icons.play_circle_outline,
        keywords: const ['present', 'slideshow', 'F5'],
        onInvoke: _presentDeck,
      ),
      PaletteCommand(
        label: l10n.t('export'),
        icon: Icons.file_download_outlined,
        keywords: const ['pdf', 'pptx', 'html'],
        enabled: _canExport,
        onInvoke: _exportDeck,
      ),
      PaletteCommand(
        label: l10n.d('Opslaan'),
        icon: Icons.save_outlined,
        shortcut: 'Ctrl/Cmd+S',
        onInvoke: _saveDeck,
      ),
      PaletteCommand(
        label: l10n.d('Nieuwe grafiek'),
        icon: Icons.insert_chart_outlined,
        keywords: const ['chart', 'csv'],
        onInvoke: () {
          final i = ref.read(editorProvider).selectedIndex;
          deckNotifier.addSlide(SlideType.chart, afterIndex: i);
          editorNotifier.select(i + 1);
        },
      ),
      PaletteCommand(
        label: l10n.t('findReplace'),
        icon: Icons.find_replace,
        shortcut: 'Ctrl/Cmd+H',
        onInvoke: _openFindReplace,
      ),
      PaletteCommand(
        label: l10n.d('Wis AI-alt-teksten'),
        icon: Icons.auto_delete_outlined,
        keywords: const ['ai', 'alt', 'accessibility', 'undo'],
        enabled: deckNotifier.aiGeneratedAltTextCount > 0,
        onInvoke: () => clearAiAltTexts(),
      ),
      ..._securityCommands(l10n, deck, deckNotifier),
      PaletteCommand(
        label: l10n.t('imageLibrary'),
        icon: Icons.photo_library_outlined,
        onInvoke: _openImageCarousel,
      ),
      PaletteCommand(
        label: isMarkdownMode ? l10n.t('visualMode') : l10n.t('markdownMode'),
        icon: isMarkdownMode ? Icons.view_quilt : Icons.code,
        onInvoke: _toggleMarkdownMode,
      ),
      PaletteCommand(
        label: l10n.t('fullDeckPreview'),
        icon: Icons.preview_outlined,
        onInvoke: _openFullDeckPreview,
      ),
      PaletteCommand(
        label: l10n.t('newPresentationTab'),
        icon: Icons.add_circle_outline,
        onInvoke: _newInTab,
      ),
      PaletteCommand(
        label: l10n.t('openEllipsis'),
        icon: Icons.folder_open_outlined,
        onInvoke: () => _openWithSearch(context, ref),
      ),
      PaletteCommand(
        label: l10n.t('exportPackage'),
        icon: Icons.inventory_2_outlined,
        onInvoke: () => _exportPackage(context, ref),
      ),
      PaletteCommand(
        label: l10n.t('importPackage'),
        icon: Icons.unarchive_outlined,
        onInvoke: _importPackage,
      ),
      PaletteCommand(
        label: l10n.t('importUrl'),
        icon: Icons.link,
        onInvoke: _importUrl,
      ),
      PaletteCommand(
        label: l10n.t('settings'),
        icon: Icons.settings_outlined,
        onInvoke: () => SettingsDialog.show(context),
      ),
      // TLP-classificatie: één commando per niveau (het huidige niveau is uit).
      for (final level in TlpLevel.values)
        PaletteCommand(
          label:
              '${l10n.t('classification')}: '
              '${level == TlpLevel.none ? l10n.d('Geen') : level.label}',
          icon: Icons.shield_outlined,
          keywords: const ['tlp', 'classification'],
          enabled: deck.tlp != level,
          onInvoke: () => deckNotifier.updateInfo(tlp: level),
        ),
    ];
    CommandPalette.show(context, commands);
  }

  /// The security-module command-palette actions, gated on the reveal flag and
  /// grouped here to keep [_openCommandPalette] under the method-length limit.
  List<PaletteCommand> _securityCommands(
    AppLocalizations l10n,
    Deck deck,
    DeckNotifier deckNotifier,
  ) {
    final enabled = ref.read(secModuleRevealProvider);
    return [
      PaletteCommand(
        label: l10n.d('MIAUW-compliance'),
        icon: Icons.fact_check_outlined,
        keywords: const ['eis', 'compliance', 'miauw', 'waiver', 'audit'],
        enabled: enabled,
        onInvoke: () => MiauwCompliancePanel.show(context, deckNotifier),
      ),
      PaletteCommand(
        label: l10n.d('Bevindingen hernummeren'),
        icon: Icons.format_list_numbered,
        keywords: const ['finding', 'renumber', 'nummer', 'f-01'],
        enabled: enabled,
        onInvoke: deckNotifier.autoRenumberFindings,
      ),
      PaletteCommand(
        label: l10n.d('Scope-dekking controleren'),
        icon: Icons.travel_explore_outlined,
        keywords: const ['scope', 'coverage', 'gap', 'dekking'],
        enabled: enabled,
        onInvoke: () =>
            ScopeCoverageDialog.show(context, deckScopeCoverageGaps(deck)),
      ),
      PaletteCommand(
        label: l10n.d('Bewijs-hashes kopiëren'),
        icon: Icons.tag_outlined,
        keywords: const ['sha1', 'sha256', 'hash', 'bewijs', 'evidence'],
        enabled: enabled,
        onInvoke: _copyEvidenceHashes,
      ),
      PaletteCommand(
        label: l10n.d('Managementsamenvatting'),
        icon: Icons.summarize_outlined,
        keywords: const ['summary', 'management', 'samenvatting', 'overzicht'],
        enabled: enabled,
        onInvoke: () =>
            ManagementSummaryDialog.show(context, deckManagementSummary(deck)),
      ),
      PaletteCommand(
        label: l10n.d('RFC3161-tijdstempel'),
        icon: Icons.schedule_outlined,
        keywords: const ['rfc3161', 'timestamp', 'tijdstempel', 'tsa', 'seal'],
        enabled: enabled,
        onInvoke: () => SealTimestampDialog.show(context, deckNotifier),
      ),
      PaletteCommand(
        label: l10n.d('Auditdossier exporteren'),
        icon: Icons.inventory_2_outlined,
        keywords: const [
          'audit',
          'dossier',
          'export',
          'pakket',
          'bewijs',
          'verzegel',
        ],
        enabled: enabled,
        onInvoke: () => _exportAuditDossier(context, ref),
      ),
    ];
  }

  /// Compute the MIAUW evidence hash table (SHA1 + SHA-256) for every evidence
  /// slide in the deck and copy it to the clipboard (PENTEST_MIAUW §10.2). Reads
  /// each evidence image's bytes off disk; slides it cannot read are skipped.
  Future<void> _copyEvidenceHashes() async {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final imageService = ImageService();
    final hashes = <String, EvidenceHashes>{};
    for (final slide in deck.slides) {
      if (slide.findingRole != FindingRole.evidence ||
          slide.imagePath.isEmpty) {
        continue;
      }
      final bytes = await imageService.readSlideImageBytes(
        slide.imagePath,
        projectPath: deck.projectPath,
      );
      if (bytes != null) {
        hashes[slide.imagePath] = computeEvidenceHashes(bytes);
      }
    }
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: evidenceHashTable(hashes)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.d('Bewijs-hashes gekopieerd'))),
    );
  }
}
