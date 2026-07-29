import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/improvement/tree_slide.dart';
import '../../services/improvement/tree_spec.dart';
import '../../services/improvement_ai_service.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';
import 'improvement_ai_suggest_field.dart';

/// Editor for a Procesverbetering `tree` slide (PROCESS_IMPROVEMENT §3.3).
///
/// Depth lives in tab-indented [Slide.bullets]; layout and template ride in
/// `ocideck_layout` / `ocideck_template` comments on disk.
class TreeEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const TreeEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<TreeEditor> createState() => _TreeEditorState();
}

class _TreeEditorState extends ConsumerState<TreeEditor> {
  late final TextEditingController _title;
  late String _templateId;
  late String _layoutToken;
  late List<TextEditingController> _bullets;
  late List<int> _levels;
  late Set<String> _aiFields;

  static const _maxLevel = 6;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title)
      ..addListener(_emit);
    _templateId = widget.slide.improvementTemplateId.isEmpty
        ? kDefaultTreeTemplateId
        : widget.slide.improvementTemplateId;
    _layoutToken = widget.slide.improvementLayout.isNotEmpty
        ? widget.slide.improvementLayout
        : treeLayoutToken(treeLayoutOf(widget.slide));
    _bullets = [];
    _levels = [];
    _loadBullets(widget.slide.bullets);
    _aiFields = {...widget.slide.aiAssistedFields};
  }

  @override
  void didUpdateWidget(covariant TreeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id) {
      _title.text = widget.slide.title;
      _templateId = widget.slide.improvementTemplateId.isEmpty
          ? kDefaultTreeTemplateId
          : widget.slide.improvementTemplateId;
      _layoutToken = widget.slide.improvementLayout.isNotEmpty
          ? widget.slide.improvementLayout
          : treeLayoutToken(treeLayoutOf(widget.slide));
      _loadBullets(widget.slide.bullets);
      _aiFields = {...widget.slide.aiAssistedFields};
    }
  }

  String _fieldKey(int index) => 'tree:$index';

  String _siblingText(int exceptIndex) => [
    for (var i = 0; i < _bullets.length; i++)
      if (i != exceptIndex && _bullets[i].text.trim().isNotEmpty)
        'L${_levels[i]}: ${_bullets[i].text.trim()}',
  ].join('\n');

  ImprovementAiContext _aiContext(int index) => ImprovementAiContext(
    slideTitle: _title.text,
    templateId: _templateId,
    layout: _layoutToken,
    fieldLabel: 'Bullet ${index + 1} (level ${_levels[index]})',
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
      _bullets = [TextEditingController()..addListener(_emit)];
      _levels = [0];
      return;
    }
    _bullets = [];
    _levels = [];
    for (final item in raw) {
      _bullets.add(
        TextEditingController(text: bulletText(item))..addListener(_emit),
      );
      _levels.add(bulletLevel(item).clamp(0, _maxLevel));
    }
  }

  void _disposeBullets() {
    for (final c in _bullets) {
      c.dispose();
    }
    _bullets = [];
    _levels = [];
  }

  @override
  void dispose() {
    _title.dispose();
    _disposeBullets();
    super.dispose();
  }

  List<String> _encodedBullets() => [
    for (var i = 0; i < _bullets.length; i++)
      '${'\t' * _levels[i]}${_bullets[i].text}',
  ];

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
    final template = treeTemplateById(id);
    setState(() {
      _templateId = id;
      _layoutToken = treeLayoutToken(
        template?.defaultLayout ?? TreeLayout.tree,
      );
      _loadBullets(treeStarterBullets(id));
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
      final level = after < 0 ? 0 : _levels[after];
      _bullets.insert(idx, TextEditingController()..addListener(_emit));
      _levels.insert(idx, level);
    });
    _emit();
  }

  void _removeBullet(int index) {
    if (_bullets.length <= 1) return;
    setState(() {
      _bullets.removeAt(index).dispose();
      _levels.removeAt(index);
    });
    _emit();
  }

  void _indent(int index, int delta) {
    final next = (_levels[index] + delta).clamp(0, _maxLevel);
    if (next == _levels[index]) return;
    setState(() => _levels[index] = next);
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
          initialValue: bundledTreeTemplates.any((t) => t.id == _templateId)
              ? _templateId
              : kDefaultTreeTemplateId,
          isExpanded: true,
          items: [
            for (final t in bundledTreeTemplates)
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
              value: treeLayoutToken(TreeLayout.tree),
              label: Text(l10n.d('Boom')),
            ),
            ButtonSegment(
              value: treeLayoutToken(TreeLayout.fishbone),
              label: Text(l10n.d('Visgraat')),
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
              SizedBox(
                width: 52,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    'L${_levels[i]}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: _levels[i] * 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EditorField(
                        controller: _bullets[i],
                        label: '',
                        maxLines: 2,
                      ),
                      ImprovementAiSuggestField(
                        field: ImprovementAiField.treeBullet,
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
              ),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.format_indent_increase, size: 18),
                    tooltip: l10n.d('Inspringen'),
                    onPressed: _levels[i] < _maxLevel
                        ? () => _indent(i, 1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_indent_decrease, size: 18),
                    tooltip: l10n.d('Uitspringen'),
                    onPressed: _levels[i] > 0 ? () => _indent(i, -1) : null,
                  ),
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
