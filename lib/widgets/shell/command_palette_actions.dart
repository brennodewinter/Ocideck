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
        label: l10n.d('Bewerken'),
        icon: Icons.open_in_full,
        shortcut: shortcutLabel(l10n, 'Enter', shift: true),
        keywords: const ['markdown', 'editor', 'wysiwyg'],
        enabled: MarkdownEditorField.openActiveEditor != null,
        onInvoke: () => MarkdownEditorField.openActiveEditor?.call(),
      ),
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
        shortcut: shortcutLabel(l10n, 'S'),
        onInvoke: _saveDeck,
      ),
      ..._editCommands(l10n, deckNotifier),
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
        shortcut: shortcutLabel(l10n, 'H'),
        onInvoke: _openFindReplace,
      ),
      PaletteCommand(
        label: l10n.d('Wis AI-alt-teksten'),
        icon: Icons.auto_delete_outlined,
        keywords: const ['ai', 'alt', 'accessibility', 'undo'],
        enabled: deckNotifier.aiGeneratedAltTextCount > 0,
        onInvoke: () => clearAiAltTexts(),
      ),
      ..._helpCommands(l10n),
      ..._infoSafetyCommands(l10n, deck, deckNotifier),
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
      ...provenanceSignCommands(ref, l10n, deck, _signProvenance),
      ...collabPaletteCommands(context, ref, l10n),
      ...openKatPaletteCommands(context, ref, l10n),
    ];
    CommandPalette.show(context, commands);
  }

  /// De handelingen die het vaakst gezocht worden en tot nu toe alleen als
  /// icoontje in de werkbalk bestonden, plus de twee gebundelde documenten.
  ///
  /// Het palet is in deze app de plek waar een functie gevonden wordt; ongedaan
  /// maken en opnieuw hoorden er als eerste in.
  List<PaletteCommand> _editCommands(
    AppLocalizations l10n,
    DeckNotifier deckNotifier,
  ) => [
    // Ongedaan maken en opnieuw ontbraken hier, terwijl ze alleen als twee
    // kleine icoontjes in de werkbalk bestonden. Het palet is in deze app de
    // plek waar een functie gevonden wordt; de twee handelingen die iemand het
    // vaakst zoekt, hoorden er als eerste in.
    PaletteCommand(
      label: l10n.d('Ongedaan maken'),
      icon: Icons.undo,
      shortcut: shortcutLabel(l10n, 'Z'),
      keywords: const ['undo', 'terug'],
      enabled: deckNotifier.currentState.canUndo,
      onInvoke: () => _undo(deckNotifier),
    ),
    PaletteCommand(
      label: l10n.d('Opnieuw'),
      icon: Icons.redo,
      shortcut: shortcutLabel(l10n, 'Z', shift: true),
      keywords: const ['redo', 'opnieuw'],
      enabled: deckNotifier.currentState.canRedo,
      onInvoke: () => _redo(deckNotifier),
    ),
    PaletteCommand(
      label: l10n.d('Zoeken'),
      icon: Icons.search,
      shortcut: shortcutLabel(l10n, 'F'),
      onInvoke: _openFind,
    ),
    PaletteCommand(
      // Zelfde instel-icoon als de knop in de AppBar-titel (#1479), zodat beide
      // ingangen naar dezelfde presentatie-eigenschappen er hetzelfde uitzien.
      label: l10n.d('Eigenschappen'),
      icon: Icons.tune,
      keywords: const ['auteur', 'organisatie', 'metadata'],
      onInvoke: _openProperties,
    ),
  ];

  /// De gebundelde documentatie, zonder internet te hoeven raadplegen.
  List<PaletteCommand> _helpCommands(AppLocalizations l10n) => [
    PaletteCommand(
      label: l10n.d('Gebruikershandleiding'),
      icon: Icons.menu_book_outlined,
      keywords: const ['help', 'handleiding', 'documentatie'],
      onInvoke: () => DocumentReaderScreen.open(
        context,
        title: l10n.d('Gebruikershandleiding'),
        assetBase: 'docs/USER_GUIDE.md',
      ),
    ),
    PaletteCommand(
      label: l10n.d('Sneltoetsen'),
      icon: Icons.keyboard_outlined,
      keywords: const ['shortcuts', 'toetsen'],
      onInvoke: () => DocumentReaderScreen.open(
        context,
        title: l10n.d('Sneltoetsen'),
        assetBase: 'docs/SHORTCUTS.md',
      ),
    ),
  ];

  /// The security-module command-palette actions. Gated on the reveal flag:
  /// when the module is off they are **omitted entirely** (not shown greyed-out),
  /// matching how the security slide types are hidden from the add-slide picker
  /// and editor — the palette never offers a command the user can't run.
  /// Grouped here to keep [_openCommandPalette] under the method-length limit.
  List<PaletteCommand> _infoSafetyCommands(
    AppLocalizations l10n,
    Deck deck,
    DeckNotifier deckNotifier,
  ) {
    if (!ref.read(infoSafetyRevealProvider)) return const [];
    return [
      PaletteCommand(
        label: l10n.d('MIAUW-compliance'),
        icon: Icons.fact_check_outlined,
        keywords: const ['eis', 'compliance', 'miauw', 'waiver', 'audit'],
        onInvoke: () => MiauwCompliancePanel.show(context, deckNotifier),
      ),
      PaletteCommand(
        label: l10n.d('Bevindingen hernummeren'),
        icon: Icons.format_list_numbered,
        keywords: const ['finding', 'renumber', 'nummer', 'f-01'],
        onInvoke: deckNotifier.autoRenumberFindings,
      ),
      PaletteCommand(
        label: l10n.d('Scope-dekking controleren'),
        icon: Icons.travel_explore_outlined,
        keywords: const ['scope', 'coverage', 'gap', 'dekking'],
        onInvoke: () =>
            ScopeCoverageDialog.show(context, deckScopeCoverageGaps(deck)),
      ),
      PaletteCommand(
        label: l10n.d('Bewijs-hashes kopiëren'),
        icon: Icons.tag_outlined,
        keywords: const ['sha1', 'sha256', 'hash', 'bewijs', 'evidence'],
        onInvoke: _copyEvidenceHashes,
      ),
      PaletteCommand(
        label: l10n.d('Managementsamenvatting'),
        icon: Icons.summarize_outlined,
        keywords: const ['summary', 'management', 'samenvatting', 'overzicht'],
        onInvoke: () =>
            ManagementSummaryDialog.show(context, deckManagementSummary(deck)),
      ),
      PaletteCommand(
        label: l10n.d('RFC3161-tijdstempel'),
        icon: Icons.schedule_outlined,
        keywords: const ['rfc3161', 'timestamp', 'tijdstempel', 'tsa', 'seal'],
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

/// Tell a co-author when owner-drop handover changes their role
/// (COLLABORATION.md §5.3): a snackbar when the owner drops and they become the
/// temporary authority (their edits keep the session alive but are not saved),
/// and another when the owner returns and takes it back. Top-level, called once
/// from the layout's `build`, so it stays off `_MainLayoutState` and fires on the
/// transition rather than on every rebuild.
void listenCollabAuthorityChange(
  WidgetRef ref,
  BuildContext context,
  AppLocalizations l10n,
) {
  ref.listen(collabSessionProvider, (prev, next) {
    if (prev?.isTemporaryAuthority == next.isTemporaryAuthority) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next.isTemporaryAuthority
              ? l10n.d(
                  'De eigenaar is weg — jij houdt de samenwerking nu gaande; jouw wijzigingen worden pas bewaard als de eigenaar terugkomt.',
                )
              : l10n.d(
                  'De eigenaar is terug en neemt de samenwerking weer over.',
                ),
        ),
      ),
    );
  });
}

