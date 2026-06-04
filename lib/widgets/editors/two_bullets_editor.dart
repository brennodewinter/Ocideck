import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';

typedef _Mutate = void Function(VoidCallback fn);

class TwoBulletsEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const TwoBulletsEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
  });

  @override
  State<TwoBulletsEditor> createState() => _TwoBulletsEditorState();
}

class _TwoBulletsEditorState extends State<TwoBulletsEditor> {
  late final TextEditingController _title;
  late _BulletSet _left;
  late _BulletSet _right;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
    _left = _BulletSet(widget.slide.bullets, _emit);
    _right = _BulletSet(widget.slide.bullets2, _emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        bullets: _left.values,
        bullets2: _right.values,
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final columns = [
              _BulletColumn(label: 'Bullets links', set: _left, emit: _emit),
              _BulletColumn(label: 'Bullets rechts', set: _right, emit: _emit),
            ];
            if (narrow) {
              return Column(
                children: [columns[0], const SizedBox(height: 18), columns[1]],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: columns[0]),
                const SizedBox(width: 16),
                Expanded(child: columns[1]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BulletSet {
  static const maxLevel = 4;

  final VoidCallback emit;
  late List<TextEditingController> controllers;
  late List<int> levels;
  late List<FocusNode> focusNodes;

  _BulletSet(List<String> raw, this.emit) {
    final list = raw.isEmpty ? [''] : raw;
    levels = list.map(_levelOf).toList();
    controllers = list.map((b) => _makeCtrl(b.trimLeft())).toList();
    focusNodes = List.generate(controllers.length, (_) => FocusNode());
  }

  List<String> get values => List.generate(
    controllers.length,
    (i) => '\t' * levels[i] + controllers[i].text,
  );

  static int _levelOf(String b) {
    int l = 0;
    while (l < b.length && b[l] == '\t' && l < maxLevel) {
      l++;
    }
    return l;
  }

  TextEditingController _makeCtrl(String text) {
    final c = TextEditingController(text: text);
    c.addListener(emit);
    return c;
  }

  void addAfter(_Mutate mutate, int i) {
    mutate(() {
      controllers.insert(i + 1, _makeCtrl(''));
      levels.insert(i + 1, levels[i]);
      focusNodes.insert(i + 1, FocusNode());
    });
    emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (i + 1 < focusNodes.length) focusNodes[i + 1].requestFocus();
    });
  }

  void removeAndFocus(_Mutate mutate, int i) {
    if (controllers.length <= 1) return;
    final target = (i - 1).clamp(0, controllers.length - 2);
    mutate(() {
      controllers[i].removeListener(emit);
      controllers[i].dispose();
      controllers.removeAt(i);
      levels.removeAt(i);
      focusNodes[i].dispose();
      focusNodes.removeAt(i);
    });
    emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target < focusNodes.length) focusNodes[target].requestFocus();
    });
  }

  Future<void> paste(_Mutate mutate, int i) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    final lines = data!.text!
        .split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'^[-*•◦▪▫]\s*'), ''))
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    if (lines.length == 1) {
      final ctrl = controllers[i];
      final sel = ctrl.selection;
      final start = sel.isValid ? sel.start : ctrl.text.length;
      final end = sel.isValid ? sel.end : ctrl.text.length;
      ctrl.value = TextEditingValue(
        text: ctrl.text.replaceRange(start, end, lines[0]),
        selection: TextSelection.collapsed(offset: start + lines[0].length),
      );
      return;
    }

    mutate(() {
      controllers[i].removeListener(emit);
      controllers[i].dispose();
      controllers[i] = _makeCtrl(lines[0]);
      for (int j = 1; j < lines.length; j++) {
        controllers.insert(i + j, _makeCtrl(lines[j]));
        levels.insert(i + j, levels[i]);
        focusNodes.insert(i + j, FocusNode());
      }
    });
    emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final last = i + lines.length - 1;
      if (last < focusNodes.length) focusNodes[last].requestFocus();
    });
  }

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
  }
}

class _BulletColumn extends StatefulWidget {
  final String label;
  final _BulletSet set;
  final VoidCallback emit;

  const _BulletColumn({
    required this.label,
    required this.set,
    required this.emit,
  });

  @override
  State<_BulletColumn> createState() => _BulletColumnState();
}

class _BulletColumnState extends State<_BulletColumn> {
  _BulletSet get set => widget.set;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(widget.label),
        const SizedBox(height: 6),
        for (int i = 0; i < set.controllers.length; i++) _buildRow(i),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () =>
              set.addAfter((fn) => setState(fn), set.controllers.length - 1),
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.d('Bullet toevoegen')),
        ),
      ],
    );
  }

  Widget _buildRow(int i) {
    final l10n = context.l10n;
    final level = set.levels[i];
    return Padding(
      key: ValueKey(set.controllers[i]),
      padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _markerForLevel(level),
            style: const TextStyle(fontSize: 16, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.enter) {
                  set.addAfter((fn) => setState(fn), i);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.backspace &&
                    set.controllers[i].text.isEmpty &&
                    set.controllers.length > 1) {
                  set.removeAndFocus((fn) => setState(fn), i);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.tab) {
                  if (HardwareKeyboard.instance.isShiftPressed) {
                    if (set.levels[i] > 0) setState(() => set.levels[i]--);
                  } else {
                    if (set.levels[i] < _BulletSet.maxLevel) {
                      setState(() => set.levels[i]++);
                    }
                  }
                  widget.emit();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.keyV &&
                    (HardwareKeyboard.instance.isMetaPressed ||
                        HardwareKeyboard.instance.isControlPressed)) {
                  set.paste((fn) => setState(fn), i);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: set.controllers[i],
                focusNode: set.focusNodes[i],
                decoration: InputDecoration(
                  hintText: '${l10n.d('Bullet')} ${i + 1}',
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
            onPressed: set.controllers.length > 1
                ? () => set.removeAndFocus((fn) => setState(fn), i)
                : null,
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
}
