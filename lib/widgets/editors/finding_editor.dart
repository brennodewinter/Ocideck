import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/finding_spec.dart';
import '../../models/slide.dart';
import '../../services/cvss/cvss4.dart';
import '../../services/finding_ai_service.dart';
import '../../services/image_service.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';
import '../../utils/project_path.dart';
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
class FindingEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final String? projectPath;
  final bool nestedInScrollView;

  const FindingEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    this.projectPath,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<FindingEditor> createState() => _FindingEditorState();
}

class _FindingEditorState extends ConsumerState<FindingEditor>
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
        const SizedBox(height: 8),
        _evidenceSection(context.l10n),
      ],
    );
  }

  /// Evidence attached to this finding: screenshots and videos, each stored as
  /// its own slide in the finding group (role `evidence`) right after the
  /// header — so evidence rides with the finding and round-trips as part of it.
  Widget _evidenceSection(AppLocalizations l10n) {
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    final findingId = _findingId.text.trim();
    final evidence = <(int, Slide)>[
      if (deck != null && findingId.isNotEmpty)
        for (var i = 0; i < deck.slides.length; i++)
          if (deck.slides[i].findingRole == FindingRole.evidence &&
              deck.slides[i].findingId == findingId)
            (i, deck.slides[i]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Bewijs'),
        Text(
          l10n.d(
            'Voeg screenshots of video\'s toe als bewijs. Elk stuk bewijs komt als eigen slide direct na de bevinding en telt mee in de export.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
        const SizedBox(height: 8),
        for (final (index, slide) in evidence)
          _evidenceTile(l10n, index, slide),
        if (evidence.isNotEmpty) const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: findingId.isEmpty ? null : _addScreenshot,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: Text(l10n.d('Screenshot toevoegen')),
            ),
            OutlinedButton.icon(
              onPressed: findingId.isEmpty ? null : _addVideo,
              icon: const Icon(Icons.video_call_outlined, size: 16),
              label: Text(l10n.d('Video toevoegen')),
            ),
          ],
        ),
        if (findingId.isEmpty) ...[
          const SizedBox(height: 4),
          Text(
            l10n.d('Geef eerst een bevinding-id op om bewijs te koppelen.'),
            style: TextStyle(fontSize: 11, color: AppTheme.amber700),
          ),
        ],
      ],
    );
  }

  /// One evidence slide: a small preview (screenshot thumbnail or a video icon)
  /// with its file name, plus jump-to-edit and remove actions.
  Widget _evidenceTile(AppLocalizations l10n, int index, Slide slide) {
    final isVideo = slide.type == SlideType.video;
    final path = isVideo ? slide.videoPath : slide.imagePath;
    final name = path.isEmpty
        ? l10n.d('(nog leeg)')
        : path.split(Platform.pathSeparator).last.split('/').last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 44, height: 30, child: _evidenceThumb(isVideo, path)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppTheme.slate700),
            ),
          ),
          IconButton(
            tooltip: l10n.d('Bewerk deze slide'),
            icon: const Icon(Icons.edit_outlined, size: 16),
            visualDensity: VisualDensity.compact,
            color: AppTheme.slate500,
            onPressed: () => ref.read(editorProvider.notifier).select(index),
          ),
          IconButton(
            tooltip: l10n.d('Bewijs verwijderen'),
            icon: const Icon(Icons.delete_outline, size: 16),
            visualDensity: VisualDensity.compact,
            color: AppTheme.slate500,
            onPressed: () => ref.read(deckProvider.notifier).removeSlide(index),
          ),
        ],
      ),
    );
  }

  Widget _evidenceThumb(bool isVideo, String path) {
    if (!isVideo && path.isNotEmpty) {
      final resolved = resolveEditorAssetPath(path, widget.projectPath);
      if (resolved != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            File(resolved),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _evidenceIcon(isVideo),
          ),
        );
      }
    }
    return _evidenceIcon(isVideo);
  }

  Widget _evidenceIcon(bool isVideo) => Container(
    decoration: BoxDecoration(
      color: AppTheme.slate100,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Icon(
      isVideo ? Icons.movie_outlined : Icons.image_outlined,
      size: 16,
      color: AppTheme.slate400,
    ),
  );

  /// Insert [evidence] right after this finding's group (its header plus any
  /// existing detail/evidence slides that share the id).
  void _insertEvidence(Slide evidence) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final findingId = _findingId.text.trim();
    var afterIndex = deck.slides.indexWhere((s) => s.id == widget.slide.id);
    if (afterIndex < 0) return;
    for (var i = afterIndex + 1; i < deck.slides.length; i++) {
      if (deck.slides[i].findingId == findingId &&
          deck.slides[i].findingRole != FindingRole.header) {
        afterIndex = i;
      } else {
        break;
      }
    }
    ref.read(deckProvider.notifier).insertSlides([
      evidence,
    ], afterIndex: afterIndex);
  }

  Future<void> _addScreenshot() async {
    final path = await pickImageWithFeedback(
      context,
      widget.imageService,
      projectPath: widget.projectPath,
    );
    if (path == null || !mounted) return;
    _insertEvidence(
      Slide.create(SlideType.image).copyWith(
        imagePath: path,
        findingId: _findingId.text.trim(),
        findingRole: FindingRole.evidence,
      ),
    );
  }

  Future<void> _addVideo() async {
    final path = await widget.imageService.pickVideo(
      projectPath: widget.projectPath,
    );
    if (path == null || !mounted) return;
    _insertEvidence(
      Slide.create(SlideType.video).copyWith(
        videoPath: path,
        findingId: _findingId.text.trim(),
        findingRole: FindingRole.evidence,
      ),
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