/// Collaboration actions for the command palette, shown only for a deck that
/// lives on WebDAV — the sidecar log the async transport needs has to live
/// somewhere (§5.7). While a session runs the only action is to leave it;
/// otherwise you can host one or join one an author already started for this
/// deck. Top-level, not a `_MainLayoutState` method, so it stays off the class.
List<PaletteCommand> collabPaletteCommands(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) {
  final session = ref.read(collabSessionProvider);
  // A running or connecting session offers only to leave it — plus copying the
  // invite link again when this tab is the Matrix host.
  if (session.isActive || session.isConnecting) {
    return [
      if (session.isMatrix && session.inviteLink != null)
        PaletteCommand(
          label: l10n.d('Uitnodigingslink kopiëren'),
          icon: Icons.copy,
          keywords: const ['invite', 'link', 'copy', 'matrix', 'uitnodiging'],
          onInvoke: () => _copyInvite(context, ref, l10n),
        ),
      if (session.isMatrix && session.isActive) ...[
        PaletteCommand(
          label: ref.read(collabChatOpenProvider)
              ? l10n.d('Chat sluiten')
              : l10n.d('Chat openen'),
          icon: Icons.forum_outlined,
          keywords: const [
            'chat',
            'bericht',
            'message',
            'matrix',
            'samenwerken',
          ],
          onInvoke: () {
            final open = ref.read(collabChatOpenProvider);
            ref.read(collabChatOpenProvider.notifier).state = !open;
          },
        ),
        PaletteCommand(
          label: l10n.d('Deelnemers verifiëren'),
          icon: Icons.verified_user_outlined,
          keywords: const [
            'verify',
            'verifiëren',
            'fingerprint',
            'vingerafdruk',
            'matrix',
            'apparaat',
          ],
          onInvoke: () => _verifyParticipants(context, ref, l10n),
        ),
      ],
      PaletteCommand(
        label: l10n.d('Samenwerking verlaten'),
        icon: Icons.link_off,
        keywords: const ['collab', 'samenwerken', 'leave', 'stop'],
        onInvoke: () => _leaveCollab(context, ref, l10n),
      ),
    ];
  }
  // WebDAV collaboration needs the deck on a WebDAV source (the sidecar log,
  // §5.7); realtime Matrix needs only the app-global account (§6). Either or both
  // may be available — show what applies.
  final canWebdav = ref.read(collabSessionProvider.notifier).canCollaborate;
  // Matrix host/join only when the module and its Matrix transport are on
  // *and* an account is configured to host/join with.
  final hasMatrix =
      ref.read(matrixCollabActiveProvider) &&
      (ref.read(matrixAccountProvider)?.isConfigured ?? false);
  return [
    if (canWebdav) ...[
      PaletteCommand(
        label: l10n.d('Samenwerking starten'),
        icon: Icons.groups_outlined,
        keywords: const ['collab', 'samenwerken', 'webdav', 'share', 'host'],
        onInvoke: () => _beginCollab(context, ref, l10n, host: true),
      ),
      PaletteCommand(
        label: l10n.d('Deelnemen aan samenwerking'),
        icon: Icons.group_add_outlined,
        keywords: const ['collab', 'samenwerken', 'join', 'webdav'],
        onInvoke: () => _beginCollab(context, ref, l10n, host: false),
      ),
    ],
    if (hasMatrix) ...[
      PaletteCommand(
        label: l10n.d('Realtime samenwerken starten'),
        icon: Icons.cast_connected_outlined,
        keywords: const [
          'collab',
          'matrix',
          'realtime',
          'live',
          'host',
          'samenwerken',
        ],
        onInvoke: () => _beginMatrixCollab(context, ref, l10n, host: true),
      ),
      PaletteCommand(
        label: l10n.d('Deelnemen via een link'),
        icon: Icons.link,
        keywords: const [
          'collab',
          'matrix',
          'realtime',
          'live',
          'join',
          'link',
          'samenwerken',
        ],
        onInvoke: () => _beginMatrixCollab(context, ref, l10n, host: false),
      ),
    ],
  ];
}

