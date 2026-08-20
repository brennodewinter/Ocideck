import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/improvement/canvas_slide.dart';
import '../../services/improvement/canvas_spec.dart';
import '../../services/improvement_ai_service.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';
import 'improvement_ai_suggest_field.dart';
import 'markdown_editor_field.dart';
import 'editor_text_controller.dart';

/// Editor for a Procesverbetering `canvas` slide (PROCESS_IMPROVEMENT §3.2).
///
/// Storage is ordinary Markdown with `##` region headings plus
/// `<!-- ocideck_template: a3 -->`. The template picker remaps region bodies by
/// key so switching A3 → charter keeps text that still belongs.
class CanvasEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const CanvasEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<CanvasEditor> createState() => _CanvasEditorState();
}

class _CanvasEditorState extends ConsumerState<CanvasEditor> {
  late final EditorTextController _title;
  late String _templateId;
  late List<_RegionControllers> _regions;
  late Set<String> _aiFields;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title)
      ..addTextListener(_emit);
    _templateId = widget.slide.improvementTemplateId.isEmpty
        ? kDefaultCanvasTemplateId
        : widget.slide.improvementTemplateId;
    _regions = _controllersFor(widget.slide.customMarkdown, _templateId);
    _aiFields = {...widget.slide.aiAssistedFields};
  }

  @override
  void didUpdateWidget(covariant CanvasEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id) {
      _title.text = widget.slide.title;
      _templateId = widget.slide.improvementTemplateId.isEmpty
          ? kDefaultCanvasTemplateId
          : widget.slide.improvementTemplateId;
      _disposeRegions();
      _regions = _controllersFor(widget.slide.customMarkdown, _templateId);
      _aiFields = {...widget.slide.aiAssistedFields};
    }
  }

  String _fieldKey(String regionKey) => 'canvas:$regionKey';

  String _siblingText(String exceptKey) => [
    for (final r in _regions)
      if (r.key != exceptKey && r.body.text.trim().isNotEmpty)
        '${r.headingLabel('en', _templateId)}: ${r.body.text.trim()}',
  ].join('\n');

  ImprovementAiContext _aiContext(_RegionControllers region) =>
      ImprovementAiContext(
        slideTitle: _title.text,
        templateId: _templateId,
        fieldLabel: region.headingLabel('en', _templateId),
        existingText: region.body.text,
        siblingText: _siblingText(region.key),
      );

  void _onAiSuggested(
    String key,
    EditorTextController controller,
    String draft,
  ) {
    setState(() => _aiFields.add(key));
    controller.text = draft;
  }

  void _onAiReviewed(String key) {
    setState(() => _aiFields.remove(key));
    _emit();
  }

  List<_RegionControllers> _controllersFor(String md, String templateId) {
    final parsed = canvasRegionsFromMarkdown(md, templateId: templateId);
    return [
      for (final r in parsed)
        _RegionControllers(r.key, r.heading, r.body, _emit),
    ];
  }

  void _disposeRegions() {
    for (final r in _regions) {
      r.dispose();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _disposeRegions();
    super.dispose();
  }

  void _emit() {
    final regions = [
      for (final r in _regions)
        CanvasRegionContent(key: r.key, heading: r.heading, body: r.body.text),
    ];
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        customMarkdown: canvasMarkdownFromRegions(regions),
        improvementTemplateId: _templateId,
        aiAssistedFields: _aiFields.toList(),
      ),
    );
  }

  void _setTemplate(String id) {
    if (id == _templateId) return;
    final remapped = canvasMarkdownForTemplate(
      widget.slide.copyWith(
        customMarkdown: canvasMarkdownFromRegions([
          for (final r in _regions)
            CanvasRegionContent(
              key: r.key,
              heading: r.heading,
              body: r.body.text,
            ),
        ]),
        improvementTemplateId: _templateId,
      ),
      id,
    );
    setState(() {
      _templateId = id;
      _disposeRegions();
      _regions = _controllersFor(remapped, id);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorField(controller: _title, label: l10n.d('Titel')),
        const SizedBox(height: 12),
        Text(l10n.d('Sjabloon'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: bundledCanvasTemplates.any((t) => t.id == _templateId)
              ? _templateId
              : kDefaultCanvasTemplateId,
          isExpanded: true,
          items: [
            for (final t in bundledCanvasTemplates)
              DropdownMenuItem(
                value: t.id,
                child: Text('${t.label(lang)} — ${t.guidance(lang)}'),
              ),
          ],
          onChanged: (v) {
            if (v != null) _setTemplate(v);
          },
        ),
        const SizedBox(height: 12),
        for (final r in _regions) ...[
          Text(
            r.headingLabel(lang, _templateId),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppTheme.accentFg),
          ),
          const SizedBox(height: 4),
          MarkdownEditorField(
            controller: r.body,
            label: l10n.d('Inhoud'),
            minLines: 2,
            maxLines: 4,
          ),
          ImprovementAiSuggestField(
            field: ImprovementAiField.canvasRegion,
            fieldKey: _fieldKey(r.key),
            contextBuilder: () => _aiContext(r),
            hasExistingText: r.body.text.trim().isNotEmpty,
            isAiDraft: _aiFields.contains(_fieldKey(r.key)),
            onSuggested: (draft) =>
                _onAiSuggested(_fieldKey(r.key), r.body, draft),
            onAccepted: () => _onAiReviewed(_fieldKey(r.key)),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
    if (widget.nestedInScrollView) return body;
    return SingleChildScrollView(child: body);
  }
}

class _RegionControllers {
  _RegionControllers(
    this.key,
    this.heading,
    String body,
    VoidCallback onChanged,
  ) : body = EditorTextController(text: body)..addTextListener(onChanged);

  final String key;
  final String heading;
  final EditorTextController body;

  String headingLabel(String lang, String templateId) {
    final t = canvasTemplateById(templateId);
    if (t == null) return heading;
    for (final r in t.regions) {
      if (r.key == key) return r.label(lang);
    }
    return heading;
  }

  void dispose() => body.dispose();
}
