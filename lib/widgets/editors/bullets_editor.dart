import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../markdown_editor/markdown_editor.dart';
import '_editor_field.dart';
import 'bullet_marker_selector.dart';
import 'list_style_selector.dart';

class BulletsEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const BulletsEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<BulletsEditor> createState() => _BulletsEditorState();
}

class _BulletsEditorState extends State<BulletsEditor> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late List<TextEditingController> _bullets;
  late List<int> _levels;
  late List<bool> _checked;
  late List<FocusNode> _focusNodes;
  late ListStyle _listStyle;
  BulletMarker? _bulletMarkerOverride;
  late bool _showChecklistProgress;
  late final TextEditingController _richText;

  static const _maxLevel = 4;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
    _subtitle = TextEditingController(text: widget.slide.subtitle);
    _subtitle.addListener(_emit);
    _listStyle = widget.slide.listStyle;
    _bulletMarkerOverride = widget.slide.bulletMarkerOverride;
    _showChecklistProgress = widget.slide.showChecklistProgress;
    _richText = TextEditingController(
      text: normalizeRichTextMarkdown(widget.slide.customMarkdown),
    );
    _richText.addListener(_emit);
    _initBullets(widget.slide.bullets);
  }

  void _initBullets(List<String> raw) {
    final list = raw.isEmpty ? [''] : raw;
    _levels = list.map(_levelOf).toList();
    _checked = list.map(checklistItemChecked).toList();
    _bullets = list.map((b) => _makeCtrl(checklistItemText(b))).toList();
    _focusNodes = List.generate(_bullets.length, (_) => FocusNode());
  }

  static int _levelOf(String b) {
    int l = 0;
    while (l < b.length && b[l] == '\t' && l < _maxLevel) {
      l++;
    }
    return l;
  }

  TextEditingController _makeCtrl(String text) {
    final c = TextEditingController(text: text);
    c.addListener(_emit);
    return c;
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        subtitle: _subtitle.text,
        listStyle: _listStyle,
        bulletMarkerOverride: _bulletMarkerOverride,
        clearBulletMarkerOverride: _bulletMarkerOverride == null,
        showChecklistProgress: _showChecklistProgress,
        customMarkdown: _listStyle == ListStyle.richText
            ? normalizeRichTextMarkdown(_richText.text)
            : widget.slide.customMarkdown,
        bullets: _listStyle == ListStyle.richText
            ? widget.slide.bullets
            : List.generate(
                _bullets.length,
                (i) => _listStyle == ListStyle.checklist
                    ? checklistBullet(
                        level: _levels[i],
                        text: _bullets[i].text,
                        checked: _checked[i],
                      )
                    : '\t' * _levels[i] + _bullets[i].text,
              ),
      ),
    );
  }

  void _reorderItem(int oldIndex, int newIndex) {
    _moveBullet(oldIndex, newIndex);
  }

  void _moveBullet(int oldIndex, int newIndex) {
    setState(() {
      final ctrl = _bullets.removeAt(oldIndex);
      final level = _levels.removeAt(oldIndex);
      final checked = _checked.removeAt(oldIndex);
      final focus = _focusNodes.removeAt(oldIndex);
      _bullets.insert(newIndex, ctrl);
      _levels.insert(newIndex, level);
      _checked.insert(newIndex, checked);
      _focusNodes.insert(newIndex, focus);
    });
    _emit();
  }

  void _addBulletAfter(int i) {
    final newLevel = _levels[i]; // inherit current level
    setState(() {
      _bullets.insert(i + 1, _makeCtrl(''));
      _levels.insert(i + 1, newLevel);
      _checked.insert(i + 1, false);
      _focusNodes.insert(i + 1, FocusNode());
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (i + 1 < _focusNodes.length) _focusNodes[i + 1].requestFocus();
    });
  }

  void _removeBulletAndFocus(int i) {
    if (_bullets.length == 1) {
      setState(() {
        _bullets[i].removeListener(_emit);
        _bullets[i].clear();
        _bullets[i].addListener(_emit);
        _levels[i] = 0;
        _checked[i] = false;
      });
      _emit();
      _focusNodes[i].requestFocus();
      return;
    }
    final target = (i - 1).clamp(0, _bullets.length - 2);
    setState(() {
      _bullets[i].removeListener(_emit);
      _bullets[i].dispose();
      _bullets.removeAt(i);
      _levels.removeAt(i);
      _checked.removeAt(i);
      _focusNodes[i].dispose();
      _focusNodes.removeAt(i);
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target < _focusNodes.length) _focusNodes[target].requestFocus();
    });
  }

  Future<void> _handlePaste(int i) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    final lines = data!.text!
        .split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'^[-*•◦▪▫]\s*'), ''))
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    if (lines.length == 1) {
      final ctrl = _bullets[i];
      final sel = ctrl.selection;
      final start = sel.isValid ? sel.start : ctrl.text.length;
      final end = sel.isValid ? sel.end : ctrl.text.length;
      ctrl.value = TextEditingValue(
        text: ctrl.text.replaceRange(start, end, lines[0]),
        selection: TextSelection.collapsed(offset: start + lines[0].length),
      );
      return;
    }

    setState(() {
      _bullets[i].removeListener(_emit);
      _bullets[i].dispose();
      _bullets[i] = _makeCtrl(lines[0]);
      for (int j = 1; j < lines.length; j++) {
        _bullets.insert(i + j, _makeCtrl(lines[j]));
        _levels.insert(i + j, _levels[i]);
        _checked.insert(i + j, false);
        _focusNodes.insert(i + j, FocusNode());
      }
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final last = i + lines.length - 1;
      if (last < _focusNodes.length) _focusNodes[last].requestFocus();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _richText.dispose();
    for (final c in _bullets) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
        const SizedBox(height: 12),
        EditorField(
          label: l10n.d('Subkop (optioneel)'),
          controller: _subtitle,
          hint: l10n.d('Subkop'),
        ),
        const SizedBox(height: 16),
        ListStyleSelector(
          value: _listStyle,
          onChanged: (value) {
            setState(() => _listStyle = value);
            _emit();
          },
        ),
        if (_listStyle == ListStyle.bullets) ...[
          const SizedBox(height: 12),
          BulletMarkerSelector(
            value: _bulletMarkerOverride,
            onChanged: (value) {
              setState(() => _bulletMarkerOverride = value);
              _emit();
            },
          ),
        ],
        if (_listStyle == ListStyle.checklist)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.d('Voortgangsgrafiek tonen')),
            subtitle: Text(
              l10n.d('Toont afgevinkt en niet afgevinkt als percentages.'),
            ),
            value: _showChecklistProgress,
            onChanged: (value) {
              setState(() => _showChecklistProgress = value);
              _emit();
            },
          ),
        if (_listStyle == ListStyle.richText) ...[
          const SizedBox(height: 16),
          const SectionLabel('Tekst'),
          SizedBox(
            height: 320,
            child: MarkdownNotesEditor.legacy(
              controller: _richText,
              baseStyle: const TextStyle(fontSize: 14, height: 1.45),
              linkColor: const Color(0xFF2563EB),
              hintText: l10n.d('Tekst...'),
              expand: true,
              minLines: 8,
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          const SectionLabel('Bullets'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _reorderItem,
            children: [
              for (int i = 0; i < _bullets.length; i++) _buildBulletRow(i),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addBulletAfter(_bullets.length - 1),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Bullet toevoegen')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBulletRow(int i) {
    final l10n = context.l10n;
    final level = _levels[i];
    return Padding(
      key: ValueKey(_bullets[i]),
      padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            index: i,
            child: const Icon(
              Icons.drag_indicator,
              size: 16,
              color: Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(width: 4),
          if (_listStyle == ListStyle.checklist)
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                key: ValueKey('checklist-item-$i'),
                value: _checked[i],
                onChanged: (value) {
                  setState(() => _checked[i] = value ?? false);
                  _emit();
                },
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            Text(
              _markerForItem(i),
              style: const TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                // Enter → nieuwe bullet
                if (event.logicalKey == LogicalKeyboardKey.enter) {
                  _addBulletAfter(i);
                  return KeyEventResult.handled;
                }
                // Backspace op lege bullet → verwijder
                if (event.logicalKey == LogicalKeyboardKey.backspace &&
                    _bullets[i].text.isEmpty &&
                    _bullets.length > 1) {
                  _removeBulletAndFocus(i);
                  return KeyEventResult.handled;
                }
                // Tab → inspringing
                if (event.logicalKey == LogicalKeyboardKey.tab) {
                  if (HardwareKeyboard.instance.isShiftPressed) {
                    if (_levels[i] > 0) setState(() => _levels[i]--);
                  } else {
                    if (_levels[i] < _maxLevel) setState(() => _levels[i]++);
                  }
                  _emit();
                  return KeyEventResult.handled;
                }
                // Cmd/Ctrl+V → slim plakken
                if (event.logicalKey == LogicalKeyboardKey.keyV &&
                    (HardwareKeyboard.instance.isMetaPressed ||
                        HardwareKeyboard.instance.isControlPressed)) {
                  _handlePaste(i);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _bullets[i],
                focusNode: _focusNodes[i],
                decoration: InputDecoration(
                  hintText: '${l10n.d('Bullet')} ${i + 1}',
                  isDense: true,
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('remove-bullet-$i'),
            icon: const Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: Color(0xFF64748B),
            ),
            onPressed: () => _removeBulletAndFocus(i),
            tooltip: l10n.d('Verwijder'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
          ),
        ],
      ),
    );
  }

  String _markerForLevel(int level) {
    const markers = ['•', '◦', '▪', '▫', '–'];
    return markers[level.clamp(0, markers.length - 1)];
  }

  String _markerForItem(int index) {
    if (_listStyle == ListStyle.bullets) {
      return _markerForLevel(_levels[index]);
    }
    if (_listStyle == ListStyle.checklist) return '';
    final level = _levels[index];
    var number = 0;
    for (var i = 0; i <= index; i++) {
      if (_levels[i] == level) number++;
      if (_levels[i] < level) number = 0;
    }
    return '$number.';
  }
}