/// Start or join a realtime Matrix session. The outcome — the host's invite
/// dialog, a guest going live, or a failure — is surfaced by [listenMatrixCollab]
/// on the phase transition, because a guest only goes active once the baseline
/// arrives over the sync loop, well after this returns.
Future<void> _beginMatrixCollab(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n, {
  required bool host,
}) async {
  final notifier = ref.read(collabSessionProvider.notifier);
  if (host) {
    await notifier.hostMatrix();
    return;
  }
  final link = await promptMatrixInvite(context, l10n);
  if (link == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.d('Verbinden met de samenwerking…'))),
  );
  await notifier.joinMatrix(link);
}

/// Show the session's devices and their fingerprints for out-of-band comparison.
void _verifyParticipants(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) {
  final notifier = ref.read(collabSessionProvider.notifier);
  showMatrixParticipantsDialog(
    context,
    l10n,
    participants: notifier.matrixParticipants,
    onPin: notifier.pinParticipant,
    onUnpin: notifier.unpinParticipant,
  );
}

/// Copy the current Matrix invite link again (the host may need to re-share it).
Future<void> _copyInvite(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  final link = ref.read(collabSessionProvider).inviteLink;
  if (link == null) return;
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.d('Uitnodigingslink gekopieerd.'))),
  );
}

/// Surface the outcome of a Matrix session as it settles: the host's invite
/// dialog when it goes active, a "you are live" note for a guest, and the
/// localised reason on failure. Top-level and called once from the layout build,
/// like [listenCollabAuthorityChange]; it ignores WebDAV sessions (`isMatrix`).
void listenMatrixCollab(
  WidgetRef ref,
  BuildContext context,
  AppLocalizations l10n,
) {
  ref.listen(collabSessionProvider, (prev, next) {
    if (!next.isMatrix || prev?.phase == next.phase) return;
    switch (next.phase) {
      case CollabPhase.active:
        if (next.role == CollabRole.host && next.inviteLink != null) {
          showMatrixInviteDialog(context, l10n, next.inviteLink!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.d('Je doet nu live mee aan de samenwerking.')),
            ),
          );
        }
      case CollabPhase.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_matrixCollabError(next.error, l10n))),
        );
      case CollabPhase.connecting:
      case CollabPhase.idle:
        break;
    }
  });
}

