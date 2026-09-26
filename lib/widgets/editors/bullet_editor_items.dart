import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import 'editor_text_controller.dart';

typedef BulletMutation = void Function(VoidCallback fn);

/// De gedeelde bewerkbare toestand van een opsomming in de slide-editors.
///
/// Controllers, niveaus en focusnodes moeten altijd tegelijk worden verplaatst
/// en verwijderd. Door die levenscyclus hier te bewaren kunnen de editors niet
/// ongemerkt uit de pas gaan lopen wanneer één ervan nieuw rijgedrag krijgt.
class BulletSet {
  static const maxLevel = kMaxIndentButtonLevel;

  final VoidCallback emit;
  late final List<EditorTextController> controllers;
  late final List<int> levels;
  late final List<bool> checked;
  late final List<bool> headings;
  late final List<FocusNode> focusNodes;

  BulletSet(List<String> raw, this.emit) {
    final items = raw.isEmpty ? [''] : raw;
    headings = items.map(isGroupHeading).toList();
    levels = items
        .map((item) => isGroupHeading(item) ? 0 : bulletLevel(item))
        .toList();
    checked = items
        .map(
          (item) => isGroupHeading(item) ? false : checklistItemChecked(item),
        )
        .toList();
    controllers = items
        .map(
          (item) => _makeController(
            isGroupHeading(item)
                ? groupHeadingText(item)
                : checklistItemText(item),
          ),
        )
        .toList();
    focusNodes = List.generate(controllers.length, (_) => FocusNode());
  }

  List<String> values(ListStyle listStyle) =>
      List.generate(controllers.length, (index) {
        if (headings[index]) {
          return groupHeadingBullet(controllers[index].text);
        }
        return listStyle == ListStyle.checklist
            ? checklistBullet(
                level: levels[index],
                text: controllers[index].text,
                checked: checked[index],
              )
            : '\t' * levels[index] + controllers[index].text;
      });

  EditorTextController _makeController(String text) {
    final controller = EditorTextController(text: text);
    controller.addTextListener(emit);
    return controller;
  }

  void reorder(BulletMutation mutate, int oldIndex, int newIndex) {
    mutate(() {
      controllers.insert(newIndex, controllers.removeAt(oldIndex));
      levels.insert(newIndex, levels.removeAt(oldIndex));
      checked.insert(newIndex, checked.removeAt(oldIndex));
      headings.insert(newIndex, headings.removeAt(oldIndex));
      focusNodes.insert(newIndex, focusNodes.removeAt(oldIndex));
    });
    emit();
  }

  void addAfter(BulletMutation mutate, int index, {bool heading = false}) {
    mutate(() {
      controllers.insert(index + 1, _makeController(''));
      levels.insert(index + 1, heading || headings[index] ? 0 : levels[index]);
      checked.insert(index + 1, false);
      headings.insert(index + 1, heading);
      focusNodes.insert(index + 1, FocusNode());
    });
    emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (index + 1 < focusNodes.length) {
        focusNodes[index + 1].requestFocus();
      }
    });
  }

  void toggleHeading(BulletMutation mutate, int index) {
    mutate(() {
      headings[index] = !headings[index];
      if (headings[index]) {
        levels[index] = 0;
        checked[index] = false;
      }
    });
    emit();
    focusNodes[index].requestFocus();
  }

  void removeAndFocus(BulletMutation mutate, int index) {
    if (controllers.length == 1) {
      mutate(() {
        controllers[index].removeTextListener(emit);
        controllers[index].clear();
        controllers[index].addTextListener(emit);
        levels[index] = 0;
        checked[index] = false;
        headings[index] = false;
      });
      emit();
      focusNodes[index].requestFocus();
      return;
    }

    final target = (index - 1).clamp(0, controllers.length - 2);
    mutate(() {
      controllers[index].removeTextListener(emit);
      controllers[index].dispose();
      controllers.removeAt(index);
      levels.removeAt(index);
      checked.removeAt(index);
      headings.removeAt(index);
      focusNodes[index].dispose();
      focusNodes.removeAt(index);
    });
    emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target < focusNodes.length) focusNodes[target].requestFocus();
    });
  }

  Future<void> paste(BulletMutation mutate, int index) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    final lines = data!.text!
        .split('\n')
        .map((line) => line.trim().replaceAll(RegExp(r'^[-*•◦▪▫]\s*'), ''))
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    if (lines.length == 1) {
      final controller = controllers[index];
      final selection = controller.selection;
      final start = selection.isValid
          ? selection.start
          : controller.text.length;
      final end = selection.isValid ? selection.end : controller.text.length;
      controller.value = TextEditingValue(
        text: controller.text.replaceRange(start, end, lines.first),
        selection: TextSelection.collapsed(offset: start + lines.first.length),
      );
      return;
    }

    mutate(() {
      controllers[index].removeTextListener(emit);
      controllers[index].dispose();
      controllers[index] = _makeController(lines.first);
      headings[index] = false;
      for (var offset = 1; offset < lines.length; offset++) {
        controllers.insert(index + offset, _makeController(lines[offset]));
        levels.insert(index + offset, levels[index]);
        checked.insert(index + offset, false);
        headings.insert(index + offset, false);
        focusNodes.insert(index + offset, FocusNode());
      }
    });
    emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final last = index + lines.length - 1;
      if (last < focusNodes.length) focusNodes[last].requestFocus();
    });
  }

  String markerForItem(int index, ListStyle listStyle) {
    if (listStyle == ListStyle.bullets) {
      const markers = ['•', '◦', '▪', '▫', '–'];
      return markers[levels[index].clamp(0, markers.length - 1)];
    }
    if (listStyle == ListStyle.checklist) return '';
    final level = levels[index];
    var number = 0;
    for (var preceding = 0; preceding <= index; preceding++) {
      if (levels[preceding] == level) number++;
      if (levels[preceding] < level) number = 0;
    }
    return '$number.';
  }

  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  }
}

