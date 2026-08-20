import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/improvement/flow_slide.dart';
import '../../services/improvement/flow_spec.dart';
import '../../services/improvement_ai_service.dart';
import '_editor_field.dart';
import 'improvement_ai_suggest_field.dart';
import 'editor_text_controller.dart';

/// Editor for a Procesverbetering `flow` slide (PROCESS_IMPROVEMENT §3.4).
///
/// Steps live in [Slide.bullets] as `title :: kind :: attrs`; layout and template
/// ride in `ocideck_layout` / `ocideck_template` comments on disk.
class FlowEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const FlowEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<FlowEditor> createState() => _FlowEditorState();
}

class _FlowEditorState extends ConsumerState<FlowEditor> {
  late final EditorTextController _title;
  late String _templateId;
  late String _layoutToken;
  late List<EditorTextController> _bullets;
  late Set<String> _aiFields;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title)
      ..addTextListener(_emit);
    _templateId = widget.slide.improvementTemplateId.isEmpty
        ? kDefaultFlowTemplateId
        : widget.slide.improvementTemplateId;
    _layoutToken = widget.slide.improvementLayout.isNotEmpty
        ? widget.slide.improvementLayout
        : flowLayoutToken(flowLayoutOf(widget.slide));
    _bullets = [];
    _loadBullets(widget.slide.bullets);
    _aiFields = {...widget.slide.aiAssistedFields};
  }

  @override
  void didUpdateWidget(covariant FlowEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id) {
      _title.text = widget.slide.title;
      _templateId = widget.slide.improvementTemplateId.isEmpty
          ? kDefaultFlowTemplateId
          : widget.slide.improvementTemplateId;
      _layoutToken = widget.slide.improvementLayout.isNotEmpty
          ? widget.slide.improvementLayout
          : flowLayoutToken(flowLayoutOf(widget.slide));
      _loadBullets(widget.slide.bullets);
      _aiFields = {...widget.slide.aiAssistedFields};
    }
  }

  String _fieldKey(int index) => 'flow:$index';

  String _siblingText(int exceptIndex) => [
    for (var i = 0; i < _bullets.length; i++)
      if (i != exceptIndex && _bullets[i].text.trim().isNotEmpty)
        'Step ${i + 1}: ${_bullets[i].text.trim()}',
  ].join('\n');

  ImprovementAiContext _aiContext(int index) => ImprovementAiContext(
    slideTitle: _title.text,
    templateId: _templateId,
    layout: _layoutToken,
    fieldLabel: 'Step ${index + 1}',
    existingText: _bullets[index].text,
    siblingText: _siblingText(index),
  );

  void _onAiSuggested(int index, String draft) {
    setState(() => _aiFields.add(_fieldKey(index)));
    _bullets[index].text = draft;
  }

  void _onAiReviewed(int index) {
    setState(() => _aiFields.remove(_fieldKey(index)));
    _emit();
  }

  void _loadBullets(List<String> raw) {
    _disposeBullets();
    if (raw.isEmpty) {
      _bullets = [EditorTextController()..addTextListener(_emit)];
      return;
    }
    _bullets = [
      for (final item in raw)
        EditorTextController(text: bulletText(item))..addTextListener(_emit),
    ];
  }

  void _disposeBullets() {
    for (final c in _bullets) {
      c.dispose();
    }
    _bullets = [];
  }

  @override
  void dispose() {
    _title.dispose();
    _disposeBullets();
    super.dispose();
  }

  List<String> _encodedBullets() => [for (final c in _bullets) c.text];

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        bullets: _encodedBullets(),
        improvementTemplateId: _templateId,
        improvementLayout: _layoutToken,
        aiAssistedFields: _aiFields.toList(),
      ),
    );
  }

  void _setTemplate(String id) {
    if (id == _templateId) return;
    final template = flowTemplateById(id);
    setState(() {
      _templateId = id;
      _layoutToken = flowLayoutToken(
        template?.defaultLayout ?? FlowLayout.flow,
      );
      _loadBullets(flowStarterBullets(id));
    });
    _emit();
  }

  void _setLayout(String token) {
    if (token == _layoutToken) return;
    setState(() => _layoutToken = token);
    _emit();
  }

  void _addBullet({int after = -1}) {
    setState(() {
      final idx = after < 0 ? _bullets.length : after + 1;
      _bullets.insert(idx, EditorTextController()..addTextListener(_emit));
    });
    _emit();
  }

  void _removeBullet(int index) {
    if (_bullets.length <= 1) return;
    setState(() {
      _bullets.removeAt(index).dispose();
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
          initialValue: bundledFlowTemplates.any((t) => t.id == _templateId)
              ? _templateId
              : kDefaultFlowTemplateId,
          isExpanded: true,
          items: [
            for (final t in bundledFlowTemplates)
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
        Text(l10n.d('Lay-out'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: flowLayoutToken(FlowLayout.flow),
              label: Text(l10n.d('Stroom')),
            ),
            ButtonSegment(
              value: flowLayoutToken(FlowLayout.swimlane),
              label: Text(l10n.d('Zwembanen')),
            ),
            ButtonSegment(
              value: flowLayoutToken(FlowLayout.vsm),
              label: Text(l10n.d('VSM')),
            ),
          ],
          selected: {_layoutToken},
          onSelectionChanged: (s) => _setLayout(s.first),
        ),
        const SizedBox(height: 12),
        Text(l10n.d('Punten'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        for (var i = 0; i < _bullets.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditorField(
                      controller: _bullets[i],
                      label: '',
                      maxLines: 2,
                    ),
                    ImprovementAiSuggestField(
                      field: ImprovementAiField.flowStep,
                      fieldKey: _fieldKey(i),
                      contextBuilder: () => _aiContext(i),
                      hasExistingText: _bullets[i].text.trim().isNotEmpty,
                      isAiDraft: _aiFields.contains(_fieldKey(i)),
                      onSuggested: (draft) => _onAiSuggested(i, draft),
                      onAccepted: () => _onAiReviewed(i),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: l10n.d('Punt toevoegen'),
                    onPressed: () => _addBullet(after: i),
                  ),
                  if (_bullets.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      tooltip: l10n.d('Punt verwijderen'),
                      onPressed: () => _removeBullet(i),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addBullet(),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Punt toevoegen')),
          ),
        ),
      ],
    );
    if (widget.nestedInScrollView) return body;
    return SingleChildScrollView(child: body);
  }
}
