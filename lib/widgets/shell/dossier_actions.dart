// Part of the app_shell library — see ../app_shell.dart.
part of '../app_shell.dart';

class _DossierController {
  _DossierController(this.host);

  final _AppShellState host;
  BuildContext get context => host.context;
  WidgetRef get ref => host.ref;
  void _refreshDossier(VoidCallback change) => host._refreshDossier(change);

  DocumentDossierStore? _dossierStore;
  DocumentDossier? _dossier;
  bool _showDossier = false;
  bool _dossierBusy = false;
  final Map<String, DossierIntegrityStatus> _dossierVerification = {};

  Widget _dossierWorkspace(TabsState tabsState) => Column(
    children: [
      _AppTabBar(
        tabsState: tabsState,
        dossierTitle: _dossier?.title,
        dossierActive: _showDossier,
        onDossierSelect: () => _refreshDossier(() => _showDossier = true),
        onNewDossier: isWebPlatform ? null : () => unawaited(_newDossier()),
        onOpenDossier: isWebPlatform ? null : () => unawaited(_openDossier()),
        onSelect: (i) {
          ref.read(tabsProvider.notifier).selectTab(i);
          _refreshDossier(() => _showDossier = false);
        },
        onClose: host._onCloseTab,
        onAdd: () => ref.read(tabsProvider.notifier).newEmptyTab(),
      ),
      Expanded(
        child: Column(
          children: [
            if (!_showDossier &&
                _dossier != null &&
                _dossierContainsTab(tabsState.current))
              _dossierReturnBar(),
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: tabsState.clampedIndex,
                    children: _tabScopes(tabsState),
                  ),
                  if (_showDossier && _dossier != null)
                    Positioned.fill(child: _dossierOverview()),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _newDossier() async {
    if (isWebPlatform) return;
    final title = await DossierDialogs.editTitle(
      context,
      initialTitle: '',
      creating: true,
    );
    if (title == null || title.trim().isEmpty || !context.mounted) return;
    final parent = await getDirectoryPath();
    if (parent == null || !context.mounted) return;
    final name = sanitizeFilename(title.trim(), fallback: 'dossier');
    final folder = Directory(p.join(parent, name));
    if (await folder.exists()) {
      if (!context.mounted) return;
      _dossierMessage(
        context.l10n.d('Deze dossiermap bestaat al. Kies een andere naam.'),
      );
      return;
    }
    final store = DocumentDossierStore(
      File(p.join(folder.path, 'dossier.json')),
    );
    try {
      final dossier = await store.create(title.trim());
      if (!context.mounted) return;
      _refreshDossier(() {
        _dossierStore = store;
        _dossier = dossier;
        _showDossier = true;
        _dossierVerification.clear();
      });
    } catch (error, stack) {
      logError('Dossierhandeling mislukt', error, stack);
      if (context.mounted) {
        _dossierMessage(
          context.l10n.d('Het dossier kon niet worden aangemaakt.'),
        );
      }
    }
  }

  Future<void> _openDossier() async {
    if (isWebPlatform) return;
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: context.l10n.d('OciDeck dossier'),
          extensions: ['json'],
        ),
      ],
    );
    if (file == null || !context.mounted) return;
    final store = DocumentDossierStore(File(file.path));
    try {
      final dossier = await store.load();
      if (!context.mounted) return;
      _refreshDossier(() {
        _dossierStore = store;
        _dossier = dossier;
        _showDossier = true;
        _dossierVerification.clear();
      });
      final all = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.d('Dossier openen')),
          content: Text(
            context.l10n.d('Wil je de bijlagen ook in tabbladen openen?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.d('Alleen overzicht')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.d('Overzicht en bijlagen')),
            ),
          ],
        ),
      );
      if (all == true && context.mounted) await _openAllDossierEntries();
    } catch (error, stack) {
      logError('Dossierhandeling mislukt', error, stack);
      if (context.mounted) {
        _dossierMessage(context.l10n.d('Dit dossier kon niet worden geopend.'));
      }
    }
  }

  Widget _dossierOverview() => DossierOverview(
    dossier: _dossier!,
    busy: _dossierBusy,
    verification: _dossierVerification,
    onOpenEntry: (entry) => unawaited(_openDossierEntry(entry)),
    onOpenAll: () => unawaited(_openAllDossierEntries()),
    onOpenAsDocument: () => unawaited(_openDossierOverviewDocument()),
    onAdd: () => unawaited(_addDossierEntries()),
    onVerifyEntry: (entry) => unawaited(_verifyDossierEntry(entry)),
    onVerifyAll: () => unawaited(_verifyAllDossierEntries()),
    onRefreshReference: (entry) => unawaited(_refreshDossierReference(entry)),
    onRenameEntry: (entry, title) => unawaited(
      _changeDossier(
        (d) => d.copyWith(
          entries: [
            for (final e in d.entries)
              e.id == entry.id ? e.copyWith(title: title) : e,
          ],
        ),
      ),
    ),
    onRemoveEntry: (entry) => unawaited(
      _changeDossier(
        (d) => d.copyWith(
          entries: [
            for (final e in d.entries)
              if (e.id != entry.id) e,
          ],
        ),
      ),
    ),
    onReorder: (from, to) => unawaited(
      _changeDossier((d) {
        final entries = [...d.entries];
        final item = entries.removeAt(from);
        entries.insert(to, item);
        return d.copyWith(entries: entries);
      }),
    ),
    onRenameDossier: (title) =>
        unawaited(_changeDossier((d) => d.copyWith(title: title))),
  );

  Widget _dossierReturnBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _refreshDossier(() => _showDossier = true),
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(context.l10n.d('Terug naar dossier')),
        ),
      ),
    ),
  );

  bool _dossierContainsTab(TabInfo? tab) {
    final path = tab?.openFilePath;
    if (path == null || _dossierStore == null || _dossier == null) return false;
    final root = _dossierStore!.directory.absolute.path;
    if (p.normalize(path) == p.normalize(p.join(root, 'overzicht.md'))) {
      return true;
    }
    return _dossier!.entries.any(
      (e) => p.normalize(p.join(root, e.relativePath)) == p.normalize(path),
    );
  }

  bool _dossierOverviewIsDirty() {
    final store = _dossierStore;
    if (store == null) return false;
    final overviewPath = p.normalize(
      p.join(store.directory.path, 'overzicht.md'),
    );
    return ref
        .read(tabsProvider)
        .tabs
        .any(
          (tab) =>
              p.normalize(tab.openFilePath ?? '') == overviewPath &&
              tab.isDirty,
        );
  }

  Future<void> _changeDossier(
    DocumentDossier Function(DocumentDossier) change,
  ) async {
    final current = _dossier;
    final store = _dossierStore;
    if (current == null || store == null || _dossierBusy) return;
    if (_dossierOverviewIsDirty()) {
      _dossierMessage(
        context.l10n.d(
          'Sla wijzigingen in het overzichtsdocument eerst op of sluit dat tabblad.',
        ),
      );
      return;
    }
    final updated = change(current).copyWith(updatedAt: DateTime.now().toUtc());
    _refreshDossier(() => _dossierBusy = true);
    try {
      await store.save(updated);
      if (context.mounted) _refreshDossier(() => _dossier = updated);
    } catch (error, stack) {
      logError('Dossierhandeling mislukt', error, stack);
      if (context.mounted) {
        _dossierMessage(context.l10n.d('Wijziging opslaan is mislukt.'));
      }
    } finally {
      if (context.mounted) _refreshDossier(() => _dossierBusy = false);
    }
  }

  Future<void> _addDossierEntries() async {
    final store = _dossierStore;
    if (store == null || _dossier == null || _dossierBusy) return;
    if (_dossierOverviewIsDirty()) {
      _dossierMessage(
        context.l10n.d(
          'Sla wijzigingen in het overzichtsdocument eerst op of sluit dat tabblad.',
        ),
      );
      return;
    }
    final paths = await ref.read(fileServiceProvider).pickMarkdownFiles();
    if (paths.isEmpty || !context.mounted) return;
    _refreshDossier(() => _dossierBusy = true);
    try {
      var dossier = _dossier!;
      var skipped = 0;
      for (final path in paths) {
        if (p.extension(path).toLowerCase() != '.md') {
          skipped++;
          continue;
        }
        dossier = await store.addFile(dossier, File(path));
        if (!context.mounted) return;
        _refreshDossier(() => _dossier = dossier);
      }
      if (skipped > 0 && context.mounted) {
        _dossierMessage(
          context.l10n.d(
            'Alleen Markdown-documenten en -presentaties (.md) kunnen worden toegevoegd.',
          ),
        );
      }
    } catch (error, stack) {
      logError('Dossierhandeling mislukt', error, stack);
      if (context.mounted) {
        _dossierMessage(
          context.l10n.d('Een bijlage kon niet worden toegevoegd.'),
        );
      }
    } finally {
      if (context.mounted) _refreshDossier(() => _dossierBusy = false);
    }
  }

  Future<void> _openDossierEntry(DossierEntry entry) async {
    final path = await _dossierStore?.resolvedPath(entry);
    if (path == null || !context.mounted) {
      if (context.mounted) {
        _dossierMessage(context.l10n.d('Deze bijlage is niet beschikbaar.'));
      }
      return;
    }
    final outcome = await ref.read(tabsProvider.notifier).openFileByPath(path);
    if (!context.mounted) return;
    if (outcome == OpenResult.opened) {
      _refreshDossier(() => _showDossier = false);
    } else {
      _dossierMessage(
        context.l10n.d('Deze bijlage kon niet veilig worden geopend.'),
      );
    }
  }

  Future<void> _openDossierOverviewDocument() async {
    final store = _dossierStore;
    if (store == null) return;
    final path = p.join(store.directory.path, 'overzicht.md');
    final outcome = await ref.read(tabsProvider.notifier).openFileByPath(path);
    if (!context.mounted) return;
    if (outcome == OpenResult.opened) {
      _refreshDossier(() => _showDossier = false);
    } else {
      _dossierMessage(
        context.l10n.d('Het overzicht kon niet als document worden geopend.'),
      );
    }
  }

  Future<void> _openAllDossierEntries() async {
    final dossier = _dossier;
    if (dossier == null || _dossierBusy) return;
    _refreshDossier(() => _dossierBusy = true);
    try {
      for (final entry in dossier.entries) {
        if (!context.mounted) return;
        await _openDossierEntry(entry);
      }
      if (context.mounted) _refreshDossier(() => _showDossier = true);
    } finally {
      if (context.mounted) _refreshDossier(() => _dossierBusy = false);
    }
  }

  Future<void> _verifyDossierEntry(DossierEntry entry) async {
    final result = await _dossierStore?.verify(entry);
    if (result != null && context.mounted) {
      _refreshDossier(() => _dossierVerification[entry.id] = result.status);
    }
  }

  Future<void> _refreshDossierReference(DossierEntry entry) async {
    final store = _dossierStore;
    final dossier = _dossier;
    if (store == null || dossier == null || _dossierBusy) return;
    if (_dossierOverviewIsDirty()) {
      _dossierMessage(
        context.l10n.d(
          'Sla wijzigingen in het overzichtsdocument eerst op of sluit dat tabblad.',
        ),
      );
      return;
    }
    final result = await store.verify(entry);
    if (!context.mounted) return;
    final actual = result.actualSha256;
    if (actual == null) {
      _dossierMessage(
        context.l10n.d('Deze bijlage kan niet worden gecontroleerd.'),
      );
      return;
    }
    if (actual == entry.sha256) {
      _dossierMessage(context.l10n.d('De SHA-256 klopt al.'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.d('Nieuwe versie vastleggen?')),
        content: SelectableText(
          '${dialogContext.l10n.d('Vastgelegde SHA-256')}\n${entry.sha256}\n\n'
          '${dialogContext.l10n.d('Huidige SHA-256')}\n$actual\n\n'
          '${dialogContext.l10n.d('Hiermee wordt de nieuwe bestandsversie de referentie voor dit dossier.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.d('Vastleggen')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    _refreshDossier(() => _dossierBusy = true);
    try {
      final updated = await store.refreshReference(
        dossier,
        entry.id,
        expectedSha256: actual,
      );
      if (!context.mounted) return;
      _refreshDossier(() {
        _dossier = updated;
        _dossierVerification[entry.id] = DossierIntegrityStatus.matches;
      });
    } catch (error, stack) {
      logError('Dossierhandeling mislukt', error, stack);
      if (context.mounted) {
        _dossierMessage(
          context.l10n.d(
            'Het bestand veranderde of kon niet worden vastgelegd. Controleer opnieuw.',
          ),
        );
      }
    } finally {
      if (context.mounted) _refreshDossier(() => _dossierBusy = false);
    }
  }

  Future<void> _verifyAllDossierEntries() async {
    final dossier = _dossier;
    if (dossier == null || _dossierBusy) return;
    _refreshDossier(() => _dossierBusy = true);
    try {
      for (final entry in dossier.entries) {
        await _verifyDossierEntry(entry);
      }
    } finally {
      if (context.mounted) _refreshDossier(() => _dossierBusy = false);
    }
  }

  void _dossierMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}