class BulletEditorRow extends StatelessWidget {
  final BulletSet bullets;
  final int index;
  final ListStyle listStyle;
  final BulletMutation mutate;
  final String keyPrefix;
  final bool reorderable;
  final bool descriptiveRemoveTooltip;

  const BulletEditorRow({
    super.key,
    required this.bullets,
    required this.index,
    required this.listStyle,
    required this.mutate,
    this.keyPrefix = '',
    this.reorderable = false,
    this.descriptiveRemoveTooltip = false,
  });

  String _key(String action) =>
      keyPrefix.isEmpty ? '$action-$index' : '$action-$keyPrefix-$index';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final heading = bullets.headings[index];
    final level = heading ? 0 : bullets.levels[index];
    return Padding(
      key: ValueKey(bullets.controllers[index]),
      padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (reorderable) ...[
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_indicator,
                size: 16,
                color: AppTheme.slate300,
              ),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            key: ValueKey(_key('toggle-heading')),
            icon: Icon(
              Icons.horizontal_split,
              size: 18,
              color: heading ? AppTheme.accentFg : AppTheme.slate300,
            ),
            onPressed: () => bullets.toggleHeading(mutate, index),
            tooltip: heading
                ? l10n.d('Maak er weer een bullet van')
                : l10n.d('Maak een tussenkop'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          if (!heading) ...[
            if (listStyle == ListStyle.checklist)
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  key: ValueKey(_key('checklist-item')),
                  value: bullets.checked[index],
                  onChanged: (value) {
                    mutate(() => bullets.checked[index] = value ?? false);
                    bullets.emit();
                  },
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              Text(
                bullets.markerForItem(index, listStyle),
                style: TextStyle(fontSize: 16, color: AppTheme.slate500),
              ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) => _handleKey(event, heading),
              child: TextField(
                controller: bullets.controllers[index],
                focusNode: bullets.focusNodes[index],
                style: heading
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null,
                decoration: InputDecoration(
                  hintText: heading
                      ? l10n.d('Tussenkop (leeg = alleen een scheidingslijn)')
                      : '${l10n.d('Bullet')} ${index + 1}',
                  isDense: true,
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey(_key('remove-bullet')),
            icon: Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: AppTheme.slate500,
            ),
            onPressed: () => bullets.removeAndFocus(mutate, index),
            tooltip: descriptiveRemoveTooltip
                ? l10n.d('Bullet verwijderen')
                : l10n.d('Verwijder'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKey(KeyEvent event, bool heading) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      bullets.addAfter(mutate, index);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        bullets.controllers[index].text.isEmpty &&
        bullets.controllers.length > 1) {
      bullets.removeAndFocus(mutate, index);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab && !heading) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (bullets.levels[index] > 0) {
          mutate(() => bullets.levels[index]--);
        }
      } else if (bullets.levels[index] < BulletSet.maxLevel) {
        mutate(() => bullets.levels[index]++);
      }
      bullets.emit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      bullets.paste(mutate, index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
