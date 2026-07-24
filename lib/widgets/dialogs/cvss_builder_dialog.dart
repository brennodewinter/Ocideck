import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cvss_builder.dart';
import '../../services/cvss/cvss4.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';

/// Reusable per-metric **CVSS 4.0 Base builder** (PENTEST_MIAUW §4.1/§7): one
/// dropdown per Base metric plus a live base/context score read-out. It emits a
/// **Base-only vector** via [onVectorChanged]; the context score is derived for
/// display only from [cia] (the linked scope object's CIA rating) and is never
/// baked into the emitted vector — the weighting lives on the scope object so it
/// re-scores every finding that references it. Shared by the finding wizard
/// (inline step) and [CvssBuilderDialog] (opened from the finding editor).
class CvssBuilder extends StatefulWidget {
  const CvssBuilder({
    super.key,
    this.initialVector = '',
    this.cia = const CiaRating(),
    required this.onVectorChanged,
  });

  /// A vector to seed the dropdowns from; only its Base metrics are read.
  final String initialVector;

  /// The linked scope object's CIA rating, used for the context read-out only.
  final CiaRating cia;

  /// Called with the assembled Base-only vector on every change.
  final ValueChanged<String> onVectorChanged;

  @override
  State<CvssBuilder> createState() => _CvssBuilderState();
}

class _CvssBuilderState extends State<CvssBuilder> {
  late final Map<String, String> _base;

  @override
  void initState() {
    super.initState();
    final parsed = Cvss4.tryParseVector(widget.initialVector);
    _base = {
      for (final m in kCvss4BaseMetrics)
        m.code: parsed?[m.code] ?? m.defaultToken,
    };
  }

  String get _vector => assembleCvss4Vector(_base);

  void _set(String code, String token) {
    setState(() => _base[code] = token);
    widget.onVectorChanged(_vector);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in kCvss4BaseMetrics) _metricDropdown(m),
        const SizedBox(height: 12),
        _readout(context.l10n),
      ],
    );
  }

  Widget _metricDropdown(Cvss4BaseMetric m) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              l10n.d(m.dutchLabel),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 4,
            child: DropdownButton<String>(
              isExpanded: true,
              value: _base[m.code],
              style: TextStyle(fontSize: 12, color: AppTheme.ink),
              items: [
                for (final o in m.options)
                  DropdownMenuItem(
                    value: o.token,
                    child: Text('${o.token} · ${l10n.d(o.dutchLabel)}'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _set(m.code, v);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Live score chips: always the base score, plus a context score when the
  /// scope object carries a CIA rating (then the context score is what guides
  /// the tester to the "correct" score).
  Widget _readout(AppLocalizations l10n) {
    final base = Cvss4.tryParseVector(_vector);
    if (base == null) return const SizedBox.shrink();
    final context = contextCvss(_vector, widget.cia);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _scoreBadge(l10n.d('Basis'), base),
        if (context != null) _scoreBadge(l10n.d('Context'), context),
        if (context != null)
          Text(
            l10n.d('CIA-gewogen'),
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
      ],
    );
  }

  Widget _scoreBadge(String label, Cvss4 cvss) {
    final color = FindingSeverityPalette.of(cvss.severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label ${cvss.score.toStringAsFixed(1)} · ${cvss.severity.label}',
        style: TextStyle(
          // Zie de bevindingeditor: 12px-label op de lichte ernstbanden, wit
          // zakte daar naar 3,2-3,6:1 (#821). `labelOn` kiest zwart waar nodig.
          color: AppTheme.labelOn(color),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Modal wrapper around [CvssBuilder] for the finding editor: opens the guided
/// builder seeded from the current vector, and returns the assembled Base-only
/// vector on "Toepassen" (or null on cancel). The finding editor writes the
/// result into its free-text vector field.
class CvssBuilderDialog extends StatefulWidget {
  const CvssBuilderDialog({
    super.key,
    this.initialVector = '',
    this.cia = const CiaRating(),
  });

  final String initialVector;
  final CiaRating cia;

  static Future<String?> show(
    BuildContext context, {
    String initialVector = '',
    CiaRating cia = const CiaRating(),
  }) => showDialog<String>(
    context: context,
    builder: (_) => CvssBuilderDialog(initialVector: initialVector, cia: cia),
  );

  @override
  State<CvssBuilderDialog> createState() => _CvssBuilderDialogState();
}

class _CvssBuilderDialogState extends State<CvssBuilderDialog> {
  late String _vector = baseCvss4Vector(widget.initialVector);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('CVSS-wizard')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: CvssBuilder(
            initialVector: widget.initialVector,
            cia: widget.cia,
            onVectorChanged: (v) => _vector = v,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_vector),
          child: Text(l10n.d('Toepassen')),
        ),
      ],
    );
  }
}
