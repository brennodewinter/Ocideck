import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';
import 'bullet_marker_selector.dart';
import 'list_style_selector.dart';
import 'split_continuation_switch.dart';
import '../../theme/app_theme.dart';

typedef _Mutate = void Function(VoidCallback fn);

class TwoBulletsEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  /// Of de vorige slide met deze een gesplitste reeks kan vormen — bepaalt of
  /// de voortzettingsschakelaar zin heeft.
  final bool canContinueSplit;

  final bool nestedInScrollView;

  const TwoBulletsEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.canContinueSplit = false,
    this.nestedInScrollView = false,
  });

  @override
  State<TwoBulletsEditor> createState() => _TwoBulletsEditorState();
}

class _TwoBulletsEditorState extends State<TwoBulletsEditor> {
  late final TextEditingController _title;
  late final TextEditingController _heading1;
  late final TextEditingController _heading2;
  late _BulletSet _left;
  late _BulletSet _right;
  late ListStyle _listStyle;
  BulletMarker? _bulletMarkerOverride;
  late bool _showChecklistProgress;
  late bool _continuesSplit;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
    _heading1 = TextEditingController(text: widget.slide.columnTitle1);
    _heading2 = TextEditingController(text: widget.slide.columnTitle2);
    _heading1.addListener(_emit);
    _heading2.addListener(_emit);
    _listStyle = widget.slide.listStyle == ListStyle.richText
        ? ListStyle.bullets
        : widget.slide.listStyle;
    _bulletMarkerOverride = widget.slide.bulletMarkerOverride;
    _showChecklistProgress = widget.slide.showChecklistProgress;
    _continuesSplit = widget.slide.continuesSplit;
    _left = _BulletSet(widget.slide.bullets, _emit);
    _right = _BulletSet(widget.slide.bullets2, _emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        columnTitle1: _heading1.text,
        columnTitle2: _heading2.text,
        listStyle: _listStyle,
        bulletMarkerOverride: _bulletMarkerOverride,
        clearBulletMarkerOverride: _bulletMarkerOverride == null,
        showChecklistProgress: _showChecklistProgress,
        // Alleen een slide die daadwerkelijk op een gelijksoortige voorganger
        // volgt kan een voortzetting zijn.
        continuesSplit: widget.canContinueSplit && _continuesSplit,
        bullets: _left.values(_listStyle),
        bullets2: _right.values(_listStyle),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _heading1.dispose();
    _heading2.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
        const SizedBox(height: 16),
        ListStyleSelector(
          value: _listStyle,
          allowRichText: false,
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
        if (widget.canContinueSplit)
          SplitContinuationSwitch(
            value: _continuesSplit,
            onChanged: (value) {
              setState(() => _continuesSplit = value);
              _emit();
            },
          ),
        if (_listStyle == ListStyle.checklist)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.d('Voortgangsgrafiek tonen')),
            subtitle: Text(
              context.l10n.d(
                'Toont afgevinkt en niet afgevinkt als percentages.',
              ),
            ),
            value: _showChecklistProgress,
            onChanged: (value) {
              setState(() => _showChecklistProgress = value);
              _emit();
            },
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final columns = [
              _BulletColumn(
                label: 'Bullets links',
                set: _left,
                emit: _emit,
                headingController: _heading1,
                listStyle: _listStyle,
              ),
              _BulletColumn(
                label: 'Bullets rechts',
                set: _right,
                emit: _emit,
                headingController: _heading2,
                listStyle: _listStyle,
              ),
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
  late List<bool> checked;
  late List<bool> headings;
  late List<FocusNode> focusNodes;

  _BulletSet(List<String> raw, this.emit) {
    final list = raw.isEmpty ? [''] : raw;
    headings = list.map(isGroupHeading).toList();
    levels = list.map((b) => isGroupHeading(b) ? 0 : _levelOf(b)).toList();
    checked = list
        .map((b) => isGroupHeading(b) ? false : checklistItemChecked(b))
        .toList();
    controllers = list
        .map(
          (b) => _makeCtrl(
            isGroupHeading(b) ? groupHeadingText(b) : checklistItemText(b),
          ),
        )
        .toList();
    focusNodes = List.generate(controllers.length, (_) => FocusNode());
  }

  List<String> values(ListStyle listStyle) =>
      List.generate(controllers.length, (i) {
        if (headings[i]) return groupHeadingBullet(controllers[i].text);
        return listStyle == ListStyle.checklist
            ? checklistBullet(
                level: levels[i],
                text: controllers[i].text,
                checked: checked[i],
              )
            : '\t' * levels[i] + controllers[i].text;
      });

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

  void addAfter(_Mutate mutate, int i, {bool heading = false}) {
    mutate(() {
      controllers.insert(i + 1, _makeCtrl(''));
      levels.insert(i + 1, heading ? 0 : levels[i]);
      checked.insert(i + 1, false);
      headings.insert(i + 1, heading);
      focusNodes.insert(i + 1, FocusNode());
    });
    emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (i + 1 < focusNodes.length) focusNodes[i + 1].requestFocus();
    });
  }

