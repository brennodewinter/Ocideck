import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/finding_spec.dart';
import '../../models/slide.dart';
import '../../services/cvss/cvss4.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';
import '_editor_field.dart';

/// Structured editor for a `finding` **header** slide (PENTEST_MIAUW §3.1). The
/// fields map one-to-one onto [FindingSpec], which round-trips to plain,
/// human-readable Markdown; the finding-group id is a slide-level field so a
/// later wizard (P2-WIZ) can attach detail/evidence slides to the same group.
///
/// The CVSS score and severity band are **derived** from the vector by the
/// [Cvss4] engine and shown live — never typed and never stored (§3.1). A full
/// per-metric CVSS builder is the finding wizard's job (P2-WIZ); here the vector
/// is entered as text with an immediate score/severity read-out.
class FindingEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const FindingEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<FindingEditor> createState() => _FindingEditorState();
}

class _FindingEditorState extends State<FindingEditor>
    with EditorTextControllers {
  late final TextEditingController _heading;
  late final TextEditingController _findingId;
  late final TextEditingController _scope;
  late final TextEditingController _cvss;
  late final TextEditingController _cwe;
  late final TextEditingController _cve;
  late final TextEditingController _description;
  late final TextEditingController _confirmation;
  late final TextEditingController _impact;
  late final TextEditingController _recommendation;

  static final _reCweId = RegExp(r'\d+');
  static final _reCweStrip = RegExp(r'^\s*CWE[-\s]*\d+\s*');
  static final _reCweSep = RegExp(r'^[—:·-]\s*');
  static final _reCve = RegExp(r'CVE-\d{4}-\d+', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    final spec = FindingSpec.parse(widget.slide.customMarkdown);
    _heading = newController(spec.heading, _onChanged);
    _findingId = newController(widget.slide.findingId, _onChanged);
    _scope = newController(spec.scopeObject, _onChanged);
    _cvss = newController(spec.cvssVector, _onChanged);
    _cwe = newController(_composeCwe(spec), _onChanged);
    _cve = newController(spec.cveIds.join(', '), _onChanged);
    _description = newController(spec.description, _onChanged);
    _confirmation = newController(spec.confirmation, _onChanged);
    _impact = newController(spec.impact, _onChanged);
    _recommendation = newController(spec.recommendation, _onChanged);
  }

  String _composeCwe(FindingSpec spec) {
    if (spec.cweId == null) return '';
    return spec.cweName.isEmpty
        ? 'CWE-${spec.cweId}'
        : 'CWE-${spec.cweId} — ${spec.cweName}';
  }

  void _onChanged() {
    setState(() {}); // refresh the live CVSS read-out
    _emit();
  }

  void _emit() {
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
      cvssVector: _cvss.text.trim(),
      cweId: cweId,
      cweName: cweName,
      cveIds: cveIds,
      description: _description.text,
      confirmation: _confirmation.text,
      impact: _impact.text,
      recommendation: _recommendation.text,
    );
    widget.onUpdate(
      widget.slide.copyWith(
        customMarkdown: spec.toMarkdown(),
        title: spec.heading,
        findingId: _findingId.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditorFieldList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel',
          controller: _heading,
          hint: 'F-03 · SQL-injectie in het loginformulier',
        ),
        EditorField(
          label: 'Bevinding-id',
          controller: _findingId,
          hint: 'F-03',
        ),
        EditorField(
          label: 'Scope-object',
          controller: _scope,
          hint: 'https://app.voorbeeld/login',
        ),
        EditorField(
          label: 'CVSS 4.0-vector',
          controller: _cvss,
          hint:
              'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
        ),
        _cvssReadout(context),
        EditorField(
          label: 'CWE',
          controller: _cwe,
          hint: 'CWE-89 — Improper Neutralization of SQL',
        ),
        EditorField(
          label: 'CVE',
          controller: _cve,
          hint: 'CVE-2024-1234, CVE-2024-5678',
        ),
        EditorField(
          label: 'Beschrijving',
          controller: _description,
          maxLines: 5,
        ),
        EditorField(
          label: 'Bevestiging (reproductie)',
          controller: _confirmation,
          maxLines: 5,
        ),
        EditorField(
          label: 'Mogelijke impact',
          controller: _impact,
          maxLines: 4,
        ),
        EditorField(
          label: 'Aanbeveling',
          controller: _recommendation,
          maxLines: 4,
        ),
      ],
    );
  }

  /// The derived score/severity chip. Nothing when the vector is empty; a muted
  /// hint when it is present but unparseable; otherwise the score + FIRST band
  /// in the band's colour.
  Widget _cvssReadout(BuildContext context) {
    final l10n = context.l10n;
    final vector = _cvss.text.trim();
    if (vector.isEmpty) return const SizedBox.shrink();
    final cvss = Cvss4.tryParseVector(vector);
    if (cvss == null) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: AppTheme.amber700),
          const SizedBox(width: 6),
          Text(
            l10n.d('Controleer de CVSS-vector'),
            style: TextStyle(fontSize: 12, color: AppTheme.amber700),
          ),
        ],
      );
    }
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
      ],
    );
  }
}
