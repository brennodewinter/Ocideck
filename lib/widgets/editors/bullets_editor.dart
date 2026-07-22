import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/slide_quality.dart';
import '../../services/rich_text_chapters.dart';
import '../../state/editor_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../markdown_editor/markdown_editor.dart';
import '_editor_field.dart';
import 'bullet_marker_selector.dart';
import 'list_style_selector.dart';
import 'split_continuation_switch.dart';
import '../../theme/app_theme.dart';

class BulletsEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  /// Knipt de vrije tekst op zijn `#`-koppen in losse dia's. Null wanneer er
  /// niets te knippen valt; de editor biedt het dan niet aan.
  final VoidCallback? onSplitChapters;

  /// Whether the preceding slide renders a numbered list — only then is the
  /// "continue numbering from the previous slide" option offered.
  final bool previousSlideIsNumbered;

  /// Of de vorige slide met deze een gesplitste reeks kan vormen — bepaalt of
  /// de voortzettingsschakelaar zin heeft.
  final bool canContinueSplit;

  final bool nestedInScrollView;

  const BulletsEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.onSplitChapters,
    this.previousSlideIsNumbered = false,
    this.canContinueSplit = false,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<BulletsEditor> createState() => _BulletsEditorState();
}

class _BulletsEditorState extends ConsumerState<BulletsEditor> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late List<TextEditingController> _bullets;
  late List<int> _levels;
  late List<bool> _checked;
  late List<bool> _isHeading;
  late List<FocusNode> _focusNodes;
  late ListStyle _listStyle;
  BulletMarker? _bulletMarkerOverride;
  late bool _showChecklistProgress;
  late bool _continueNumbering;
  late bool _continuesSplit;
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
    _continueNumbering = widget.slide.continueNumbering;
    _continuesSplit = widget.slide.continuesSplit;
    _richText = TextEditingController(
      text: normalizeRichTextMarkdown(widget.slide.customMarkdown),
    );
    _richText.addListener(_emit);
    _initBullets(widget.slide.bullets);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyQualityFocus());
  }

  /// Springt naar het gemelde opsommingsitem en accentueert het fragment.
  ///
  /// Opsommingen zijn waar de meeste tekst staat, en dus waar de meeste
  /// privacybevindingen landen. Zonder dit wees een melding wel naar de slide,
  /// maar moest de auteur zelf de goede regel zoeken.
  void _applyQualityFocus() {
    if (!mounted) return;
    final editor = ref.read(editorProvider);
    if (editor.focusQualityField != 'bullets') return;
    final index = editor.focusQualitySpan?.fragmentIndex ?? 0;
    if (index < 0 || index >= _bullets.length) return;
    _focusNodes[index].requestFocus();
    applyQualitySpanSelection(
      _bullets[index],
      _spanInController(index, editor.focusQualitySpan),
    );
    ref.read(editorProvider.notifier).clearFocusQualityField();
  }

  /// Rekent een positie in de ruwe bullet om naar een positie in het tekstveld.
  ///
  /// De scanner leest `slide.bullets[i]` zoals het in de markdown staat — met
  /// tabs voor het niveau en `- [ ] ` voor een checklist-item. Het tekstveld
  /// toont die opmaak niet; het bevat alleen de kale tekst. Een positie uit de
  /// scan één op één toepassen zou dus het verkeerde stuk accentueren, precies
  /// zo veel te ver naar rechts als de opmaak lang is.
  ///
  /// Alles wat gestript wordt is een prefix, dus het verschil in lengte ís de
  /// verschuiving — en `endsWith` controleert die aanname in plaats van haar aan
  /// te nemen. Klopt ze niet, dan liever geen accentuering dan een verkeerde.
  SlideQualitySpan? _spanInController(int index, SlideQualitySpan? span) {
    if (span == null || index >= widget.slide.bullets.length) return null;
    final raw = widget.slide.bullets[index];
    final stripped = _bullets[index].text;
    if (!raw.endsWith(stripped)) return null;
    final shift = raw.length - stripped.length;
    if (span.start - shift < 0) return null;
    return SlideQualitySpan(
      start: span.start - shift,
      end: span.end - shift,
      fragmentIndex: index,
    );
  }

  void _initBullets(List<String> raw) {
    final list = raw.isEmpty ? [''] : raw;
    _isHeading = list.map(isGroupHeading).toList();
    _levels = list.map((b) => isGroupHeading(b) ? 0 : _levelOf(b)).toList();
    _checked = list
        .map((b) => isGroupHeading(b) ? false : checklistItemChecked(b))
        .toList();
    _bullets = list
        .map(
          (b) => _makeCtrl(
            isGroupHeading(b) ? groupHeadingText(b) : checklistItemText(b),
          ),
        )
        .toList();
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
        // Only a numbered list can continue a chain; keep it off otherwise so a
        // later style switch doesn't leave a stale flag in the markdown.
        continueNumbering:
            _listStyle == ListStyle.numbered && _continueNumbering,
        // Alleen een slide die daadwerkelijk op een gelijksoortige voorganger
        // volgt kan een voortzetting zijn; anders zou een stale vlag in de
        // markdown blijven staan die de opmaak stilletjes stuurt.
        continuesSplit: widget.canContinueSplit && _continuesSplit,
        customMarkdown: _listStyle == ListStyle.richText
            ? normalizeRichTextMarkdown(_richText.text)
            : widget.slide.customMarkdown,
        bullets: _listStyle == ListStyle.richText
            ? widget.slide.bullets
            : List.generate(_bullets.length, (i) {
                if (_isHeading[i]) return groupHeadingBullet(_bullets[i].text);
                return _listStyle == ListStyle.checklist
                    ? checklistBullet(
                        level: _levels[i],
                        text: _bullets[i].text,
                        checked: _checked[i],
                      )
                    : '\t' * _levels[i] + _bullets[i].text;
              }),
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
      final heading = _isHeading.removeAt(oldIndex);
      final focus = _focusNodes.removeAt(oldIndex);
      _bullets.insert(newIndex, ctrl);
      _levels.insert(newIndex, level);
      _checked.insert(newIndex, checked);
      _isHeading.insert(newIndex, heading);
      _focusNodes.insert(newIndex, focus);
    });
    _emit();
  }

  void _addBulletAfter(int i) {
    // A new item inherits the row's indent, but never its heading-ness — Enter
    // after a heading starts an ordinary bullet in the group it introduces.
    final newLevel = _isHeading[i] ? 0 : _levels[i];
    _insertItemAfter(i, level: newLevel, heading: false);
  }

  /// Inserts a wordless group heading below row [i] and focuses it.
  void _addHeadingAfter(int i) => _insertItemAfter(i, level: 0, heading: true);

  void _insertItemAfter(int i, {required int level, required bool heading}) {
    setState(() {
      _bullets.insert(i + 1, _makeCtrl(''));
      _levels.insert(i + 1, level);
      _checked.insert(i + 1, false);
      _isHeading.insert(i + 1, heading);
      _focusNodes.insert(i + 1, FocusNode());
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (i + 1 < _focusNodes.length) _focusNodes[i + 1].requestFocus();
    });
  }

  /// Flips row [i] between an ordinary bullet and a group heading. A heading is
  /// always level 0 and unchecked.
  void _toggleHeading(int i) {
    setState(() {
      _isHeading[i] = !_isHeading[i];
      if (_isHeading[i]) {
        _levels[i] = 0;
        _checked[i] = false;
      }
    });
    _emit();
    _focusNodes[i].requestFocus();
  }

  void _removeBulletAndFocus(int i) {
    if (_bullets.length == 1) {
      setState(() {
        _bullets[i].removeListener(_emit);
        _bullets[i].clear();
        _bullets[i].addListener(_emit);
        _levels[i] = 0;
        _checked[i] = false;
        _isHeading[i] = false;
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
      _isHeading.removeAt(i);
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
      _isHeading[i] = false;
      for (int j = 1; j < lines.length; j++) {
        _bullets.insert(i + j, _makeCtrl(lines[j]));
        _levels.insert(i + j, _levels[i]);
        _checked.insert(i + j, false);
        _isHeading.insert(i + j, false);
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
    // Klikken op een melding van de slide die al openstaat verandert alleen de
    // editorstate — er komt geen nieuwe initState of didUpdateWidget langs.
    // Zonder deze listener zou het springen alleen werken naar een ándere slide.
    ref.listen(editorProvider.select((s) => s.focusQualityField), (_, next) {
      if (next != 'bullets') return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyQualityFocus());
    });
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel',
          controller: _title,
          hint: 'Slide titel',
          qualityField: 'title',
        ),
        const SizedBox(height: 12),
        EditorField(
          label: l10n.d('Subkop (optioneel)'),
          controller: _subtitle,
          hint: l10n.d('Subkop'),
          qualityField: 'subtitle',
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
        // Offered only when the previous slide is a numbered list — e.g. after
        // splitting a numbered slide, its second half can carry on the count.
        if (_listStyle == ListStyle.numbered && widget.previousSlideIsNumbered)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.d('Doornummeren vanaf vorige slide')),
            subtitle: Text(
              l10n.d('Begin de nummering waar de vorige slide ophield.'),
            ),
            value: _continueNumbering,
            onChanged: (value) {
              setState(() => _continueNumbering = value);
              _emit();
            },
          ),
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
          if (widget.onSplitChapters != null) _chapterSplitHint(l10n),
          SizedBox(
            height: 320,
            child: MarkdownNotesEditor.legacy(
              controller: _richText,
              baseStyle: const TextStyle(fontSize: 14, height: 1.45),
              linkColor: AppTheme.accent,
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
            child: Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _addBulletAfter(_bullets.length - 1),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.d('Bullet toevoegen')),
                ),
                TextButton.icon(
                  onPressed: () => _addHeadingAfter(_bullets.length - 1),
                  icon: const Icon(Icons.horizontal_split, size: 16),
                  label: Text(l10n.d('Tussenkop toevoegen')),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Het aanbod om de tekst op zijn `#`-koppen in losse dia's te knippen.
  ///
  /// Aangeboden en niet automatisch: knippen tijdens het typen zou de dia onder
  /// je handen uiteen laten vallen op het moment dat je `# ` intikt. Het aanbod
  /// staat bóven het tekstvak, want daar kijk je na het plakken van een document
  /// als eerste — en het verdwijnt vanzelf zodra er niets meer te knippen valt.
  Widget _chapterSplitHint(AppLocalizations l10n) {
    final chapters = richTextChapterCount(widget.slide);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.splitscreen, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l10n.d('Deze tekst bevat hoofdstukken. Opknippen levert')}'
              ' $chapters ${l10n.d('dia\'s op.')}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onSplitChapters,
            child: Text(l10n.d('Splits op hoofdstukken')),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletRow(int i) {
    final l10n = context.l10n;
    final heading = _isHeading[i];
    final level = heading ? 0 : _levels[i];
    return Padding(
      key: ValueKey(_bullets[i]),
      padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            index: i,
            child: Icon(
              Icons.drag_indicator,
              size: 16,
              color: AppTheme.slate300,
            ),
          ),
          const SizedBox(width: 4),
          // Toggle a row between an ordinary bullet and a group heading.
          IconButton(
            key: ValueKey('toggle-heading-$i'),
            icon: Icon(
              Icons.horizontal_split,
              size: 18,
              color: heading ? AppTheme.accent : AppTheme.slate300,
            ),
            onPressed: () => _toggleHeading(i),
            tooltip: heading
                ? l10n.d('Maak er weer een bullet van')
                : l10n.d('Maak een tussenkop'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 28),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          if (!heading) ...[
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
                style: TextStyle(fontSize: 16, color: AppTheme.slate500),
              ),
            const SizedBox(width: 8),
          ],
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
                // Tab → inspringing (niet op een tussenkop; die staat vast op
                // niveau 0)
                if (event.logicalKey == LogicalKeyboardKey.tab && !heading) {
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
            key: ValueKey('remove-bullet-$i'),
            icon: Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: AppTheme.slate500,
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
