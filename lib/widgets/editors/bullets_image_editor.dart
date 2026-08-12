import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';
import '../slides/image_crop_dialog.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../markdown_editor/markdown_editor.dart';
import '_editor_field.dart';
import 'bullet_marker_selector.dart';
import 'list_style_selector.dart';
import 'split_continuation_switch.dart';
import '../../theme/app_theme.dart';

class BulletsImageEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final List<String> searchPaths;
  final String? captionBasePath;

  /// Whether the preceding slide renders a numbered list — only then is the
  /// "continue numbering" toggle offered (e.g. the second half of a split
  /// numbered bullets-with-image slide can carry on the count).
  final bool previousSlideIsNumbered;

  /// Of de vorige slide met deze een gesplitste reeks kan vormen — bepaalt of
  /// de voortzettingsschakelaar zin heeft.
  final bool canContinueSplit;

  final bool nestedInScrollView;

  const BulletsImageEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    this.searchPaths = const [],
    this.captionBasePath,
    this.previousSlideIsNumbered = false,
    this.canContinueSplit = false,
    this.nestedInScrollView = false,
  });

  @override
  State<BulletsImageEditor> createState() => _BulletsImageEditorState();
}

class _BulletsImageEditorState extends State<BulletsImageEditor> {
  late final TextEditingController _title;
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
    _listStyle = widget.slide.listStyle;
    _bulletMarkerOverride = widget.slide.bulletMarkerOverride;
    _showChecklistProgress = widget.slide.showChecklistProgress;
    _continueNumbering = widget.slide.continueNumbering;
    _continuesSplit = widget.slide.continuesSplit;
    _richText = TextEditingController(
      text: normalizeRichTextMarkdown(widget.slide.customMarkdown),
    );
    _richText.addListener(_emit);
    final list = widget.slide.bullets.isEmpty ? [''] : widget.slide.bullets;
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
        listStyle: _listStyle,
        bulletMarkerOverride: _bulletMarkerOverride,
        clearBulletMarkerOverride: _bulletMarkerOverride == null,
        showChecklistProgress: _showChecklistProgress,
        // Only a numbered list can continue a chain; keep it off otherwise so a
        // later switch to bullets/checklist doesn't leave a stale flag behind.
        continueNumbering:
            _listStyle == ListStyle.numbered && _continueNumbering,
        // Alleen een slide die daadwerkelijk op een gelijksoortige voorganger
        // volgt kan een voortzetting zijn; anders blijft er een stale vlag in
        // de markdown staan die de opmaak stilletjes stuurt.
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

  void _addBulletAfter(int i) => _insertItemAfter(
    i,
    level: _isHeading[i] ? 0 : _levels[i],
    heading: false,
  );

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

  /// Flips row [i] between an ordinary bullet and a group heading.
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

