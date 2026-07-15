import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/eis_entry.dart';
import '../../models/miauw_compliance.dart';
import '../../services/miauw_compliance_analyzer.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';

/// The MIAUW compliance overview (PENTEST_MIAUW §9): per EIS a status
/// (Voldaan / Open / Uitgesloten door klant) grouped by part, with a per-row
/// action to exclude a requirement (mandatory reason) or lift the exclusion. A
/// gap analysis — it warns when a foundational EIS is excluded, but never blocks.
///
/// Shown as a root-navigator dialog (via the command palette), so it must NOT
/// read the per-tab-scoped `deckProvider`: those overrides live below the root
/// Navigator, so a root dialog would resolve the empty root deck instead. It
/// therefore takes the tab's [DeckNotifier] (captured at the tab-scoped call
/// site), subscribes to it, and recomputes the overview on the live deck — so
/// waive/unwaive updates the panel immediately.
class MiauwCompliancePanel extends StatefulWidget {
  const MiauwCompliancePanel({super.key, required this.notifier});

  /// The active tab's deck notifier, passed in from the tab-scoped command
  /// (see `command_palette_actions.dart`).
  final DeckNotifier notifier;

  static Future<void> show(BuildContext context, DeckNotifier notifier) =>
      showDialog<void>(
        context: context,
        builder: (_) => MiauwCompliancePanel(notifier: notifier),
      );

  @override
  State<MiauwCompliancePanel> createState() => _MiauwCompliancePanelState();
}

class _MiauwCompliancePanelState extends State<MiauwCompliancePanel> {
  static const _analyzer = MiauwComplianceAnalyzer();

  late MiauwComplianceResult _result;
  VoidCallback? _removeListener;

  @override
  void initState() {
    super.initState();
    // Seed from the current deck, then rebuild on every deck edit (including
    // this panel's own waive/unwaive). `fireImmediately: false` avoids a
    // setState during initState.
    _result = _analyze(widget.notifier.currentState);
    _removeListener = widget.notifier.addListener((state) {
      final result = _analyze(state);
      if (mounted) setState(() => _result = result);
    }, fireImmediately: false);
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  MiauwComplianceResult _analyze(DeckState state) {
    final deck = state.deck;
    if (deck == null) return const MiauwComplianceResult([]);
    return _analyzer.analyze(deck);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _result;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.d('MIAUW-compliance'))),
          _summary(l10n, result),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result.foundationalWaived.isNotEmpty)
              _foundationalWarning(l10n),
            Expanded(
              child: ListView(
                children: [
                  for (final part in EisPart.values)
                    if (result.forPart(part).isNotEmpty) ...[
                      _partHeader(part),
                      for (final r in result.forPart(part)) _row(l10n, r),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }

  // Lead with the denominator: the catalog is a curated subset of the full
  // 92-EIS schema, so a bare met·open·waived tally must never read as full
  // MIAUW conformance. Counts stay compact (locale-invariant) so the dialog
  // title never overflows; the labelled breakdown lives in the audit dossier.
  Widget _summary(AppLocalizations l10n, MiauwComplianceResult r) => Text(
    '${r.total}/$kMiauwFullSchemaSize · '
    '${r.metCount} · ${r.openCount} · ${r.waivedCount}',
    style: TextStyle(fontSize: 13, color: AppTheme.slate500),
  );

  Widget _foundationalWarning(AppLocalizations l10n) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.amber500.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Icon(Icons.warning_amber_outlined, size: 16, color: AppTheme.amber700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.d('Fundamentele eisen zijn uitgesloten'),
            style: TextStyle(fontSize: 12, color: AppTheme.amber700),
          ),
        ),
      ],
    ),
  );

  Widget _partHeader(EisPart part) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      part.dutchLabel,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.slate700,
      ),
    ),
  );

  Widget _row(AppLocalizations l10n, EisResult r) {
    final (label, color) = _statusStyle(r.status, l10n);
    final waived = r.status == EisStatus.uitgesloten;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusChip(label, color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.entry.id} · ${r.entry.title}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  r.entry.derivation == EisDerivation.automatic
                      ? l10n.d('Automatisch')
                      : l10n.d('Handmatig'),
                  style: TextStyle(fontSize: 10.5, color: AppTheme.slate400),
                ),
                if (waived && (r.waiverReason ?? '').isNotEmpty)
                  Text(
                    r.waiverReason!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _toggleWaiver(l10n, r, waived),
            child: Text(
              waived ? l10n.d('Opheffen') : l10n.d('Uitsluiten'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  (String, Color) _statusStyle(EisStatus status, AppLocalizations l10n) =>
      switch (status) {
        EisStatus.voldaan => (l10n.d('Voldaan'), AppTheme.severityLow),
        EisStatus.open => (l10n.d('Openstaand'), AppTheme.amber700),
        EisStatus.uitgesloten => (
          l10n.d('Uitgesloten door klant'),
          AppTheme.slate500,
        ),
      };

  Future<void> _toggleWaiver(
    AppLocalizations l10n,
    EisResult r,
    bool waived,
  ) async {
    final notifier = widget.notifier;
    if (waived) {
      notifier.removeMiauwWaiver(r.entry.id);
      return;
    }
    final reason = await _promptReason(l10n, r);
    if (reason == null || reason.trim().isEmpty) return;
    notifier.setMiauwWaiver(r.entry.id, reason);
  }

  Future<String?> _promptReason(AppLocalizations l10n, EisResult r) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${l10n.d('Uitsluiten')} · ${r.entry.id}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.d('Reden voor uitsluiting'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.d('Uitsluiten')),
          ),
        ],
      ),
    );
  }
}