/// A Matrix session failure key mapped to a message that says what to do next.
String _matrixCollabError(
  String? error,
  AppLocalizations l10n,
) => switch (error) {
  'no-matrix-account' => l10n.d(
    'Stel eerst een Matrix-account in bij Instellingen → Samenwerken.',
  ),
  'no-deck' => l10n.d('Open eerst een presentatie om aan samen te werken.'),
  'bad-invite' => l10n.d('Dat is geen geldige uitnodigingslink.'),
  'join-timeout' => l10n.d(
    'De gastheer reageerde niet op tijd. Controleer de link en of de gastheer nog online is.',
  ),
  'matrix-auth' => l10n.d(
    'Je Matrix-account wordt geweigerd — controleer het access-token bij Instellingen.',
  ),
  'matrix-network' => l10n.d('De Matrix-homeserver is niet bereikbaar.'),
  _ => l10n.d('Realtime samenwerken is mislukt.'),
};

Future<void> _beginCollab(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n, {
  required bool host,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(collabSessionProvider.notifier);
  host ? await notifier.host() : await notifier.join();
  if (!context.mounted) return;
  final state = ref.read(collabSessionProvider);
  final String message;
  if (state.isActive) {
    message = host
        ? l10n.d('Samenwerking gestart.')
        : l10n.d('Deelgenomen aan de samenwerking.');
  } else if (state.error == 'no-baseline') {
    message = l10n.d('Nog geen samenwerking gestart voor dit deck.');
  } else {
    message = l10n.d('Samenwerking mislukt.');
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _leaveCollab(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(collabSessionProvider.notifier).leave();
  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.d('Samenwerking beëindigd.'))),
  );
}

/// Een grafiek kon zijn databestand niet lezen of niet schrijven: ontbrekend,
/// onleesbaar, buiten de projectmap, of intussen buiten de app gewijzigd.
///
/// Melden is hier het hele punt. Bij het openen tekent zo'n grafiek leeg, en
/// een lege grafiek is niet te onderscheiden van een grafiek waar nog geen
/// cijfers in staan. Bij het opslaan weegt het zwaarder: de markdown draagt
/// dan alleen nog de verwijzing, dus die cijfers bestaan enkel nog in dit
/// venster — een geslaagde opslag melden zou ronduit misleidend zijn. Vandaar
/// twee teksten, en bij het opslaan de foutkleur.
void _listenChartDataWarning(BuildContext context, WidgetRef ref) {
  ref.listen<ChartDataWarning?>(chartDataWarningProvider, (_, warning) {
    if (warning == null) return;
    ref.read(chartDataWarningProvider.notifier).state = null;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final sources = warning.sources.join(', ');
    if (warning.whileSaving) {
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Grafiekcijfers zijn niet opgeslagen — ze staan alleen nog in dit venster:')} '
        '$sources',
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          '${l10n.d('Grafiekdata kon niet worden gelezen; die grafieken blijven leeg:')} '
          '$sources',
        ),
      ),
    );
  });
}

/// #1953: het crashherstel kon zijn snapshot niet wegschrijven. Eén keer per
/// sessie — niet elke 25 s herhalen. Foutkleur: de belofte dat onopgeslagen
/// werk terugkomt na een crash geldt nu niet, en dat is iets dat de gebruiker
/// moet weten vóórdat hij op de vangnetten leunt.
void _listenRecoveryWriteError(BuildContext context, WidgetRef ref) {
  ref.listen<bool>(recoveryWriteErrorProvider, (_, failed) {
    if (!failed) return;
    ref.read(recoveryWriteErrorProvider.notifier).state = false;
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      context.l10n,
      context.l10n.d(
        'Crashherstel werkt nu niet — de herstelmap is niet beschrijfbaar. Sla je werk handmatig op.',
      ),
    );
  });
}

