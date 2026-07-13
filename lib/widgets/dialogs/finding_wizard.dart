import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cvss_builder.dart';
import '../../models/finding_spec.dart';
import '../../models/scope_matrix_spec.dart';
import '../../models/slide.dart';
import '../../services/finding_context_score.dart';
import '../../services/finding_group_builder.dart';
import '../../theme/app_theme.dart';
import 'cvss_builder_dialog.dart';
import 'cwe_picker.dart';

/// The guided **finding wizard** (PENTEST_MIAUW §4.1): step through title →
/// scope object → a per-metric **CVSS 4.0 builder** (which stores a Base-only
/// vector and shows the context score derived from the chosen scope object's CIA
/// rating) → CWE → CVE → the four narrative sections, then **emit a finding slide
/// group** (header + optional detail/evidence placeholders sharing one finding
/// id). Returns the group (or null on cancel); the caller inserts it with
/// `insertSlides`.
class FindingWizard extends StatefulWidget {
  const FindingWizard({super.key, this.scopeRows = const []});

  /// The deck's scope objects, so the CVSS step can pull the chosen scope
  /// object's CIA rating and show a context (environmental) score alongside the
  /// base score.
  final List<ScopeRow> scopeRows;

  static Future<List<Slide>?> show(
    BuildContext context, {
    List<ScopeRow> scopeRows = const [],
  }) => showDialog<List<Slide>>(
    context: context,
    builder: (_) => FindingWizard(scopeRows: scopeRows),
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

  /// The finding's Base-only CVSS vector, seeded to the all-defaults vector and
  /// updated by the builder. The CIA weighting is never baked in here — it lives
  /// on the scope object and yields the context score at display time.
  String _baseVector = baseCvss4Vector('');
  late final Map<String, CiaRating> _scopeCiaIndex;
  bool _addDetail = false;
  bool _addEvidence = true;

  @override
  void initState() {
    super.initState();
    _scopeCiaIndex = scopeCiaIndexFromRows(widget.scopeRows);
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

  /// The CIA rating of the currently entered scope object, or an empty rating
  /// when it is not in the scope matrix — the CVSS step uses it for the context
  /// read-out.
  CiaRating get _scopeCia => scopeObjectCia(_scope.text.trim(), _scopeCiaIndex);

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
      cvssVector: _baseVector,
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

  Widget _stepCvss(AppLocalizations l10n) {
    final cia = _scopeCia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cia.isDefined)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.d(
                'De contextscore is gewogen met de CIA-rating van het gekozen scope-object.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          ),
        CvssBuilder(
          initialVector: _baseVector,
          cia: cia,
          onVectorChanged: (v) => _baseVector = v,
        ),
      ],
    );
  }

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
}
