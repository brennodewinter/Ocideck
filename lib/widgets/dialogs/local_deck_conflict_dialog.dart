import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/slide.dart';
import '../../services/git/deck_merge.dart';
import '../../services/git/version_diff.dart';
import '../../services/local_conflict.dart';
import '../../theme/app_theme.dart';
import 'slide_diff_dialog.dart';

/// De vergelijkingsdialoog bij een lokaal bestandsconflict (#2323): drie
/// versies naast elkaar — de basis (laatst geopend/opgeslagen), jouw
/// niet-opgeslagen versie en de versie op schijf — met het dia-overzicht,
/// de verplichte keuze per botsende dia en het toepassen van de merge.
/// Lezen van schijf gebeurt door de aanroeper via de gewone open-poort;
/// deze dialoog analyseert en toont alleen.

/// Laat de dia-vergelijking en de botsingskeuzes zien. Geeft het
/// samengevoegde deck terug bij "Samenvoegen en toepassen", of `null` bij
/// Terug — de aanroeper laat dan de eerste keuzedialoog weer zien.
class LocalDeckCompareDialog extends StatefulWidget {
  final LocalDeckConflict conflict;

  const LocalDeckCompareDialog({super.key, required this.conflict});

  @override
  State<LocalDeckCompareDialog> createState() => LocalDeckCompareDialogState();
}

class LocalDeckCompareDialogState extends State<LocalDeckCompareDialog> {
  /// baseIndex → nemen we de schijfversie van die dia? Geen keuze is bewust
  /// niet voorgeselecteerd: een botsing eist een expliciete keuze, anders
  /// drukte iemand per ongeluk "Toepassen" zonder te kijken.
  final Map<int, bool> _takeTheirs = {};

  bool get _allChosen {
    final merge = widget.conflict.merge;
    if (merge == null) return false;
    return merge.conflicts.every((c) => _takeTheirs.containsKey(c.baseIndex));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conflict = widget.conflict;
    final merge = conflict.merge;
    final conflicts = merge?.conflicts ?? const <SlideConflict>[];
    final overview = conflict.theirsDiff.changes
        .where((c) => c.kind != SlideChangeKind.unchanged)
        .toList();

    return AlertDialog(
      title: Text(l10n.d('Verschillen met de versie op schijf')),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Drie versies: wat je het laatst opende of opsloeg (de basis), jouw niet-opgeslagen versie, en wat er nu op schijf staat.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 10),
            if (conflict.hasBase) ...[
              _counts(l10n, l10n.d('Mijn versie'), conflict.oursDiff),
              _counts(l10n, l10n.d('Versie op schijf'), conflict.theirsDiff),
              const SizedBox(height: 6),
            ] else ...[
              Text(
                l10n.d(
                  'Er is geen betrouwbare basisversie bekend; automatisch samenvoegen kan niet. Kies welke versie je wilt gebruiken.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate400),
              ),
              const SizedBox(height: 6),
            ],
            if (merge != null && merge.isClean)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  l10n.d(
                    'De wijzigingen raken elkaar niet en kunnen automatisch worden samengevoegd.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (conflicts.isNotEmpty) ...[
              Text(
                l10n.d(
                  'Deze slides zijn aan beide kanten gewijzigd — kies per slide welke versie blijft:',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final c in conflicts) _conflictRow(l10n, c),
              const Divider(height: 18),
            ],
            Flexible(
              child: overview.isEmpty
                  ? Text(
                      l10n.d('Geen inhoudelijke verschillen gevonden.'),
                      style: TextStyle(fontSize: 12, color: AppTheme.slate400),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: overview.length,
                      itemBuilder: (context, i) =>
                          _changeRow(l10n, overview[i]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Terug')),
        ),
        if (merge != null)
          FilledButton(
            onPressed: _allChosen || merge.isClean
                ? () => Navigator.pop(context, _resolved())
                : null,
            child: Text(l10n.d('Samenvoegen en toepassen')),
          ),
      ],
    );
  }

  /// De tellingen van één kant, in dezelfde vorm als het versie-overzicht
  /// uit de git-flow.
  Widget _counts(AppLocalizations l10n, String label, VersionDiff diff) {
    return Text(
      '$label: '
      '${diff.addedCount} ${l10n.d('toegevoegd')} · '
      '${diff.removedCount} ${l10n.d('verwijderd')} · '
      '${diff.editedCount} ${l10n.d('gewijzigd')} · '
      '${diff.movedCount} ${l10n.d('verplaatst')}',
      style: const TextStyle(fontSize: 12),
    );
  }

  /// Eén botsende dia: titel, de keuze tussen beide kanten en een
  /// vergelijkingsknop wanneer er twee teksten zijn om te tonen.
  Widget _conflictRow(AppLocalizations l10n, SlideConflict c) {
    final taken = _takeTheirs[c.baseIndex];
    final title = (c.ours ?? c.theirs ?? c.base).title.trim();

    String sideLabel(Slide? slide, String whose) =>
        slide == null ? '$whose — ${l10n.d('verwijderd')}' : whose;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? l10n.d('(zonder titel)') : title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (c.ours != null && c.theirs != null)
                TextButton(
                  onPressed: () => _compare(l10n, c.ours!, c.theirs!),
                  child: Text(l10n.d('Verschillen')),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text(
                  sideLabel(c.ours, l10n.d('Mijn versie')),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  sideLabel(c.theirs, l10n.d('Versie op schijf')),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
            selected: taken == null ? const <bool>{} : {taken},
            emptySelectionAllowed: true,
            onSelectionChanged: (s) =>
                setState(() => _takeTheirs[c.baseIndex] = s.first),
          ),
        ],
      ),
    );
  }

