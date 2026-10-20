// Part of the document_editor_screen library — see ../document_editor_screen.dart.
// De risico-kwaliteitscontrole in documentmodus (#2490): een gegroepeerd,
// navigeerbaar bevindingenoverzicht met één veilige herstelactie per
// bevinding. De controle leest; herstel is altijd een menselijke keuze.
part of '../document_editor_screen.dart';

/// Open het bevindingenoverzicht. Hergescand bij elke open én na elke
/// herstelactie — dezelfde pure toets als de exportpoort, dus wat hier staat
/// is wat de export straks ook vindt.
Future<void> _openRiskQuality(_DocumentEditorScreenState s) {
  return showDialog(
    context: s.context,
    builder: (context) => StatefulBuilder(
      builder: (context, refresh) {
        final l10n = context.l10n;
        final report = riskQualityFindings(s._controller.text);
        return AlertDialog(
          title: Text(l10n.d('Risico-kwaliteitscontrole')),
          content: SizedBox(
            width: 560,
            child: report.isClean
                ? Text(
                    l10n.d(
                      'Geen bevindingen — IDs, scores en gekoppelde '
                      'weergaven kloppen.',
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (report.errors.isNotEmpty) ...[
                          _riskQualityHeader(
                            l10n.d('Blokkerende fouten'),
                            l10n.d(
                              'De cijfers zijn niet betrouwbaar zolang deze '
                              'er zijn.',
                            ),
                          ),
                          for (final f in report.errors)
                            _riskQualityTile(
                              s,
                              context,
                              l10n,
                              f,
                              () => refresh(() {}),
                            ),
                        ],
                        if (report.warnings.isNotEmpty) ...[
                          _riskQualityHeader(
                            l10n.d('Waarschuwingen'),
                            l10n.d(
                              'Inhoudelijk om na te lopen; één heeft een '
                              'veilige herstelknop.',
                            ),
                          ),
                          for (final f in report.warnings)
                            _riskQualityTile(
                              s,
                              context,
                              l10n,
                              f,
                              () => refresh(() {}),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.t('close')),
            ),
          ],
        );
      },
    ),
  );
}

Widget _riskQualityHeader(String title, String hint) => Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 4),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      Text(hint, style: const TextStyle(fontSize: 10.5, height: 1.25)),
    ],
  ),
);

/// Eén bevinding: regel + record, wat afwijkt, het gevolg, en de ene knop
/// die erbij past — "Ga naar" voor menselijke keuzes, "Verversen" voor een
/// herstelbare weergave.
Widget _riskQualityTile(
  _DocumentEditorScreenState s,
  BuildContext dialogContext,
  AppLocalizations l10n,
  RiskQualityFinding f,
  VoidCallback refresh,
) {
  final isError = f.severity == RiskQualitySeverity.error;
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: isError ? AppTheme.warningBg : AppTheme.infoBg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 15,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'L${f.line}'
                '${f.recordId == null ? '' : '  ${f.recordId}'}'
                '${f.tableId == null ? '' : '  (${f.tableId})'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (f.repair != RiskQualityRepair.none)
              TextButton(
                onPressed: () {
                  final next = switch (f.repair) {
                    RiskQualityRepair.refreshView => regenerateOciView(
                      s._controller.text,
                      f.repairTable!,
                    ),
                    RiskQualityRepair.recalculateCalc => recalculateOciTable(
                      s._controller.text,
                      f.repairTable!,
                    ),
                    RiskQualityRepair.none => null,
                  };
                  if (next == null) return;
                  _commitDocumentBody(s.ref, next, coalesceKey: null);
                  refresh();
                },
                child: Text(
                  f.repair == RiskQualityRepair.recalculateCalc
                      ? l10n.d('Herberekenen')
                      : l10n.d('Verversen'),
                  style: const TextStyle(fontSize: 11),
                ),
              )
            else
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _revealSourceLine(s, f.line);
                },
                child: Text(
                  l10n.d('Ga naar'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        Text(f.message, style: const TextStyle(fontSize: 11.5)),
        const SizedBox(height: 2),
        Text(
          f.consequence,
          style: TextStyle(fontSize: 10.5, color: AppTheme.slate600),
        ),
      ],
    ),
  );
}

/// Spring naar regel [line] van de bron: naar de bronstand en de regel
/// selecteren. Navigeren werkt hetzelfde vanuit elke modus.
void _revealSourceLine(_DocumentEditorScreenState s, int line) {
  if (s._viewMode != _DocViewMode.source) {
    s._changeViewMode(_DocViewMode.source);
  }
  final lines = s._controller.text.split('\n');
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    if (i + 1 == line) {
      s._controller.selection = TextSelection(
        baseOffset: offset,
        extentOffset: offset + lines[i].length,
      );
      s._editorFocus.requestFocus();
      return;
    }
    offset += lines[i].length + 1;
  }
}
