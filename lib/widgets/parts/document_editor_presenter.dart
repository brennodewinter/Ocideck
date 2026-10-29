// Part of the document-editor library — see ../document_editor_screen.dart.
//
// De documentpresentatie van #2487 zoals de editor hem start: de
// aanwijsdialoog (welke tabellen mogen live bewerkt worden), de
// tweede-scherm-grens en de afhandeling van de afsluitkeuze. Top-level
// functies — ze raken geen veld van de State, dus ze horen ook niet in de
// klasse te tellen; de State houdt alleen de dunne `_presentDocument`-
// delegator vast.
part of '../document_editor_screen.dart';

/// De presentatie-route van #2487. In tegenstelling tot de document→
/// presentatie-conversie is dit geen kopie maar de bron zelf; wat de sessie
/// aan edits opleverde wordt bij het sluiten expliciet bewaard, als kopie
/// bewaard of verworpen.
Future<void> _presentDocumentSession(_DocumentEditorScreenState s) async {
  s.ref.read(documentProvider.notifier).flushPendingVisualEdit();
  final context = s.context;
  final ref = s.ref;
  final body = s._controller.text;
  final l10n = context.l10n;
  // Wijs de live-bewerkbare tabellen aan vóór de presentatie; zonder
  // aanwijzing staat alles lees-only (#2487: nooit impliciet).
  final editable = await _designatePresentableTables(context, l10n, body);
  if (editable == null || !context.mounted) return;
  final settings = ref.read(settingsProvider);
  final doc = ref.read(documentProvider);
  // Dezelfde tweede-scherm-grens als de diapresentatie: op één scherm is er
  // geen beamer — een publieksvenster zou dan het enige scherm dekken.
  // getAllDisplays faalt intern fail-closed (logt + lege lijst).
  final dualScreen =
      supportsDualScreenPresenter && getAllDisplays().length >= 2;
  final result = await presentDocument(
    context,
    body: body,
    projectPath: doc.projectPath,
    themeProfile: resolveDocumentStyleProfile(
      settings,
      doc.document?.styleName,
    ),
    editableTables: editable,
    dualScreen: dualScreen,
    // Dezelfde pagina-einden als de export (FILE_FORMAT.md §14.6).
    chapterBreaks: settings.documentChapterPageBreak,
  );
  if (result == null || !context.mounted) return;
  switch (result.choice) {
    case DocumentExitChoice.keep:
      // De sessie als één discrete stap — dezelfde bronroute als elke andere
      // documentedit, zodat undo/redo en de externe-wijziging-poort bij
      // opslaan onverkort gelden.
      if (result.body != body) {
        _commitDocumentBody(ref, result.body, coalesceKey: null);
      }
    case DocumentExitChoice.copy:
      ref
          .read(tabsProvider.notifier)
          .newDocumentFromMarkdown(
            result.body,
            projectPath: ref.read(documentProvider).projectPath,
            suggestedName: ref.read(documentProvider).suggestedName,
          );
    case DocumentExitChoice.discard:
      break;
  }
}

/// De aanwijsdialoog van #2487: welke tabellen mogen tijdens de sessie live
/// bewerkt worden. `null` = afgesloten zonder te presenteren; een lege
/// verzameling = presenteren zonder bewerkingsrechten.
Future<Set<int>?> _designatePresentableTables(
  BuildContext context,
  AppLocalizations l10n,
  String body,
) async {
  final labels = <int, String>{};
  for (var o = 0; ; o++) {
    final range = DocumentMarkdownView.nthTableBlockRange(body, o);
    if (range == null) break;
    final rows = decodeMarkdownTableRows(
      body.split('\n').sublist(range[0], range[1]),
    );
    labels[o] = rows.isEmpty
        ? '${l10n.d('Tabel')} ${o + 1}'
        : '${l10n.d('Tabel')} ${o + 1} — ${rows.first.take(3).join(' · ')}';
  }
  if (labels.isEmpty) return const {};
  if (!context.mounted) return null;
  final selected = <int>{};
  final chosen = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(l10n.d('Presenteer document')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d(
                    'Vink aan welke tabellen tijdens de presentatie live bewerkt mogen worden. Alle andere inhoud blijft alleen-lezen.',
                  ),
                ),
                const SizedBox(height: 12),
                for (final e in labels.entries)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: selected.contains(e.key),
                    onChanged: (v) => setDialogState(
                      () => v == true
                          ? selected.add(e.key)
                          : selected.remove(e.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.d('Presenteren')),
          ),
        ],
      ),
    ),
  );
  return chosen == true ? selected : null;
}