  Future<void> _pasteImage() async {
    final path = await pasteImageWithFeedback(
      context,
      widget.imageService,
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  Future<void> _pickImage() async {
    final path = await pickImageWithFeedback(
      context,
      widget.imageService,
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _richText.dispose();
    for (final c in _bullets) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Widget _imageBar(String imagePath) {
    return ImagePickerBar(
      imagePath: imagePath,
      imageCaption: widget.slide.imageCaption,
      searchPaths: widget.searchPaths,
      captionBasePath: widget.captionBasePath,
      onPicked: (path, caption) => widget.onUpdate(
        widget.slide.copyWith(imagePath: path, imageCaption: caption),
      ),
      onBrowse: _pickImage,
      onPaste: _pasteImage,
      onClear: imagePath.isNotEmpty
          ? () => widget.onUpdate(
              widget.slide.copyWith(imagePath: '', imageCaption: ''),
            )
          : null,
      onCaptionChanged: (caption) =>
          widget.onUpdate(widget.slide.copyWith(imageCaption: caption)),
      imageAltText: widget.slide.imageAltText,
      onAltTextChanged: (alt) => widget.onUpdate(
        widget.slide
            .copyWith(imageAltText: alt)
            .withAiAssistedField('imageAltText', present: false),
      ),
      onAltTextSuggested: (alt) => widget.onUpdate(
        widget.slide
            .copyWith(imageAltText: alt)
            .withAiAssistedField('imageAltText', present: true),
      ),
      imageAltIsAiDraft: widget.slide.aiAssistedFields.contains('imageAltText'),
      onAltTextAccepted: () => widget.onUpdate(
        widget.slide.withAiAssistedField('imageAltText', present: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final imagePath = widget.slide.imagePath;

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
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
        // splitting a numbered bullets-with-image slide, its second half can
        // carry on the count.
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
          const SectionLabel('Tekst (links)'),
          SizedBox(
            height: 320,
            child: MarkdownNotesEditor.legacy(
              controller: _richText,
              baseStyle: const TextStyle(fontSize: 14, height: 1.45),
              linkColor: AppTheme.accentFg,
              hintText: l10n.d('Tekst...'),
              expand: true,
              minLines: 8,
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          const SectionLabel('Bullets (links)'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _reorderItem,
            children: [
              for (int i = 0; i < _bullets.length; i++) _buildBulletRow(i),
            ],
          ),
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
        const SizedBox(height: 16),
        const SectionLabel('Afbeelding (rechts)'),
        _imageBar(imagePath),
        const SizedBox(height: 12),
        const SectionLabel('Breedte afbeeldingspaneel (rechts)'),
        ImageZoomControl(
          value: widget.slide.imageSize > 0 ? widget.slide.imageSize : 40,
          onChanged: (v) =>
              widget.onUpdate(widget.slide.copyWith(imageSize: v)),
          step: 5,
          minValue: 20,
          maxValue: 70,
        ),
        if (imageIsCroppable(imagePath)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.crop, size: 18),
              label: Text(l10n.d('Bijsnijden')),
              onPressed: _openCrop,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openCrop() async {
    // The image fills a fixed right-hand panel; crop adjusts both the zoom
    // (0=cover, 100=contain, >100=zoom in) and the focal point.
    final fraction =
        (widget.slide.imageSize > 0 ? widget.slide.imageSize / 100.0 : 0.40)
            .clamp(0.1, 0.70);
    final result = await showImageCropDialog(
      context,
      imagePath: widget.slide.imagePath,
      projectPath: widget.captionBasePath,
      frameAspect: fraction * 16 / 9,
      imageSize: widget.slide.imageZoom,
      focalX: widget.slide.imageFocalX,
      focalY: widget.slide.imageFocalY,
      enableZoom: true,
    );
    if (result == null) return;
    widget.onUpdate(
      widget.slide.copyWith(
        imageFocalX: result.focalX,
        imageFocalY: result.focalY,
        imageZoom: result.imageSize,
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
          IconButton(
            key: ValueKey('toggle-heading-$i'),
            icon: Icon(
              Icons.horizontal_split,
              size: 18,
              color: heading ? AppTheme.accentFg : AppTheme.slate300,
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
                if (event.logicalKey == LogicalKeyboardKey.enter) {
                  _addBulletAfter(i);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.backspace &&
                    _bullets[i].text.isEmpty &&
                    _bullets.length > 1) {
                  _removeBulletAndFocus(i);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.tab && !heading) {
                  if (HardwareKeyboard.instance.isShiftPressed) {
                    if (_levels[i] > 0) setState(() => _levels[i]--);
                  } else {
                    if (_levels[i] < _maxLevel) setState(() => _levels[i]++);
                  }
                  _emit();
                  return KeyEventResult.handled;
                }
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
            tooltip: l10n.d('Bullet verwijderen'),
            icon: Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: AppTheme.slate500,
            ),
            onPressed: () => _removeBulletAndFocus(i),
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
