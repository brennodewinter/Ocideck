import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/finding_spec.dart';
import '../../models/slide.dart';
import '../../services/cvss/cvss4.dart';
import '../../services/finding_ai_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';
import '../dialogs/cwe_picker.dart';
import '../dialogs/finding_template_picker.dart';
import '_editor_field.dart';
import 'ai_suggest_field.dart';

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

  /// The free-text fields whose current value is an unreviewed AI draft
  /// (`ocideck_ai_assisted`, §16.3). Seeded from the slide and written back by
  /// [_emit]; the seal step blocks while it is non-empty.
  late final Set<String> _aiFields;

  @override
  void initState() {
    super.initState();
    final spec = FindingSpec.parse(widget.slide.customMarkdown);
    _aiFields = {...widget.slide.aiAssistedFields};
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
        aiAssistedFields: _aiFields.toList(),
      ),
    );
  }

  /// The pentester's own facts, the only grounding the AI drafting gets (§16.3).
  FindingAiContext _aiContext() {
    final cweText = _cwe.text.trim();
    return FindingAiContext(
      heading: _heading.text,
      scopeObject: _scope.text,
      cvssVector: _cvss.text,
      cwe: cweText,
      cveIds: [for (final m in _reCve.allMatches(_cve.text)) m.group(0)!],
      description: _description.text,
      confirmation: _confirmation.text,
      impact: _impact.text,
      recommendation: _recommendation.text,
    );
  }

  /// Insert an AI draft into [controller] and mark [field] as an unreviewed AI
  /// draft; setting the text re-emits with the marker.
  void _onAiSuggested(
    String field,
    TextEditingController controller,
    String draft,
  ) {
    setState(() => _aiFields.add(field));
    controller.text = draft;
  }

  /// Clear the AI-draft marker on [field] once the tester has reviewed it.
  void _onAiReviewed(String field) {
    setState(() => _aiFields.remove(field));
    _emit();
  }

  /// The per-field AI "suggest" control row (only free-text fields, §16).
  Widget _suggest(
    FindingAiField field,
    String key,
    TextEditingController controller,
  ) => AiSuggestField(
    field: field,
    contextBuilder: _aiContext,
    hasExistingText: controller.text.trim().isNotEmpty,
    isAiDraft: _aiFields.contains(key),
    onSuggested: (draft) => _onAiSuggested(key, controller, draft),
    onAccepted: () => _onAiReviewed(key),
  );

  /// Pull a reusable template (PENTEST_MIAUW §17) into this finding and let the
  /// tester specialise it: the title, CVSS, CWE and the four sections are filled
  /// from the template; the scope object, CVE ids and finding id stay as the
  /// tester set them for this engagement.
  Future<void> _pickTemplate() async {
    final template = await FindingTemplatePicker.show(context);
    if (template == null) return;
    final spec = template.toFindingSpec();
    _heading.text = spec.heading;
    _cvss.text = spec.cvssVector;
    _cwe.text = _composeCwe(spec);
    _description.text = spec.description;
    _confirmation.text = spec.confirmation;
    _impact.text = spec.impact;
    _recommendation.text = spec.recommendation;
  }

  /// Pick a weakness from the offline CWE catalog (§10.6): always set the CWE
  /// field, and fill the description / recommendation **only when they are
  /// still empty** with the entry's deterministic snippet — so a picked CWE
  /// gives a head start without ever overwriting text the tester already wrote.
  Future<void> _pickCwe() async {
    final entry = await CwePicker.show(context);
    if (entry == null) return;
    _cwe.text = entry.label;
    if (_description.text.trim().isEmpty) _description.text = entry.description;
    if (_recommendation.text.trim().isEmpty) {
      _recommendation.text = entry.recommendation;
    }
  }

  @override
  Widget build(BuildContext context) {
    return EditorFieldList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pickTemplate,
                icon: const Icon(Icons.library_books_outlined, size: 16),
                label: Text(context.l10n.d('Uit sjabloon…')),
              ),
              OutlinedButton.icon(
                onPressed: _pickCwe,
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: Text(context.l10n.d('Kies CWE…')),
              ),
            ],
          ),
        ),
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
        _suggest(FindingAiField.description, 'description', _description),
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
        _suggest(FindingAiField.impact, 'impact', _impact),
        EditorField(
          label: 'Aanbeveling',
          controller: _recommendation,
          maxLines: 4,
        ),
        _suggest(
          FindingAiField.recommendation,
          'recommendation',
          _recommendation,
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
