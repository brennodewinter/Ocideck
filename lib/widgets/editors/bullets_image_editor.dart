import 'package:material_ui/material_ui.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';
import '../slides/image_crop_dialog.dart';
import '../../utils/markdown_paste_cleanup.dart';
import '../markdown_editor/markdown_editor.dart';
import '_editor_field.dart';
import 'ai_condense_button.dart';
import 'bullet_editor_items.dart';
import 'bullet_marker_selector.dart';
import 'list_style_selector.dart';
import 'split_continuation_switch.dart';
import '../../theme/app_theme.dart';
import 'editor_text_controller.dart';
import 'callout_editor.dart';

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
  late final EditorTextController _title;
  late final BulletSet _bullets;
  late ListStyle _listStyle;
  BulletMarker? _bulletMarkerOverride;
  late bool _showChecklistProgress;
  late bool _continueNumbering;
  late bool _continuesSplit;
  late final EditorTextController _richText;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title);
    _title.addTextListener(_emit);
    _listStyle = widget.slide.listStyle;
    _bulletMarkerOverride = widget.slide.bulletMarkerOverride;
    _showChecklistProgress = widget.slide.showChecklistProgress;
    _continueNumbering = widget.slide.continueNumbering;
    _continuesSplit = widget.slide.continuesSplit;
    _richText = EditorTextController(
      text: normalizeRichTextMarkdown(widget.slide.customMarkdown),
    );
    _richText.addTextListener(_emit);
    _bullets = BulletSet(widget.slide.bullets, _emit);
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
            : _bullets.values(_listStyle),
      ),
    );
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
    _bullets.dispose();
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
          AiCondenseButton(slide: widget.slide),
          _richTextField(),
        ] else ...[
          const SizedBox(height: 16),
          const SectionLabel('Bullets (links)'),
          _bulletEditor(l10n),
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
        const SizedBox(height: 8),
        // imageZoom 0 = cover (vullen), 100 = contain (passen). Sneltoets
        // naast de bijsnijddialoog, net als bij image-slide (#1879).
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(l10n.d('Afbeelding paneelvullend')),
          subtitle: Text(l10n.d('Vult het paneel en snijdt de randen bij')),
          value: widget.slide.imageZoom == 0,
          onChanged: imagePath.isEmpty
              ? null
              : (checked) => widget.onUpdate(
                  widget.slide.copyWith(imageZoom: checked == true ? 0 : 100),
                ),
        ),
        if (imageIsCroppable(imagePath)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.crop, size: 18),
              label: Text(l10n.d('Afbeelding aanpassen')),
              onPressed: _openCrop,
            ),
          ),
        ],
        if (imagePath.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.place, size: 18),
              label: Text(l10n.d('Afbeeldingsverwijzingen')),
              onPressed: _openCalloutEditor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bulletEditor(AppLocalizations l10n) => Column(
    children: [
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (oldIndex, newIndex) => _bullets.reorder(
          (mutation) => setState(mutation),
          oldIndex,
          newIndex,
        ),
        children: [
          for (var index = 0; index < _bullets.controllers.length; index++)
            BulletEditorRow(
              key: ValueKey(_bullets.controllers[index]),
              bullets: _bullets,
              index: index,
              listStyle: _listStyle,
              mutate: (mutation) => setState(mutation),
              reorderable: true,
              descriptiveRemoveTooltip: true,
            ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => _bullets.addAfter(
                (mutation) => setState(mutation),
                _bullets.controllers.length - 1,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Bullet toevoegen')),
            ),
            TextButton.icon(
              onPressed: () => _bullets.addAfter(
                (mutation) => setState(mutation),
                _bullets.controllers.length - 1,
                heading: true,
              ),
              icon: const Icon(Icons.horizontal_split, size: 16),
              label: Text(l10n.d('Tussenkop toevoegen')),
            ),
          ],
        ),
      ),
    ],
  );

  /// Het vrije-tekstveld (listStyle richText). Aparte methode om `build`
  /// binnen de lengtegrens te houden.
  Widget _richTextField() {
    final l10n = context.l10n;
    return SizedBox(
      height: 320,
      child: MarkdownNotesEditor.legacy(
        controller: _richText,
        baseStyle: const TextStyle(fontSize: 14, height: 1.45),
        linkColor: AppTheme.accentFg,
        hintText: l10n.d('Tekst...'),
        expand: true,
        minLines: 8,
      ),
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
      callouts: widget.slide.callouts,
    );
    if (result == null) return;
    widget.onUpdate(
      widget.slide.copyWith(
        imageFocalX: result.focalX,
        imageFocalY: result.focalY,
        imageZoom: result.imageSize,
        // Draaien schrijft een afgeleide kopie en laat het origineel staan
        // (IMAGE_ROTATION.md, optie A). Let op: de callout-targets van deze dia
        // staan in beeldruimte van de oude oriëntatie en draaien niet mee — zie
        // de waarschuwing in de dialoog en §9 van het ontwerp.
        imagePath: result.rotatedImagePath,
      ),
    );
  }

  Future<void> _openCalloutEditor() async {
    await showDialog<void>(
      context: context,
      builder: (context) => CalloutEditorDialog(
        slide: widget.slide,
        projectPath: widget.captionBasePath,
        onUpdate: (updated) => widget.onUpdate(updated),
      ),
    );
  }
}
