import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cvss_builder.dart';
import '../../models/finding_spec.dart';
import '../../models/slide.dart';
import '../../services/cvss/cvss4.dart';
import '../../services/finding_group_builder.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';
import 'cwe_picker.dart';

/// The guided **finding wizard** (PENTEST_MIAUW §4.1): step through title →
/// scope object → a per-metric **CVSS 4.0 builder** (Environmental `CR/IR/AR`
/// pre-filled from the scope object's CIA rating → a CIA-weighted score) → CWE →
/// CVE → the four narrative sections, then **emit a finding slide group** (header
/// + optional detail/evidence placeholders sharing one finding id). Returns the
/// group (or null on cancel); the caller inserts it with `insertSlides`.
class FindingWizard extends StatefulWidget {
  const FindingWizard({super.key});

  static Future<List<Slide>?> show(BuildContext context) =>
      showDialog<List<Slide>>(
        context: context,
        builder: (_) => const FindingWizard(),
      );

  @override
  State<FindingWizard> createState() => _FindingWizardState();
}

class _FindingWizardState extends State<FindingWizard> {
  static const _stepCount = 4;

  static final _reCweId = RegExp(r'\d+');
  static final _reCweStrip = RegExp(r'^\s*CWE[-\s]*\d+\s*');
  static final _reCweSep = RegExp(r'^[—:·-]\s*');
  static final _reCve = RegExp(r'CVE-\d{4}-\d+', caseSensitive: false);

  int _step = 0;

  late final TextEditingController _heading;
  late final TextEditingController _findingId;
  late final TextEditingController _scope;
  late final TextEditingController _cwe;
  late final TextEditingController _cve;
  late final TextEditingController _description;
  late final TextEditingController _confirmation;
  late final TextEditingController _impact;
  late final TextEditingController _recommendation;

  final Map<String, String> _base = {
    for (final m in kCvss4BaseMetrics) m.code: m.defaultToken,
  };
  CiaRating _cia = const CiaRating();
  bool _addDetail = false;
  bool _addEvidence = true;