  /// Eén rij uit het overzicht van wat de versie op schijf anders heeft.
  Widget _changeRow(AppLocalizations l10n, SlideChange change) {
    final (icon, colour, kindLabel) = switch (change.kind) {
      SlideChangeKind.added => (
        Icons.add_circle_outline,
        AppTheme.successFg,
        l10n.d('toegevoegd'),
      ),
      SlideChangeKind.removed => (
        Icons.remove_circle_outline,
        AppTheme.dangerFg,
        l10n.d('verwijderd'),
      ),
      SlideChangeKind.edited => (
        Icons.edit_outlined,
        AppTheme.amber600,
        l10n.d('gewijzigd'),
      ),
      SlideChangeKind.moved => (
        Icons.swap_vert,
        AppTheme.blue500,
        l10n.d('verplaatst'),
      ),
      SlideChangeKind.unchanged => (Icons.remove, AppTheme.slate400, ''),
    };
    final before = change.beforeIndex == null
        ? null
        : '${l10n.d('slide')} ${change.beforeIndex! + 1}';
    final after = change.afterIndex == null
        ? null
        : '${l10n.d('slide')} ${change.afterIndex! + 1}';
    final where = switch ((before, after)) {
      (final b?, final a?) when b != a => '$b → $a',
      (final b?, null) => b,
      (null, final a?) => a,
      (final b?, _) => b,
      _ => '',
    };
    final slide = change.after ?? change.before;
    final title = slide == null
        ? l10n.d('(zonder titel)')
        : (slide.title.trim().isEmpty
              ? l10n.d('(zonder titel)')
              : slide.title.trim());

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 18, color: colour),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '$kindLabel · $where',
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      // Alleen een bijgewerkte slide heeft twee kanten om naast elkaar te
      // zetten — die vergelijking gebruikt altijd mijn versie tegen de
      // schijfversie, ongeacht of `before` de basis of mijn versie was.
      trailing: change.kind == SlideChangeKind.edited
          ? TextButton(
              onPressed: () => _compareSides(l10n, change.before, change.after),
              child: Text(l10n.d('Verschillen')),
            )
          : null,
    );
  }

  /// Vergelijkt twee slide-versies naast elkaar; welke kant welke is hangt
  /// af van [hasBase] (basis↔schijf of mijn↔schijf).
  void _compareSides(AppLocalizations l10n, Slide? before, Slide? after) {
    if (before == null || after == null) return;
    final conflict = widget.conflict;
    _compare(
      l10n,
      before,
      after,
      beforeLabel: conflict.hasBase
          ? l10n.d('Laatst geopend of opgeslagen')
          : l10n.d('Mijn versie'),
      beforeDeck: conflict.hasBase ? conflict.base : conflict.ours,
    );
  }

  void _compare(
    AppLocalizations l10n,
    Slide left,
    Slide right, {
    String? beforeLabel,
    Deck? beforeDeck,
  }) {
    final conflict = widget.conflict;
    SlideDiffDialog.show(
      context,
      primary: SlideDiffRef(
        label: l10n.d('Versie op schijf'),
        slide: right,
        projectPath: conflict.theirs.projectPath,
        themeProfile: conflict.theirs.themeProfile,
        deckMarpStyle: conflict.theirs.marpStyle,
      ),
      others: [
        SlideDiffRef(
          label: beforeLabel ?? l10n.d('Mijn versie'),
          slide: left,
          projectPath: (beforeDeck ?? conflict.ours).projectPath,
          themeProfile: (beforeDeck ?? conflict.ours).themeProfile,
          deckMarpStyle: (beforeDeck ?? conflict.ours).marpStyle,
        ),
      ],
    );
  }

  /// De gekozen kanten doorrekenen op de merge-uitkomst.
  Deck _resolved() {
    final merge = widget.conflict.merge!;
    final picks = <Slide?>[
      for (final c in merge.conflicts)
        (_takeTheirs[c.baseIndex] ?? false) ? c.theirs : c.ours,
    ];
    return applyDeckConflictChoices(merge, picks);
  }
}
