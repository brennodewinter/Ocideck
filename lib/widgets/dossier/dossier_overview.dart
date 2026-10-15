import 'package:material_ui/material_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../models/document_dossier.dart';
import '../../services/document_dossier_store.dart';
import '../../theme/app_theme.dart';
import 'dossier_dialogs.dart';
part 'dossier_overview_action.dart';

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
    required this.onEditEntryDetails,
    required this.onRemoveEntry,
    required this.onReorder,
    required this.onRenameDossier,
    this.verification = const {},
    this.busy = false,
    this.openingProgress,
    this.openingTotal,
    this.onCancelOpening,
    this.verificationProgress,
    this.verificationTotal,
    this.unsavedEntryIds = const {},
    this.onChangeDescription,
    this.onChangeStartNumber,
    this.onChangeEntryNumber,
    this.onSuggestEntryDetails,
    this.onExportPdf,
  });
  final DocumentDossier dossier;
  final ValueChanged<DossierEntry> onOpenEntry;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenAsDocument;
  final VoidCallback onAdd;
  final ValueChanged<DossierEntry> onVerifyEntry;
  final VoidCallback onVerifyAll;
  final ValueChanged<DossierEntry> onRefreshReference;
  final void Function(DossierEntry, DossierEntryDetails) onEditEntryDetails;
  final ValueChanged<DossierEntry> onRemoveEntry;
  final ReorderCallback onReorder;
  final ValueChanged<String> onRenameDossier;
  final Map<String, DossierIntegrityStatus> verification;
  final bool busy;
  final int? openingProgress;
  final int? openingTotal;
  final VoidCallback? onCancelOpening;
  final int? verificationProgress;
  final int? verificationTotal;
  final Set<String> unsavedEntryIds;
  final ValueChanged<String>? onChangeDescription;
  final ValueChanged<int>? onChangeStartNumber;
  final void Function(DossierEntry, int?)? onChangeEntryNumber;
  final Future<DossierEntryDetails?> Function(DossierEntry)?
  onSuggestEntryDetails;
  final VoidCallback? onExportPdf;
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
                      if (openingProgress != null && openingTotal != null) ...[
                        const SizedBox(height: 16),
                        _openingProgress(context, palette),
                      ],
                      if (verificationProgress != null &&
                          verificationTotal != null) ...[
                        const SizedBox(height: 16),
                        _verificationProgress(context, palette),
                      ],
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.72),
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

  Widget _openingProgress(BuildContext context, AppPalette palette) {
    final l10n = context.l10n;
    final total = openingTotal!;
    final done = openingProgress!.clamp(0, total);
    return Semantics(
      liveRegion: true,
      label: '${l10n.d('Documenten openen')}: $done / $total',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.panelText.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tab_rounded, color: palette.panelText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${l10n.d('Documenten openen')}: $done / $total',
                    style: TextStyle(
                      color: palette.panelText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onCancelOpening != null)
                  TextButton(
                    onPressed: onCancelOpening,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.panelText,
                    ),
                    child: Text(l10n.d('Annuleren')),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: total == 0 ? null : done / total,
              color: AppTheme.amberVivid,
              backgroundColor: palette.panelText.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verificationProgress(BuildContext context, AppPalette palette) {
    final l10n = context.l10n;
    final total = verificationTotal!;
    final done = verificationProgress!.clamp(0, total);
    return Semantics(
      liveRegion: true,
      label: '${l10n.d('Documenten controleren')}: $done / $total',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.panelText.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${l10n.d('Documenten controleren')}: $done / $total',
              style: TextStyle(
                color: palette.panelText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: total == 0 ? null : done / total,
              color: AppTheme.amberVivid,
              backgroundColor: palette.panelText.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
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
                if (dossier.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    dossier.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: compact ? 15 : 18,
                      height: 1.4,
                    ),
                  ),
                ],
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
                if (onChangeDescription != null ||
                    onChangeStartNumber != null) ...[
                  const SizedBox(height: 14),
                  _coverSettings(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverSettings(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      children: [
        if (onChangeDescription != null)
          TextButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final changed = await DossierDialogs.editDescription(
                      context,
                      initialDescription: dossier.description,
                    );
                    if (changed != null) onChangeDescription!(changed);
                  },
            icon: const Icon(Icons.notes_rounded),
            label: Text(l10n.d('Omschrijving wijzigen')),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        if (onChangeStartNumber != null)
          TextButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final changed = await DossierDialogs.editNumber(
                      context,
                      initialNumber: dossier.startNumber,
                      title: l10n.d('Beginnummer wijzigen'),
                    );
                    if (changed != null) onChangeStartNumber!(changed);
                  },
            icon: const Icon(Icons.format_list_numbered_rounded),
            label: Text(l10n.d('Beginnummer wijzigen')),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
      ],
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
          if (onExportPdf != null)
            OutlinedButton.icon(
              onPressed: busy ? null : onExportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(l10n.d('Dossier als PDF exporteren')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
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
              'Voeg documenten toe. De originele bestanden blijven op hun plek. Hier bepaal je de volgorde.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.panelText),
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
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: compact ? 22 : 27,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${dossier.entries.length} ${l10n.d('documenten')}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.72),
            ),
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
                    color: palette.panelText.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
            Container(
              width: compact ? 37 : 48,
              height: compact ? 37 : 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.amberVivid,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${dossier.numberFor(index)}'.padLeft(2, '0'),
                style: TextStyle(
                  color: Colors.black,
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
                  if (entry.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.panelText, fontSize: 13),
                    ),
                  ],
                  if (entry.documentDate != null ||
                      entry.author.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (entry.documentDate != null)
                          _metadataChip(
                            context,
                            palette,
                            entry.documentDate!,
                            Icons.calendar_today_outlined,
                          ),
                        if (entry.author.trim().isNotEmpty)
                          _metadataChip(
                            context,
                            palette,
                            entry.author,
                            Icons.person_outline_rounded,
                          ),
                      ],
                    ),
                  ],
                  TextButton.icon(
                    onPressed: busy ? null : () => _editEntry(context, entry),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(l10n.d('Documentgegevens bewerken')),
                  ),
                  const SizedBox(height: 5),
                  _sourceDetails(context, palette, entry),
                  Row(
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.panelText,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (unsavedEntryIds.contains(entry.id)) ...[
                    const SizedBox(height: 5),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.d(
                          'Onopgeslagen wijzigingen in tabblad; SHA-256 controleert de schijfversie.',
                        ),
                        style: TextStyle(
                          color: AppTheme.amberVivid,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (entry.checkedAt != null)
                    Text(
                      '${status == null ? l10n.d('Referentie vastgelegd') : l10n.d('Laatst gecontroleerd')}: ${_formatCheckedAt(context, entry.checkedAt!)}',
                      style: TextStyle(
                        color: palette.panelText.withValues(alpha: 0.82),
                        fontSize: 11,
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      '${l10n.d('SHA-256')} ${entry.sha256}',
                      style: TextStyle(
                        color: palette.panelText.withValues(alpha: 0.82),
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
              icon: Icon(Icons.open_in_new_rounded, color: palette.panelText),
            ),
            _entryActions(context, palette, entry, index),
          ],
        ),
      ),
    );
  }

  Widget _sourceDetails(
    BuildContext context,
    AppPalette palette,
    DossierEntry entry,
  ) {
    final l10n = context.l10n;
    final name = entry.originalName ?? entry.relativePath.split('/').last;
    final type = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : l10n.d('Bestand');
    final size = entry.sizeBytes == null ? null : _formatSize(entry.sizeBytes!);
    final location =
        entry.sourceRelativePath ?? entry.sourcePath ?? entry.relativePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 3,
          children: [
            _metadataChip(
              context,
              palette,
              type,
              Icons.insert_drive_file_outlined,
            ),
            if (size != null)
              _metadataChip(context, palette, size, Icons.data_usage_rounded),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.panelText.withValues(alpha: 0.82),
            fontSize: 12,
          ),
        ),
        Tooltip(
          message: location,
          child: Text(
            '${l10n.d('Vindplaats')}: $location',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.panelText.withValues(alpha: 0.82),
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 5),
      ],
    );
  }

  Widget _metadataChip(
    BuildContext context,
    AppPalette palette,
    String value,
    IconData icon,
  ) => Semantics(
    label: value,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.panelText.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: palette.panelText),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.panelText, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatCheckedAt(BuildContext context, DateTime checkedAt) {
    final local = checkedAt.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}-${local.month.toString().padLeft(2, '0')}-${local.year}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
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
      icon: Icon(Icons.more_vert_rounded, color: palette.panelText),
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
        if (entry.hashHistory.isNotEmpty)
          PopupMenuItem(
            value: _EntryAction.history,
            child: _menuRow(
              Icons.history_rounded,
              l10n.d('Eerdere SHA-256-waarden'),
            ),
          ),
        PopupMenuItem(
          value: _EntryAction.details,
          child: _menuRow(
            Icons.edit_outlined,
            l10n.d('Documentgegevens bewerken'),
          ),
        ),
        if (onChangeEntryNumber != null)
          PopupMenuItem(
            value: _EntryAction.number,
            child: _menuRow(Icons.pin_outlined, l10n.d('Nummer wijzigen')),
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
      case _EntryAction.history:
        await DossierDialogs.showHashHistory(context, entry: entry);
      case _EntryAction.details:
        await _editEntry(context, entry);
      case _EntryAction.number:
        final changed = await DossierDialogs.editNumber(
          context,
          initialNumber: dossier.numberFor(index),
          title: context.l10n.d('Nummer wijzigen'),
          allowAutomatic: true,
          usedNumbers: {
            for (var other = 0; other < dossier.entries.length; other++)
              if (other != index) dossier.numberFor(other),
          },
        );
        if (changed != null) {
          onChangeEntryNumber?.call(entry, changed == -1 ? null : changed);
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

  Future<void> _editEntry(BuildContext context, DossierEntry entry) async {
    final details = await DossierDialogs.editEntryDetails(
      context,
      entry: entry,
      suggest: onSuggestEntryDetails == null
          ? null
          : () => onSuggestEntryDetails!(entry),
    );
    if (details != null) onEditEntryDetails(entry, details);
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
        palette.panelText,
      ),
      DossierIntegrityStatus.changed => (
        Icons.error_rounded,
        l10n.d('Document gewijzigd'),
        AppTheme.amberVivid,
      ),
      DossierIntegrityStatus.missing => (
        Icons.error_outline_rounded,
        l10n.d('Document ontbreekt'),
        AppTheme.amberVivid,
      ),
      DossierIntegrityStatus.unreadable => (
        Icons.warning_rounded,
        l10n.d('Document niet leesbaar'),
        AppTheme.amberVivid,
      ),
      DossierIntegrityStatus.unsafe => (
        Icons.warning_rounded,
        l10n.d('Onveilige bestandsverwijzing'),
        AppTheme.amberVivid,
      ),
      null => (
        Icons.shield_outlined,
        l10n.d('Nog niet gecontroleerd'),
        palette.panelText.withValues(alpha: 0.82),
      ),
    };
  }
}