  @override
  void initState() {
    super.initState();
    _heading = TextEditingController();
    _findingId = TextEditingController();
    _scope = TextEditingController();
    _cwe = TextEditingController();
    _cve = TextEditingController();
    _description = TextEditingController();
    _confirmation = TextEditingController();
    _impact = TextEditingController();
    _recommendation = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [
      _heading,
      _findingId,
      _scope,
      _cwe,
      _cve,
      _description,
      _confirmation,
      _impact,
      _recommendation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _vector => assembleCvss4Vector(_base, cia: _cia);

  void _finish() {
    final cweText = _cwe.text.trim();
    final cweId = int.tryParse(_reCweId.firstMatch(cweText)?.group(0) ?? '');
    final cweName = cweId == null
        ? ''
        : cweText
              .replaceFirst(_reCweStrip, '')
              .replaceFirst(_reCweSep, '')
              .trim();
    final cveIds = <String>[];
    for (final match in _reCve.allMatches(_cve.text)) {
      final id = match.group(0)!.toUpperCase();
      if (!cveIds.contains(id)) cveIds.add(id);
    }
    final spec = FindingSpec(
      heading: _heading.text.trim(),
      scopeObject: _scope.text.trim(),
      cvssVector: _vector,
      cweId: cweId,
      cweName: cweName,
      cveIds: cveIds,
      description: _description.text,
      confirmation: _confirmation.text,
      impact: _impact.text,
      recommendation: _recommendation.text,
    );
    final group = buildFindingGroup(
      spec: spec,
      findingId: _findingId.text.trim(),
      addDetail: _addDetail,
      addEvidence: _addEvidence,
    );
    Navigator.of(context).pop(group);
  }

  Future<void> _pickCwe() async {
    final entry = await CwePicker.show(context);
    if (entry == null) return;
    _cwe.text = entry.label;
    if (_description.text.trim().isEmpty) _description.text = entry.description;
    if (_recommendation.text.trim().isEmpty) {
      _recommendation.text = entry.recommendation;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isLast = _step == _stepCount - 1;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.d('Nieuwe bevinding (wizard)'))),
          Text(
            '${_step + 1} / $_stepCount',
            style: TextStyle(fontSize: 13, color: AppTheme.slate500),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: SingleChildScrollView(child: _stepBody(l10n)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        if (_step > 0)
          TextButton(
            onPressed: () => setState(() => _step--),
            child: Text(l10n.d('Vorige')),
          ),
        FilledButton(
          onPressed: isLast ? _finish : () => setState(() => _step++),
          child: Text(isLast ? l10n.d('Bevinding maken') : l10n.d('Volgende')),
        ),
      ],
    );
  }

  Widget _stepBody(AppLocalizations l10n) => switch (_step) {
    0 => _stepBasis(),
    1 => _stepCvss(l10n),
    2 => _stepCweCve(l10n),
    _ => _stepContent(l10n),
  };

  Widget _stepBasis() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _field(
        'Titel',
        _heading,
        hint: 'F-03 · SQL-injectie in het loginformulier',
      ),
      _field('Bevinding-id', _findingId, hint: 'F-03'),
      _field('Scope-object', _scope, hint: 'https://app.voorbeeld/login'),
    ],
  );

  Widget _stepCvss(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final m in kCvss4BaseMetrics) _metricDropdown(m),
      const SizedBox(height: 12),
      Text(
        l10n.d('CIA-rating (scope-object)'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      _ciaDropdown(
        l10n.d('Vertrouwelijkheid'),
        _cia.confidentiality,
        (v) => setState(() => _cia = _cia.copyWith(confidentiality: v)),
      ),
      _ciaDropdown(
        l10n.d('Integriteit'),
        _cia.integrity,
        (v) => setState(() => _cia = _cia.copyWith(integrity: v)),
      ),
      _ciaDropdown(
        l10n.d('Beschikbaarheid'),
        _cia.availability,
        (v) => setState(() => _cia = _cia.copyWith(availability: v)),
      ),
      const SizedBox(height: 12),
      _readout(l10n),
    ],
  );

  Widget _stepCweCve(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _pickCwe,
          icon: const Icon(Icons.shield_outlined, size: 16),
          label: Text(l10n.d('Kies CWE…')),
        ),
      ),
      _field('CWE', _cwe, hint: 'CWE-89 — Improper Neutralization of SQL'),
      _field('CVE', _cve, hint: 'CVE-2024-1234, CVE-2024-5678'),
    ],
  );

  Widget _stepContent(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _field('Beschrijving', _description, maxLines: 3),
      _field('Bevestiging (reproductie)', _confirmation, maxLines: 3),
      _field('Mogelijke impact', _impact, maxLines: 2),
      _field('Aanbeveling', _recommendation, maxLines: 2),
      const SizedBox(height: 8),
      CheckboxListTile(
        value: _addDetail,
        onChanged: (v) => setState(() => _addDetail = v ?? false),
        title: Text(
          l10n.d('Detailslide toevoegen'),
          style: const TextStyle(fontSize: 13),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
      CheckboxListTile(
        value: _addEvidence,
        onChanged: (v) => setState(() => _addEvidence = v ?? false),
        title: Text(
          l10n.d('Bewijsslide toevoegen'),
          style: const TextStyle(fontSize: 13),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    ],
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _metricDropdown(Cvss4BaseMetric m) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(m.label, style: const TextStyle(fontSize: 12)),
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
                  child: Text('${o.token} · ${o.label}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _base[m.code] = v);
            },
          ),
        ),
      ],
    ),
  );

  Widget _ciaDropdown(
    String label,
    CiaLevel value,
    ValueChanged<CiaLevel> onChanged,
  ) => Row(
    children: [
      Expanded(
        flex: 5,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
      Expanded(
        flex: 4,
        child: DropdownButton<CiaLevel>(
          isExpanded: true,
          value: value,
          style: TextStyle(fontSize: 12, color: AppTheme.ink),
          items: [
            for (final l in CiaLevel.values)
              DropdownMenuItem(
                value: l,
                child: Text('${l.token} · ${l.label}'),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    ],
  );

  /// Live score + severity chip for the assembled vector (empty when it does not
  /// parse, which shouldn't happen for a builder-produced vector).
  Widget _readout(AppLocalizations l10n) {
    final cvss = Cvss4.tryParseVector(_vector);
    if (cvss == null) return const SizedBox.shrink();
    final color = FindingSeverityPalette.of(cvss.severity);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${cvss.score.toStringAsFixed(1)} · ${cvss.severity.label}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (_cia.isDefined)
          Text(
            l10n.d('CIA-gewogen'),
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
      ],
    );
  }
}