/// Een zojuist geopend bestand heeft elders een byte-identieke kopie:
/// niet-blokkerend melden (de gebruiker wilde gewoon openen), met de
/// opruimdialoog als directe ingang. Top-level (net als [_listenChartDataWarning])
/// zodat de listener-bedrading niet in `_AppShellState.build` of het
/// hoofdbestand hoeft te wonen.
void _listenDuplicateCopyNotice(BuildContext context, WidgetRef ref) {
  ref.listen<DuplicateCopyNotice?>(duplicateCopyNoticeProvider, (_, notice) {
    if (notice == null) return;
    ref.read(duplicateCopyNoticeProvider.notifier).state = null;
    final l10n = context.l10n;
    final homeDir = ref.read(settingsProvider).homeDirectory;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 7),
        content: Text(
          '${l10n.d('Deze presentatie staat ook op een andere plek:')} '
          '${displayFolder(notice.copyPath, homeDir: homeDir, osHome: osHomeDirectory)}',
        ),
        action: TrashService().isSupported
            ? SnackBarAction(
                label: l10n.d('Opruimen…'),
                onPressed: () => DuplicateCleanupDialog.show(
                  context,
                  groups: [
                    CleanupGroup(
                      title: p.basenameWithoutExtension(notice.openedPath),
                      paths: [notice.openedPath, notice.copyPath],
                    ),
                  ],
                  homeDir: homeDir,
                ),
              )
            : null,
      ),
    );
  });
}

/// De ingestelde thuismap stond op een onbereikbaar volume (bv. een
/// losgekoppelde netwerkschijf): de import viel terug op de documentenmap zodat
/// de presentatie tóch opende. Niet-blokkerend melden zodat de gebruiker weet
/// dat zijn locatie weg is — zelfde luister-patroon als [_listenDuplicateCopyNotice].
void _listenImportHomeUnavailable(BuildContext context, WidgetRef ref) {
  ref.listen<String?>(importHomeUnavailableProvider, (_, unavailable) {
    if (unavailable == null) return;
    ref.read(importHomeUnavailableProvider.notifier).state = null;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          '${l10n.d('De ingestelde map is niet beschikbaar; de presentatie is in de documentenmap geopend:')} '
          '$unavailable',
        ),
      ),
    );
  });
}

/// OpenKAT-menu-items voor het …-menu. Top-level zodat `_MainLayoutState`
/// onder het klasseplafond blijft.
List<PopupMenuEntry<String>> openKatShellMenuEntries(
  WidgetRef ref,
  AppLocalizations l10n,
  PopupMenuItem<String> Function(String, IconData, String) menuItem,
) {
  if (!supportsLocalProjectFolders ||
      !ref.watch(openKatIntegrationRevealProvider)) {
    return const [];
  }
  return [
    menuItem(
      'import_openkat',
      Icons.radar_outlined,
      openKatLabel(l10n, updating: hasActiveOpenKatReport(ref)),
    ),
    menuItem(
      'openkat_add_server',
      Icons.add_link,
      l10n.d('OpenKAT-server toevoegen…'),
    ),
    menuItem(
      'openkat_server_report',
      Icons.cloud_download_outlined,
      l10n.d('Rapportage van OpenKAT-server…'),
    ),
  ];
}

/// OpenKAT-acties in het commandopalet; zelfde reveal- en desktop-poort als het menu.
List<PaletteCommand> openKatPaletteCommands(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) {
  if (!ref.read(openKatIntegrationRevealProvider) ||
      !supportsLocalProjectFolders) {
    return const [];
  }
  return [
    PaletteCommand(
      label: openKatLabel(l10n, updating: hasActiveOpenKatReport(ref)),
      icon: Icons.radar_outlined,
      keywords: const ['openkat', 'import', 'rapport', 'map'],
      onInvoke: () => importOpenKatReports(context, ref),
    ),
    PaletteCommand(
      label: l10n.d('OpenKAT-server toevoegen…'),
      icon: Icons.add_link,
      keywords: const ['openkat', 'server', 'installatie', 'rocky'],
      onInvoke: () => showOpenKatInstallationWizard(context),
    ),
    PaletteCommand(
      label: l10n.d('Rapportage van OpenKAT-server…'),
      icon: Icons.cloud_download_outlined,
      keywords: const ['openkat', 'server', 'rapportage', 'live'],
      onInvoke: () => showOpenKatServerReportDialog(context),
    ),
  ];
}

/// Eén dispatch voor alle OpenKAT-menu-acties.
Future<void> dispatchOpenKatShellAction(
  BuildContext context,
  WidgetRef ref,
  String action,
) async {
  switch (action) {
    case 'import_openkat':
      await importOpenKatReports(context, ref);
    case 'openkat_add_server':
      await showOpenKatInstallationWizard(context);
    case 'openkat_server_report':
      await showOpenKatServerReportDialog(context);
  }
}
