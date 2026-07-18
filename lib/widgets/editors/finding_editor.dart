import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/checklist_spec.dart';
import '../../models/cvss_builder.dart';
import '../../models/finding_spec.dart';
import '../../models/slide.dart';
import '../../services/cvss/cvss4.dart';
import '../../services/finding_ai_service.dart';
import '../../services/finding_context_score.dart';
import '../../services/image_service.dart';
import '../../services/scope_coverage.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';
import '../../utils/project_path.dart';
import '../dialogs/cve_picker.dart';
import '../dialogs/cvss_builder_dialog.dart';
import '../dialogs/cwe_picker.dart';
import '../dialogs/maswe_picker.dart';
import '../dialogs/finding_template_picker.dart';
import '_editor_field.dart';
import 'ai_suggest_field.dart';

/// Structured editor for a `finding` **header** slide (PENTEST_MIAUW §3.1). The
/// fields map one-to-one onto [FindingSpec], which round-trips to plain,
/// human-readable Markdown; the finding-group id is a slide-level field so the
/// finding wizard (`dialogs/finding_wizard.dart`) can attach detail/evidence
/// slides to the same group.
///
/// The CVSS score and severity band are **derived** from the vector by the
/// [Cvss4] engine and shown live — never typed and never stored (§3.1). A full
/// per-metric CVSS builder is the finding wizard's job — it has one
/// (`dialogs/cvss_builder_dialog.dart`); here the vector is entered as text with
/// an immediate score/severity read-out.
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
  late final TextEditingController _maswe;
  late final TextEditingController _cve;
  late final TextEditingController _description;
  late final TextEditingController _confirmation;
  late final TextEditingController _impact;
  late final TextEditingController _recommendation;
  late final TextEditingController _retestNote;

  /// The finding's retest outcome (hertest); the dropdown drives it.
  RetestStatus _retest = RetestStatus.notRetested;

  /// The checklist test id this finding evidences (feedback #8); the test picker
  /// drives it and writes it back to the matching checklist row.
  String _testId = '';

  static final _reMasweId = RegExp(r'MASWE-\d+');
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
    _maswe = newController(spec.masweId, _onChanged);
    _cve = newController(spec.cveIds.join(', '), _onChanged);
    _description = newController(spec.description, _onChanged);
    _confirmation = newController(spec.confirmation, _onChanged);
    _impact = newController(spec.impact, _onChanged);
    _recommendation = newController(spec.recommendation, _onChanged);
    _retest = spec.retest;
    _retestNote = newController(spec.retestNote, _onChanged);
    _testId = spec.testId;
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
      masweId: _reMasweId.firstMatch(_maswe.text)?.group(0) ?? '',
      cweName: cweName,
      cveIds: cveIds,
      description: _description.text,
      confirmation: _confirmation.text,
      impact: _impact.text,
      recommendation: _recommendation.text,
      retest: _retest,
      retestNote: _retestNote.text.trim(),
      testId: _testId,
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
    // De sjabloontaal volgt het rapport, niet de interface (§12.3).
    final language = ref.read(deckProvider).deck?.language ?? '';
    final template = await FindingTemplatePicker.show(
      context,
      languageCode: language,
    );
    if (template == null) return;
    final spec = template.toFindingSpec();
    _heading.text = spec.heading;
    _cvss.text = spec.cvssVector;
    _cwe.text = _composeCwe(spec);
    _maswe.text = spec.masweId;
    _description.text = spec.description;
    _confirmation.text = spec.confirmation;
    _impact.text = spec.impact;
    _recommendation.text = spec.recommendation;
  }

  /// Het MASWE-veld met zijn kiezer ernaast. Vrij te typen, zodat een id dat
  /// nieuwer is dan onze momentopname ook vastgelegd kan worden.
  Widget _masweField(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: EditorField(
          label: 'MASWE',
          controller: _maswe,
          hint: 'MASWE-0005',
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: OutlinedButton.icon(
          onPressed: _pickMaswe,
          icon: const Icon(Icons.search, size: 16),
          label: Text(context.l10n.d('Kiezen')),
        ),
      ),
    ],
  );

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

  /// Kies een mobiele zwakheid uit de gebundelde MASWE-lijst.
  ///
  /// Anders dan bij CWE wordt hier géén beschrijving ingevuld: drie kwart van
  /// MASWE is bij de bron nog een concept, en die conceptomschrijving in het
  /// rapport van een klant laten belanden zou tekst van OWASP presenteren als
  /// bevinding van de tester. Alleen de aanhaling wordt gezet.
  Future<void> _pickMaswe() async {
    final w = await MaswePicker.show(context);
    if (w == null) return;
    _maswe.text = w.id;
  }

  /// Look up a CVE online (gated) and append its id to the CVE field, without
  /// duplicating an id already present. The finding's CVSS is left untouched.
  Future<void> _pickCve() async {
    final id = await CvePicker.show(context);
    if (id == null || !mounted) return;
    final existing = _cve.text.trim();
    final present = _reCve
        .allMatches(existing)
        .map((m) => m.group(0)!.toUpperCase());
    if (present.contains(id.toUpperCase())) return;
    _cve.text = existing.isEmpty ? id : '$existing, $id';
  }

  @override
  Widget build(BuildContext context) {
    // Scope objects (with their CIA ratings) come from the deck's scope matrix,
    // so the scope-object field can pick from them and the CVSS read-out can show
    // a context score for the linked object.
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    final scopeRows = deckScopeRows(deck?.slides ?? const []);
    final scopeObjects = {
      for (final r in scopeRows)
        if (r.object.trim().isNotEmpty) r.object,
    }.toList();
    final scopeCia = scopeObjectCia(
      _scope.text.trim(),
      scopeCiaIndexFromRows(scopeRows),
    );
    final availableTests = _testsForScope(deck?.slides ?? const []);
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
              OutlinedButton.icon(
                onPressed: _pickCve,
                icon: const Icon(Icons.travel_explore, size: 16),
                label: Text(context.l10n.d('Zoek CVE…')),
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
        _scopeField(context, scopeObjects),
        EditorField(
          label: 'CVSS 4.0-vector',
          controller: _cvss,
          hint:
              'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _openCvssWizard(scopeCia),
            icon: const Icon(Icons.tune, size: 16),
            label: Text(context.l10n.d('CVSS-wizard')),
          ),
        ),
        _cvssReadout(context, scopeCia),
        EditorField(
          label: 'CWE',
          controller: _cwe,
          hint: 'CWE-89 — Improper Neutralization of SQL',
        ),
        _masweField(context),
        EditorField(
          label: 'CVE',
          controller: _cve,
          hint: 'CVE-2024-1234, CVE-2024-5678',
        ),
        _testField(context, availableTests),
        _retestField(context),
        if (_retest.isRetested)
          EditorField(
            label: 'Hertest-notitie',
            controller: _retestNote,
            hint: 'bijv. hertest 2026-07-20, patch toegepast',
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
              onPressed: _addScreenshot,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: Text(l10n.d('Screenshot toevoegen')),
            ),
            OutlinedButton.icon(
              onPressed: _addVideo,
              icon: const Icon(Icons.video_call_outlined, size: 16),
              label: Text(l10n.d('Video toevoegen')),
            ),
          ],
        ),
        if (findingId.isEmpty) ...[
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'Zonder bevinding-id maken we er automatisch een aan bij het eerste bewijs.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ],
      ],
    );
  }

  /// The finding-id, generating one when empty so evidence can always be
  /// attached: derived from an `F-xx`-style prefix in the heading when present,
  /// else a short id from the slide id (the tester can renumber later).
  String _ensureFindingId() {
    final current = _findingId.text.trim();
    if (current.isNotEmpty) return current;
    final fromHeading = RegExp(
      r'^\s*([A-Za-z]{1,4}-?\d+)',
    ).firstMatch(_heading.text.trim())?.group(1)?.trim();
    final id = (fromHeading != null && fromHeading.isNotEmpty)
        ? fromHeading
        : 'F-${widget.slide.id.substring(0, 4)}';
    _findingId.text = id; // notifies -> _onChanged -> _emit
    return id;
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
            // Bewijsmateriaal is vaak een schermafdruk van enkele duizenden
            // pixels breed, terwijl deze duim 44 logische pixels meet. Zonder
            // decodeerhint gaat de volledige bitmap naar het geheugen — bij een
            // rapport met tientallen bewijsstukken loopt dat hard op. 176 is
            // vier keer de weergavebreedte en dus ruim boven elke realistische
            // pixelverhouding, zodat er niets zichtbaar verslechtert.
            cacheWidth: 176,
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
        findingId: _ensureFindingId(),
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
        findingId: _ensureFindingId(),
        findingRole: FindingRole.evidence,
      ),
    );
  }

  /// A labelled scope-object field: a free-text input plus a dropdown that fills
  /// it from the deck's scope-matrix objects, so the finding links to a scope
  /// element (and inherits its CIA rating for the context score) without losing
  /// the freedom to type an object that is not in the matrix.
  Widget _scopeField(BuildContext context, List<String> scopeObjects) {
    final l10n = context.l10n;
    // Via a variable (like EditorField) so the URL example is not scanned as a
    // translatable literal — it stays identical across languages.
    const hint = 'https://app.voorbeeld/login';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Scope-object'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _scope,
                minLines: 1,
                maxLines: 1,
                decoration: InputDecoration(hintText: l10n.d(hint)),
              ),
            ),
            if (scopeObjects.isNotEmpty)
              PopupMenuButton<String>(
                icon: Icon(Icons.arrow_drop_down, color: AppTheme.slate500),
                tooltip: l10n.d('Kies uit de scope'),
                onSelected: (v) => _scope.text = v,
                itemBuilder: (_) => [
                  for (final o in scopeObjects)
                    PopupMenuItem(
                      value: o,
                      child: Text(o, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  /// Open the guided CVSS builder seeded from the current vector and the linked
  /// scope object's CIA rating; write the returned Base-only vector back.
  Future<void> _openCvssWizard(CiaRating scopeCia) async {
    final result = await CvssBuilderDialog.show(
      context,
      initialVector: _cvss.text.trim(),
      cia: scopeCia,
    );
    if (result != null && mounted) _cvss.text = result;
  }

  /// The retest (hertest) outcome dropdown: Niet hertest / Opgelost / Nog
  /// aanwezig / Deels opgelost. A note field appears once an outcome is set.
  Widget _retestField(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Hertest'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<RetestStatus>(
          initialValue: _retest,
          isDense: true,
          items: [
            for (final s in RetestStatus.values)
              DropdownMenuItem(value: s, child: Text(l10n.d(s.dutchLabel))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _retest = v);
            _emit();
          },
        ),
      ],
    );
  }

  /// The checklist tests that cover this finding's scope object, de-duplicated by
  /// id — the options for the test picker and the write-back targets.
  List<({String id, String test})> _testsForScope(Iterable<Slide> slides) {
    final scopeKey = normalizeScopeObject(_scope.text.trim());
    if (scopeKey.isEmpty) return const [];
    final out = <({String id, String test})>[];
    final seen = <String>{};
    for (final s in slides) {
      if (s.type != SlideType.checklist) continue;
      if (normalizeScopeObject(s.checklistScope) != scopeKey) continue;
      for (final r in ChecklistSpec.fromSlide(s.title, s.tableRows).rows) {
        final id = r.id.trim();
        if (id.isEmpty || !seen.add(id.toUpperCase())) continue;
        out.add((id: id, test: r.test.trim()));
      }
    }
    return out;
  }

  /// Set the linked test and actively write it back to the matching checklist
  /// row (marking it an anomaly); an empty id unlinks.
  void _pickTest(String testId) {
    final fid = testId.isEmpty ? _findingId.text.trim() : _ensureFindingId();
    setState(() => _testId = testId);
    _emit();
    if (fid.isNotEmpty) {
      ref
          .read(deckProvider.notifier)
          .linkFindingToTest(
            findingId: fid,
            scopeObject: _scope.text.trim(),
            testId: testId,
          );
    }
  }

  /// The test picker (feedback #8): choose which checklist test this finding
  /// evidences. Options are the tests on the checklist(s) covering the scope
  /// object; picking one marks that row as an anomaly linked to this finding.
  Widget _testField(
    BuildContext context,
    List<({String id, String test})> tests,
  ) {
    final l10n = context.l10n;
    final label = Text(
      l10n.d('Gekoppelde test'),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.slate500,
      ),
    );
    if (tests.isEmpty && _testId.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: 5),
          Text(
            l10n.d('Maak eerst een checklist voor dit scope-object.'),
            style: TextStyle(fontSize: 12, color: AppTheme.slate400),
          ),
        ],
      );
    }
    final currentOutsideList =
        _testId.isNotEmpty &&
        !tests.any((t) => t.id.toUpperCase() == _testId.toUpperCase());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: _testId,
          isDense: true,
          items: [
            DropdownMenuItem(value: '', child: Text(l10n.d('Geen'))),
            for (final t in tests)
              DropdownMenuItem(
                value: t.id,
                child: Text(
                  t.test.isEmpty ? t.id : '${t.id} — ${t.test}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (currentOutsideList)
              DropdownMenuItem(value: _testId, child: Text(_testId)),
          ],
          onChanged: (v) => _pickTest(v ?? ''),
        ),
      ],
    );
  }

  /// The derived score chips: nothing when the vector is empty; a muted hint
  /// when it is present but unparseable; otherwise the base score plus — when the
  /// linked scope object carries a CIA rating — the CIA-weighted context score.
  Widget _cvssReadout(BuildContext context, CiaRating scopeCia) {
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
    final weighted = contextCvss(vector, scopeCia);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _scoreBadge(l10n.d('Basis'), cvss),
        if (weighted != null) _scoreBadge(l10n.d('Context'), weighted),
        if (weighted != null)
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
