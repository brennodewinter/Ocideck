import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

class BulletsEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const BulletsEditor({super.key, required this.slide, required this.onUpdate});

  @override
  State<BulletsEditor> createState() => _BulletsEditorState();
}

class _BulletsEditorState extends State<BulletsEditor> {
  late final TextEditingController _title;
  late List<TextEditingController> _bullets;
  late List<int> _levels;
  late List<FocusNode> _focusNodes;

  static const _maxLevel = 4;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
    _initBullets(widget.slide.bullets);
  }

  void _initBullets(List<String> raw) {
    final list = raw.isEmpty ? [''] : raw;
    _levels = list.map(_levelOf).toList();
    _bullets = list.map((b) => _makeCtrl(b.trimLeft())).toList();
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
        bullets: List.generate(
          _bullets.length,
          (i) => '\t' * _levels[i] + _bullets[i].text,
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
      final focus = _focusNodes.removeAt(oldIndex);
      _bullets.insert(newIndex, ctrl);
      _levels.insert(newIndex, level);
      _focusNodes.insert(newIndex, focus);
    });
    _emit();
  }

  void _addBulletAfter(int i) {
    final newLevel = _levels[i]; // inherit current level
    setState(() {
      _bullets.insert(i + 1, _makeCtrl(''));
      _levels.insert(i + 1, newLevel);
      _focusNodes.insert(i + 1, FocusNode());
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (i + 1 < _focusNodes.length) _focusNodes[i + 1].requestFocus();
    });
  }

  void _removeBulletAndFocus(int i) {
    if (_bullets.length <= 1) return;
    final target = (i - 1).clamp(0, _bullets.length - 2);
    setState(() {
      _bullets[i].removeListener(_emit);
      _bullets[i].dispose();
      _bullets.removeAt(i);
      _levels.removeAt(i);
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
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
            label: const Text('Bullet toevoegen'),
          ),
        ),
      ],
    );
  }

  Widget _buildBulletRow(int i) {
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
          Text(
            _markerForLevel(level),
            style: const TextStyle(fontSize: 16, color: Color(0xFF94A3B8)),
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
                  hintText: 'Bullet ${i + 1}',
                  isDense: true,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
            onPressed: _bullets.length > 1
                ? () => _removeBulletAndFocus(i)
                : null,
            tooltip: 'Verwijder',
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
}