  /// Flips row [i] between an ordinary bullet and a group heading.
  void toggleHeading(_Mutate mutate, int i) {
    mutate(() {
      headings[i] = !headings[i];
      if (headings[i]) {
        levels[i] = 0;
        checked[i] = false;
      }
    });
    emit();
    focusNodes[i].requestFocus();
  }

  void removeAndFocus(_Mutate mutate, int i) {
    if (controllers.length == 1) {
      mutate(() {
        controllers[i].removeListener(emit);
        controllers[i].clear();
        controllers[i].addListener(emit);
        levels[i] = 0;
        checked[i] = false;
        headings[i] = false;
      });
      emit();
      focusNodes[i].requestFocus();
      return;
    }
    final target = (i - 1).clamp(0, controllers.length - 2);
    mutate(() {
      controllers[i].removeListener(emit);
      controllers[i].dispose();
      controllers.removeAt(i);
      levels.removeAt(i);
      checked.removeAt(i);
      headings.removeAt(i);
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
      headings[i] = false;
      for (int j = 1; j < lines.length; j++) {
        controllers.insert(i + j, _makeCtrl(lines[j]));
        levels.insert(i + j, levels[i]);
        checked.insert(i + j, false);
        headings.insert(i + j, false);
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
  final TextEditingController headingController;
  final ListStyle listStyle;

  const _BulletColumn({
    required this.label,
    required this.set,
    required this.emit,
    required this.headingController,
    required this.listStyle,
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
        TextField(
          controller: widget.headingController,
          decoration: InputDecoration(
            labelText: l10n.d('Kop (optioneel)'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        SectionLabel(widget.label),
        const SizedBox(height: 6),
        for (int i = 0; i < set.controllers.length; i++) _buildRow(i),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => set.addAfter(
                (fn) => setState(fn),
                set.controllers.length - 1,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Bullet toevoegen')),
            ),
            TextButton.icon(
              onPressed: () => set.addAfter(
                (fn) => setState(fn),
                set.controllers.length - 1,
                heading: true,
              ),
              icon: const Icon(Icons.horizontal_split, size: 16),
              label: Text(l10n.d('Tussenkop toevoegen')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(int i) {
    final l10n = context.l10n;
    final heading = set.headings[i];
    final level = heading ? 0 : set.levels[i];
    return Padding(
      key: ValueKey(set.controllers[i]),
      padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            key: ValueKey('toggle-heading-${widget.label}-$i'),
            icon: Icon(
              Icons.horizontal_split,
              size: 18,
              color: heading ? AppTheme.accent : AppTheme.slate300,
            ),
            onPressed: () => set.toggleHeading((fn) => setState(fn), i),
            tooltip: heading
                ? l10n.d('Maak er weer een bullet van')
                : l10n.d('Maak een tussenkop'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          if (!heading) ...[
            if (widget.listStyle == ListStyle.checklist)
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  key: ValueKey('checklist-item-${widget.label}-$i'),
                  value: set.checked[i],
                  onChanged: (value) {
                    setState(() => set.checked[i] = value ?? false);
                    widget.emit();
                  },
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              Text(
                _markerForItem(i),
                style: TextStyle(fontSize: 16, color: AppTheme.slate500),
              ),
            const SizedBox(width: 8),
          ],
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
                if (event.logicalKey == LogicalKeyboardKey.tab && !heading) {
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
                style: heading
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null,
                decoration: InputDecoration(
                  hintText: heading
                      ? l10n.d('Tussenkop (leeg = alleen een scheidingslijn)')
                      : '${l10n.d('Bullet')} ${i + 1}',
                  isDense: true,
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('remove-bullet-${widget.label}-$i'),
            icon: Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: AppTheme.slate500,
            ),
            onPressed: () => set.removeAndFocus((fn) => setState(fn), i),
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
    if (widget.listStyle == ListStyle.bullets) {
      return _markerForLevel(set.levels[index]);
    }
    if (widget.listStyle == ListStyle.checklist) return '';
    final level = set.levels[index];
    var number = 0;
    for (var i = 0; i <= index; i++) {
      if (set.levels[i] == level) number++;
      if (set.levels[i] < level) number = 0;
    }
    return '$number.';
  }
}
