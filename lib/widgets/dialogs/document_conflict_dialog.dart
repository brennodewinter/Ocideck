import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/local_conflict.dart';
import '../../theme/app_theme.dart';

/// Wat de document-vergelijkingsdialoog teruggeeft: terug naar de eerste
/// keuze, mijn versie toch wegschrijven, de schijfversie inladen, of mijn
/// versie als kopie ergens anders bewaren (#2323).
enum DocumentConflictAction { back, overwrite, loadDisk, saveCopy }

/// Zij-aan-zij-vergelijking van twee documentbronnen bij een lokaal
/// bestandsconflict: jouw niet-opgeslagen versie naast wat er nu op schijf
/// staat, per blok uitgelijnd en op woordniveau gemarkeerd (#2323).
///
/// Bewust géén tekstuele merge en geen per-hunk-keuzes: de gebruiker kiest
/// één hele versie. Daardoor kunnen frontmatter, HTML, tabellen,
/// codeblokken en verwijzingen nooit door een merge-vergissing verloren
/// gaan, en raken BOM en regeleinden de vergelijking niet (de blokindeling
/// trekt ze gelijk).
class DocumentConflictDialog extends StatelessWidget {
  /// De bron die zou worden weggeschreven — na visueel bewerken de
  /// byte-getrouw gepatchte opslagbron, niet de genormaliseerde rondrit.
  final String ours;

  /// De bron zoals die net door de open-poort van schijf is gelezen.
  final String theirs;

  const DocumentConflictDialog({
    super.key,
    required this.ours,
    required this.theirs,
  });

  static Future<DocumentConflictAction?> show(
    BuildContext context, {
    required String ours,
    required String theirs,
  }) {
    return showDialog<DocumentConflictAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentConflictDialog(ours: ours, theirs: theirs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pairs = diffDocBlocks(ours, theirs);
    return AlertDialog(
      title: Text(l10n.d('Verschillen met de versie op schijf')),
      content: SizedBox(
        width: 720,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Drie versies: wat je het laatst opende of opsloeg (de basis), jouw niet-opgeslagen versie, en wat er nu op schijf staat.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate400),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.d('Mijn versie'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.d('Versie op schijf'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: pairs.length,
                itemBuilder: (context, i) => _row(l10n, pairs[i]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, DocumentConflictAction.back),
          child: Text(l10n.d('Terug')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, DocumentConflictAction.saveCopy),
          child: Text(l10n.d('Mijn versie als kopie bewaren')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, DocumentConflictAction.loadDisk),
          child: Text(l10n.d('Versie op schijf laden')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, DocumentConflictAction.overwrite),
          child: Text(l10n.d('Mijn versie bewaren')),
        ),
      ],
    );
  }

  /// Eén uitgelijnde rij: gelijke blokken gedimd over de hele breedte,
  /// verschillende naast elkaar met woordmarkering.
  Widget _row(AppLocalizations l10n, DocDiffPair pair) {
    if (pair.equal) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          pair.ours ?? '',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.slate400,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _marked(l10n, pair.ours, pair.theirs)),
          const SizedBox(width: 12),
          Expanded(child: _marked(l10n, pair.theirs, pair.ours)),
        ],
      ),
    );
  }

  /// De tekst van één kant met de gewijzigde woorden gemarkeerd; `null`
  /// toont als "op deze plek staat niets".
  Widget _marked(AppLocalizations l10n, String? side, String? other) {
    if (side == null) {
      return Text(
        '—',
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.slate400,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final spans = <TextSpan>[
      for (final part in diffDocWords(side, other ?? ''))
        TextSpan(
          text: part.text,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            backgroundColor: part.changed
                ? AppTheme.amber600.withValues(alpha: 0.25)
                : null,
          ),
        ),
    ];
    return Text.rich(TextSpan(children: spans));
  }
}
