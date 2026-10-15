import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/document_dossier.dart';
import '../../services/document_dossier_store.dart';
import '../../theme/app_theme.dart';
import 'dossier_dialogs.dart';

/// The dossier is a document in its own right, with its own cover and contents.
class DossierOverview extends StatelessWidget {
  const DossierOverview({
    super.key,
    required this.dossier,
    required this.onOpenEntry,
    required this.onOpenAll,
    required this.onOpenAsDocument,
    required this.onAdd,
    required this.onVerifyEntry,
    required this.onVerifyAll,
    required this.onRefreshReference,
    required this.onRenameEntry,
    required this.onRemoveEntry,
    required this.onReorder,
    required this.onRenameDossier,
    this.verification = const {},
    this.busy = false,
  });

  final DocumentDossier dossier;
  final ValueChanged<DossierEntry> onOpenEntry;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenAsDocument;
  final VoidCallback onAdd;
  final ValueChanged<DossierEntry> onVerifyEntry;
  final VoidCallback onVerifyAll;
  final ValueChanged<DossierEntry> onRefreshReference;
  final void Function(DossierEntry, String) onRenameEntry;
  final ValueChanged<DossierEntry> onRemoveEntry;
  final ReorderCallback onReorder;
  final ValueChanged<String> onRenameDossier;
  final Map<String, DossierIntegrityStatus> verification;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context));
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 730;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1050),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 38,
                    compact ? 20 : 36,
                    compact ? 16 : 38,
                    56,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cover(context, palette, compact),
                      const SizedBox(height: 24),
                      if (dossier.entries.isEmpty)
                        _emptyState(context, palette)
                      else ...[
                        _contentsHeader(context, palette, compact),
                        const SizedBox(height: 12),
                        _contents(context, palette, compact),
                        const SizedBox(height: 16),
                        Text(
                          l10n.d(
                            'Gebruik de handgreep of de pijlen om de volgorde te wijzigen. De nummers volgen automatisch.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.mutedText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cover(BuildContext context, AppPalette palette, bool compact) {
    final l10n = context.l10n;
    final title = dossier.title.trim().isEmpty
        ? l10n.d('Naamloos dossier')
        : dossier.title;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.navy, AppTheme.blueVivid, AppTheme.blue500],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.blueVivid.withValues(alpha: 0.16),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -75,
            top: -90,
            child: IgnorePointer(
              child: Container(
                width: 310,
                height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 38,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 24 : 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_stories_rounded,
                      color: AppTheme.amberVivid,
                      size: 25,
                    ),
                    const SizedBox(width: 11),
                    Text(
                      l10n.d('DOSSIER'),
                      style: const TextStyle(
                        color: AppTheme.amberVivid,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.d('Dossiertitel wijzigen'),
                      onPressed: busy
                          ? null
                          : () async {
                              final changed = await DossierDialogs.editTitle(
                                context,
                                initialTitle: dossier.title,
                              );
                              if (changed != null && changed != dossier.title) {
                                onRenameDossier(changed);
                              }
                            },
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 29 : 42,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${dossier.entries.length} ${l10n.d('documenten')}  ·  ${l10n.d('Inhoudsopgave en integriteitscontrole')}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                _coverActions(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverActions(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.d('Documenten toevoegen')),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.amberVivid,
            foregroundColor: AppTheme.navy,
          ),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onOpenAsDocument,
          icon: const Icon(Icons.description_outlined),
          label: Text(l10n.d('Als document openen')),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
          ),
        ),
        if (dossier.entries.isNotEmpty) ...[
          OutlinedButton.icon(
            onPressed: busy ? null : onOpenAll,
            icon: const Icon(Icons.tab_rounded),
            label: Text(l10n.d('Alle documenten openen')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : onVerifyAll,
            icon: const Icon(Icons.verified_outlined),
            label: Text(l10n.d('Alles controleren')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _emptyState(BuildContext context, AppPalette palette) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 54),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 56,
            color: palette.accentInk,
          ),
          const SizedBox(height: 18),
          Text(
            l10n.d('Een goed dossier begint hier'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.panelText,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.d(
              'Voeg documenten toe. Ze worden als kopie bij dit dossier bewaard en verschijnen hier in jouw volgorde.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _contentsHeader(
    BuildContext context,
    AppPalette palette,
    bool compact,
  ) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(
            l10n.d('Inhoudsopgave'),
            style: TextStyle(
              color: palette.panelText,
              fontSize: compact ? 22 : 27,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${dossier.entries.length} ${l10n.d('documenten')}',
            style: TextStyle(color: palette.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _contents(BuildContext context, AppPalette palette, bool compact) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: dossier.entries.length,
      onReorderItem: busy ? (_, _) {} : onReorder,
      proxyDecorator: (child, _, animation) => Material(
        elevation: 12,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
      itemBuilder: (context, index) => Padding(
        key: ValueKey(dossier.entries[index].id),
        padding: const EdgeInsets.only(bottom: 10),
        child: _entryCard(
          context,
          palette,
          dossier.entries[index],
          index,
          compact,
        ),
      ),
    );
  }

  Widget _entryCard(
    BuildContext context,
    AppPalette palette,
    DossierEntry entry,
    int index,
    bool compact,
  ) {
    final l10n = context.l10n;
    final status = verification[entry.id];
    final (icon, label, color) = _status(context, status, palette);
    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.panelText.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 10 : 12,
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: l10n.d('Sleep om te ordenen'),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: palette.mutedText,
                  ),
                ),
              ),
            ),
            Container(
              width: compact ? 37 : 48,
              height: compact ? 37 : 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.accentInk.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${index + 1}'.padLeft(2, '0'),
                style: TextStyle(
                  color: palette.accentInk,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 15 : 18,
                ),
              ),
            ),
            SizedBox(width: compact ? 10 : 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: busy ? null : () => onOpenEntry(entry),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.panelText,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 14 : 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      '${l10n.d('SHA-256')} ${entry.sha256}',
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: compact ? 10 : 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.d('Document openen'),
              onPressed: busy ? null : () => onOpenEntry(entry),
              icon: Icon(Icons.open_in_new_rounded, color: palette.accentInk),
            ),
            _entryActions(context, palette, entry, index),
          ],
        ),
      ),
    );
  }

  Widget _entryActions(
    BuildContext context,
    AppPalette palette,
    DossierEntry entry,
    int index,
  ) {
    final l10n = context.l10n;
    return PopupMenuButton<_EntryAction>(
      tooltip: l10n.d('Meer opties'),
      enabled: !busy,
      icon: Icon(Icons.more_vert_rounded, color: palette.mutedText),
      onSelected: (action) => _act(context, entry, index, action),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _EntryAction.verify,
          child: _menuRow(
            Icons.verified_outlined,
            l10n.d('SHA-256 controleren'),
          ),
        ),
        PopupMenuItem(
          value: _EntryAction.refresh,
          child: _menuRow(
            Icons.update_rounded,
            l10n.d('Nieuwe versie vastleggen'),
          ),
        ),
        PopupMenuItem(
          value: _EntryAction.rename,
          child: _menuRow(Icons.edit_outlined, l10n.d('Titel wijzigen')),
        ),
        if (index > 0)
          PopupMenuItem(
            value: _EntryAction.up,
            child: _menuRow(
              Icons.arrow_upward_rounded,
              l10n.d('Omhoog verplaatsen'),
            ),
          ),
        if (index < dossier.entries.length - 1)
          PopupMenuItem(
            value: _EntryAction.down,
            child: _menuRow(
              Icons.arrow_downward_rounded,
              l10n.d('Omlaag verplaatsen'),
            ),
          ),
        PopupMenuItem(
          value: _EntryAction.remove,
          child: _menuRow(
            Icons.remove_circle_outline,
            l10n.d('Uit dossier verwijderen'),
          ),
        ),
      ],
    );
  }

  Widget _menuRow(IconData icon, String label) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)],
  );

  void _act(
    BuildContext context,
    DossierEntry entry,
    int index,
    _EntryAction action,
  ) async {
    switch (action) {
      case _EntryAction.verify:
        onVerifyEntry(entry);
      case _EntryAction.refresh:
        onRefreshReference(entry);
      case _EntryAction.rename:
        final changed = await DossierDialogs.editTitle(
          context,
          initialTitle: entry.title,
        );
        if (changed != null && changed != entry.title) {
          onRenameEntry(entry, changed);
        }
      case _EntryAction.up:
        onReorder(index, index - 1);
      case _EntryAction.down:
        onReorder(index, index + 1);
      case _EntryAction.remove:
        final confirmed = await DossierDialogs.confirmRemove(
          context,
          title: entry.title,
        );
        if (confirmed) onRemoveEntry(entry);
    }
  }

  (IconData, String, Color) _status(
    BuildContext context,
    DossierIntegrityStatus? status,
    AppPalette palette,
  ) {
    final l10n = context.l10n;
    return switch (status) {
      DossierIntegrityStatus.matches => (
        Icons.check_circle_rounded,
        l10n.d('SHA-256 klopt'),
        AppTheme.successFg,
      ),
      DossierIntegrityStatus.changed => (
        Icons.error_rounded,
        l10n.d('Document gewijzigd'),
        Theme.of(context).colorScheme.error,
      ),
      DossierIntegrityStatus.missing => (
        Icons.error_outline_rounded,
        l10n.d('Document ontbreekt'),
        Theme.of(context).colorScheme.error,
      ),
      DossierIntegrityStatus.unreadable => (
        Icons.warning_rounded,
        l10n.d('Document niet leesbaar'),
        Theme.of(context).colorScheme.error,
      ),
      DossierIntegrityStatus.unsafe => (
        Icons.warning_rounded,
        l10n.d('Onveilige bestandsverwijzing'),
        Theme.of(context).colorScheme.error,
      ),
      null => (
        Icons.shield_outlined,
        l10n.d('Nog niet gecontroleerd'),
        palette.mutedText,
      ),
    };
  }
}

enum _EntryAction { verify, refresh, rename, up, down, remove }
