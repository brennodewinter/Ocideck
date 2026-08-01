import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../services/caption_service.dart';
import '../../services/description_service.dart';
import '../../models/asset_origin.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../services/image_usage.dart';
import '../../state/deck_provider.dart';
import '../../state/tabs_provider.dart';
import 'alt_text_field.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../models/markdown_validation.dart';
import '../../models/slide_quality.dart';
import '../../state/deck_quality_provider.dart';
import '../../state/editor_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/project_path.dart';
import '../asset_origin_badge.dart';
import '../dialogs/image_carousel_picker.dart';
import '../../theme/app_theme.dart';

/// Shared layout helpers for slide editors.

/// Accentueert het gemelde fragment door het te selecteren.
///
/// Waarom een selectie en geen eigen markering: dit is de accentuering die de
/// gebruiker al kent uit elk tekstveld, en het gevonden stuk is meteen te
/// kopiëren of over te typen. Bovendien scrollt het veld er vanzelf heen.
///
/// De grens-controle is geen formaliteit. Tussen de scan en dit moment kan de
/// tekst zijn veranderd — de auteur typt door terwijl het paneel openstaat — en
/// een bereik dat buiten de tekst valt gooit een `TextSelection` eruit. Dan
/// liever geen accentuering dan een crash.
void applyQualitySpanSelection(
  TextEditingController controller,
  SlideQualitySpan? span,
) {
  if (span == null || span.isEmpty) return;
  final length = controller.text.length;
  if (span.start >= length) return;
  controller.selection = TextSelection(
    baseOffset: span.start,
    extentOffset: span.end.clamp(span.start, length),
  );
}

/// Beheert de tekstcontrollers van een slide-editor: [newController] maakt er
/// één met beginwaarde en emit-listener, en dispose ruimt ze allemaal op —
/// de init/emit/dispose-boilerplate die elke editor per veld herhaalde.
mixin EditorTextControllers<T extends StatefulWidget> on State<T> {
  final List<TextEditingController> _editorControllers = [];

  TextEditingController newController(String text, VoidCallback onChanged) {
    final controller = TextEditingController(text: text)
      ..addListener(onChanged);
    _editorControllers.add(controller);
    return controller;
  }

  @override
  void dispose() {
    for (final controller in _editorControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

/// Gedeelde handlers voor editors met één achtergrondafbeelding (titel,
/// citaat): kiezen, plakken en wissen. Kiezen/plakken/wissen reset ook het
/// bijschrift, want dat hoort bij de vorige afbeelding.
mixin BgImageHandlers<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Slide get editorSlide;
  ValueChanged<Slide> get onSlideUpdate;
  String? get bgImageBasePath;

  Future<void> pasteBgImage() async {
    final path = await pasteImageWithFeedback(
      context,
      ref.read(imageServiceProvider),
      projectPath: bgImageBasePath,
    );
    if (path != null) {
      onSlideUpdate(
        editorSlide.copyWith(
          imagePath: path,
          imageCaption: '',
          imageAltText: '',
        ),
      );
    }
  }

  Future<void> pickBgImage() async {
    final path = await pickImageWithFeedback(
      context,
      ref.read(imageServiceProvider),
      projectPath: bgImageBasePath,
    );
    if (path != null) {
      onSlideUpdate(
        editorSlide.copyWith(
          imagePath: path,
          imageCaption: '',
          imageAltText: '',
        ),
      );
    }
  }

  void clearBgImage() {
    onSlideUpdate(
      editorSlide.copyWith(imagePath: '', imageCaption: '', imageAltText: ''),
    );
  }
}

class EditorField extends ConsumerStatefulWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  /// Matches [SlideQualityIssue.field] for one-shot focus after navigation.
  final String? qualityField;

  const EditorField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.maxLines = 1,
    this.qualityField,
  });

  @override
  ConsumerState<EditorField> createState() => _EditorFieldState();
}

class _EditorFieldState extends ConsumerState<EditorField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyQualityFocus());
  }

  @override
  void didUpdateWidget(EditorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyQualityFocus();
  }

  void _applyQualityFocus() {
    if (!mounted) return;
    final field = widget.qualityField;
    if (field == null) return;
    final editor = ref.read(editorProvider);
    if (editor.focusQualityField != field) return;
    _focusNode.requestFocus();
    applyQualitySpanSelection(widget.controller, editor.focusQualitySpan);
    Scrollable.ensureVisible(
      context,
      alignment: 0.25,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    ref.read(editorProvider.notifier).clearFocusQualityField();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(widget.label),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          maxLines: widget.maxLines,
          minLines: 1,
          decoration: InputDecoration(
            hintText: widget.hint.isEmpty ? '' : l10n.d(widget.hint),
          ),
        ),
      ],
    );
  }
}

class EditorFieldList extends StatelessWidget {
  final List<Widget> children;
  final bool nestedInScrollView;

  const EditorFieldList({
    super.key,
    required this.children,
    this.nestedInScrollView = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: nestedInScrollView,
      physics: nestedInScrollView
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (_, i) => children[i],
    );
  }
}

/// Root [ListView] for slide editors. When [nestedInScrollView] is true the
/// list sizes to its children so the editor panel can scroll as one page.
ListView editorScrollList({
  required bool nestedInScrollView,
  required List<Widget> children,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  return ListView(
    shrinkWrap: nestedInScrollView,
    physics: nestedInScrollView
        ? const NeverScrollableScrollPhysics()
        : const AlwaysScrollableScrollPhysics(),
    padding: padding,
    children: children,
  );
}

/// Zoom-bediening voor afbeeldingen in slides.
/// De afbeelding vult ALTIJD de slide; de zoom bepaalt welk deel zichtbaar is.
///   0 of 100 = normaal (cover, Marp-standaard)
///   150      = ingezoomd: ziet alleen het midden van de foto
///   300      = flink ingezoomd: ziet 1/3 van de foto
class ImageZoomControl extends StatelessWidget {
  final int value; // 0 = auto/normaal, anders minValue–maxValue
  final ValueChanged<int> onChanged;
  final int step;
  final int minValue;
  final int maxValue;

  const ImageZoomControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 10,
    this.minValue = 20,
    this.maxValue = 300,
  });

  // Effectieve sliderwaarde: 0 behandelen als 100
  int get _effective => value == 0 ? 100 : value.clamp(minValue, maxValue);

  String _label(BuildContext context) {
    final l10n = context.l10n;
    final v = _effective;
    if (maxValue <= 100) return '$v%'; // paneelbreedte-modus
    if (v == 100) return l10n.d('Volledig zichtbaar (100%)');
    if (v > 100) {
      return '${l10n.d('Ingezoomd')} $v% — ${((1 / (v / 100)) * 100).round()}% ${l10n.d('van de foto zichtbaar')}';
    }
    return '${l10n.d('Uitgezoomd')} $v%';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final zoomed = _effective != 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Tooltip(
              message: l10n.d('Uitzoomen (meer van de foto zichtbaar)'),
              child: Icon(Icons.zoom_out, size: 16, color: AppTheme.slate500),
            ),
            Expanded(
              child: Slider(
                value: _effective.toDouble(),
                min: minValue.toDouble(),
                max: maxValue.toDouble(),
                divisions: (maxValue - minValue) ~/ step,
                label: _label(context),
                onChanged: (v) {
                  final snapped = ((v.round() / step).round() * step).clamp(
                    minValue,
                    maxValue,
                  );
                  onChanged(snapped);
                },
              ),
            ),
            Tooltip(
              message: l10n.d('Inzoomen (minder van de foto zichtbaar)'),
              child: Icon(Icons.zoom_in, size: 16, color: AppTheme.slate500),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                '$_effective%',
                style: TextStyle(
                  fontSize: 12,
                  color: zoomed ? AppTheme.accentFg : AppTheme.slate500,
                  fontWeight: zoomed ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 4),
            // Zie de toelichting bij de beeldkiezerknoppen: de tooltip hoort op
            // de IconButton zelf, anders blijft de knop naamloos (WCAG 4.1.2).
            IconButton(
              tooltip: l10n.d('Terugzetten (volledige afbeelding zichtbaar)'),
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: zoomed ? () => onChanged(100) : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: AppTheme.slate500,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Text(
            _label(context),
            style: TextStyle(fontSize: 10, color: AppTheme.slate500),
          ),
        ),
      ],
    );
  }
}

/// Callback met pad én caption.
typedef ImagePickedCallback = void Function(String path, String caption);

/// Afbeeldingskiezer-balk met carousel-knop + optionele caption.
class ImagePickerBar extends ConsumerWidget {
  final String imagePath;
  final String imageCaption;
  final String? captionBasePath;
  final List<String> searchPaths;
  final ImagePickedCallback onPicked;
  final VoidCallback? onBrowse;
  final VoidCallback? onPaste;
  final VoidCallback? onClear;
  final ValueChanged<String>? onCaptionChanged;

  /// Per-usage WCAG alt-text (AI_ASSIST §6.1). When [onAltTextChanged] is set an
  /// alt-text field appears below the caption; null hides it (e.g. decorative
  /// background images that need no alt).
  final String imageAltText;
  final ValueChanged<String>? onAltTextChanged;

  /// Applies an **AI-drafted** alt-text (AI_ASSIST §6): distinct from
  /// [onAltTextChanged] so the editor can set the AI-provenance marker
  /// (`imageAltText` in `aiAssistedFields`) that blocks sealing until reviewed.
  /// Non-null enables the "suggest alt-text" button (still gated on the AI toggle
  /// being on).
  final ValueChanged<String>? onAltTextSuggested;

  /// Whether the current alt-text is an unreviewed AI draft (shows the badge +
  /// "reviewed" action), and the callback that marks it reviewed.
  final bool imageAltIsAiDraft;
  final VoidCallback? onAltTextAccepted;
  final String label;
  final String captionField;

  const ImagePickerBar({
    super.key,
    required this.imagePath,
    required this.searchPaths,
    required this.onPicked,
    this.imageCaption = '',
    this.captionBasePath,
    this.onBrowse,
    this.onPaste,
    this.onClear,
    this.onCaptionChanged,
    this.imageAltText = '',
    this.onAltTextChanged,
    this.onAltTextSuggested,
    this.imageAltIsAiDraft = false,
    this.onAltTextAccepted,
    this.label = 'Geen afbeelding gekozen',
    this.captionField = 'imageCaption',
  });

  Future<void> _openCarousel(
    BuildContext context,
    WidgetRef ref,
    CaptionService captions,
  ) async {
    final result = await ImageCarouselPicker.show(
      context,
      searchPaths: searchPaths,
      initialPath: imagePath.isNotEmpty ? _resolveImagePath(imagePath) : null,
      captionService: captions,
      descriptionService: ref.read(descriptionServiceProvider),
      usageOf: (absolutePath) => _imageUsages(ref, absolutePath),
      onReplaceUsages: (from, to) => _replaceImageUsages(ref, from, to),
      openDeckFiles: [
        for (final tab in ref.read(tabsProvider).tabs)
          ?tab.deckNotifier.currentState.filePath,
      ],
    );
    if (result == null) return;
    // De bibliotheek doorzoekt ook mappen buiten de presentatie; zo'n keuze
    // moet mee het deck in, anders stuurt de gebruiker straks een gat door.
    final adopted = await ref
        .read(imageServiceProvider)
        .importIntoDeck(result.path, projectPath: captionBasePath);
    onPicked(adopted, result.caption);
  }

  /// Wijs in alle open decks elke slideverwijzing naar [fromAbsolute] om naar
  /// [toAbsolute]. Gebruikt door de afbeeldingenbibliotheek wanneer een md5-
  /// duplicaat wordt opgeruimd, zodat slides het behouden bestand blijven tonen.
  Future<void> _replaceImageUsages(
    WidgetRef ref,
    String fromAbsolute,
    String toAbsolute,
  ) async {
    final target = p.normalize(fromAbsolute);
    for (final tab in ref.read(tabsProvider).tabs) {
      final notifier = tab.deckNotifier;
      final deck = notifier.currentState.deck;
      if (deck == null) continue;
      final projectPath = deck.projectPath ?? '';

      String? resolve(String candidate) => p.normalize(
        p.isAbsolute(candidate) ? candidate : p.join(projectPath, candidate),
      );
      // Blijf relatief opslaan als de slide dat al deed en het nieuwe pad
      // binnen het project ligt; anders absoluut.
      String replacement(String candidate) {
        if (p.isAbsolute(candidate) || projectPath.isEmpty) return toAbsolute;
        return p.isWithin(projectPath, toAbsolute)
            ? p.relative(toAbsolute, from: projectPath)
            : toAbsolute;
      }

      for (var i = 0; i < deck.slides.length; i++) {
        final slide = deck.slides[i];
        final updated = slideWithImageReplaced(
          slide,
          target,
          resolve,
          replacement,
        );
        if (!identical(updated, slide)) notifier.updateSlide(i, updated);
      }
    }
  }

  /// Find every open-deck slide that references [absolutePath], so we can warn
  /// before deleting an image that is still in use.
  List<String> _imageUsages(WidgetRef ref, String absolutePath) {
    final target = p.normalize(absolutePath);
    final usages = <String>[];
    for (final tab in ref.read(tabsProvider).tabs) {
      final deck = tab.deckNotifier.currentState.deck;
      if (deck == null) continue;
      String? resolve(String candidate) => p.normalize(
        p.isAbsolute(candidate)
            ? candidate
            : p.join(deck.projectPath ?? '', candidate),
      );

      for (final i in slideIndexesUsingImage(deck, target, resolve)) {
        usages.add('${tab.label} · slide ${i + 1}');
      }
    }
    return usages;
  }

  // Permissive: shows user-picked images from anywhere (e.g. before they're
  // copied into the project). Not for security-sensitive file reads — see
  // _resolveImagePathForClipboard.
  String _resolveImagePath(String path) {
    return resolveEditorAssetPath(path, captionBasePath) ?? path;
  }

  /// Strict containment for the copy-to-clipboard sink: a deck opened from disk
  /// must not be able to exfiltrate an arbitrary file (e.g. imagePath
  /// `/etc/passwd`, or a symlink inside the project pointing outside it) to the
  /// clipboard. Returns empty for out-of-project paths.
  String _resolveImagePathForClipboard(String path) {
    return resolveContainedRealPath(path, captionBasePath) ?? '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final captions = ref.read(captionServiceProvider);
    final pathText = Text(
      imagePath.isEmpty ? l10n.d(label) : imagePath,
      style: TextStyle(
        fontSize: 12,
        color: imagePath.isEmpty ? AppTheme.slate500 : AppTheme.slate700,
      ),
      overflow: TextOverflow.ellipsis,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pad-display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.slate300),
            borderRadius: BorderRadius.circular(6),
            color: AppTheme.paper,
          ),
          child: Row(
            children: [
              // Het pad is te selecteren, de placeholder niet: een bestandsnaam
              // uit een bevinding overtypen is precies het werk waar een
              // typefout in sluipt, en "geen afbeelding gekozen" valt niets aan
              // te kopiëren. SelectionArea en niet SelectableText, want die
              // laatste kent geen `overflow` — en het pad moet met een ellips
              // blijven afbreken in plaats van de knoppenrij weg te duwen.
              Expanded(
                child: imagePath.isEmpty
                    ? pathText
                    : SelectionArea(child: pathText),
              ),
              // Het ruwe pad hiernaast is alleen te duiden door wie paden
              // leest; de badge zegt wat het betekent voor de ontvanger.
              if (imagePath.isNotEmpty) ...[
                const SizedBox(width: 8),
                AssetOriginBadge(
                  origin: classifyAssetPath(imagePath, captionBasePath),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Knoppen
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => _openCarousel(context, ref, captions),
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: Text(l10n.d('Uit bibliotheek…')),
            ),
            if (onBrowse != null)
              OutlinedButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(l10n.d('Van computer…')),
              ),
            // `IconButton(tooltip:)` in plaats van een omhullende `Tooltip`:
            // die laatste hangt zijn semantiek aan een omliggende knoop, zodat
            // de knop zélf naamloos bij de schermlezer aankomt (WCAG 4.1.2).
            // De tooltip blijft visueel identiek.
            if (onPaste != null)
              IconButton(
                tooltip: l10n.d('Afbeelding plakken uit klembord'),
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste, size: 18),
                color: AppTheme.slate500,
              ),
            if (imagePath.isNotEmpty)
              IconButton(
                tooltip: l10n.d('Kopieer afbeelding naar klembord'),
                onPressed: () async {
                  final ok = await ImageService().copyImageToClipboard(
                    _resolveImagePathForClipboard(imagePath),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? l10n.d('Afbeelding gekopieerd naar klembord.')
                              : l10n.d('Kopiëren naar klembord mislukt.'),
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                color: AppTheme.slate500,
              ),
            if (onClear != null && imagePath.isNotEmpty)
              IconButton(
                tooltip: l10n.d('Verwijder afbeelding'),
                onPressed: onClear,
                icon: const Icon(Icons.clear, size: 18),
                color: AppTheme.slate500,
              ),
          ],
        ),
        // Caption-veld
        if (imagePath.isNotEmpty && onCaptionChanged != null) ...[
          const SizedBox(height: 8),
          _CaptionField(
            caption: imageCaption,
            imagePath: imagePath,
            captionBasePath: captionBasePath,
            captionService: captions,
            captionField: captionField,
            onChanged: onCaptionChanged!,
          ),
        ],
        // Alt-tekstveld (WCAG 1.1.1, AI_ASSIST §6.1)
        if (imagePath.isNotEmpty && onAltTextChanged != null) ...[
          const SizedBox(height: 8),
          AltTextField(
            key: ValueKey('alt:$imagePath'),
            altText: imageAltText,
            imagePath: imagePath,
            captionBasePath: captionBasePath,
            onChanged: onAltTextChanged!,
            onSuggested: onAltTextSuggested,
            isAiDraft: imageAltIsAiDraft,
            onAccepted: onAltTextAccepted,
          ),
        ],
      ],
    );
  }
}

/// Captionveld met auto-save naar sidecar.
class _CaptionField extends ConsumerStatefulWidget {
  final String caption;
  final String imagePath;
  final String? captionBasePath;
  final CaptionService captionService;
  final String captionField;
  final ValueChanged<String> onChanged;

  const _CaptionField({
    required this.caption,
    required this.imagePath,
    this.captionBasePath,
    required this.captionService,
    required this.captionField,
    required this.onChanged,
  });

  @override
  ConsumerState<_CaptionField> createState() => _CaptionFieldState();
}

class _CaptionFieldState extends ConsumerState<_CaptionField> {
  late final TextEditingController _ctrl;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.caption);
    _ctrl.addListener(_onChanged);
    _loadStoredCaption();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyQualityFocus());
  }

  @override
  void didUpdateWidget(_CaptionField old) {
    super.didUpdateWidget(old);
    if (old.imagePath != widget.imagePath) {
      _ctrl.removeListener(_onChanged);
      _ctrl.text = widget.caption;
      _ctrl.addListener(_onChanged);
      _loadStoredCaption();
    }
    _applyQualityFocus();
  }

  void _applyQualityFocus() {
    if (!mounted) return;
    final editor = ref.read(editorProvider);
    if (editor.focusQualityField != widget.captionField) return;
    _focusNode.requestFocus();
    applyQualitySpanSelection(_ctrl, editor.focusQualitySpan);
    Scrollable.ensureVisible(
      context,
      alignment: 0.25,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    ref.read(editorProvider.notifier).clearFocusQualityField();
  }

  void _onChanged() {
    widget.onChanged(_ctrl.text);
    widget.captionService.saveCaption(
      widget.imagePath,
      _ctrl.text,
      basePath: widget.captionBasePath,
    );
  }

  Future<void> _loadStoredCaption() async {
    if (widget.caption.isNotEmpty) return;
    final stored = await widget.captionService.getCaption(
      widget.imagePath,
      basePath: widget.captionBasePath,
    );
    if (!mounted || stored == null || stored == _ctrl.text) return;
    _ctrl.removeListener(_onChanged);
    _ctrl.text = stored;
    _ctrl.addListener(_onChanged);
    widget.onChanged(stored);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final slideIndex = ref.watch(editorProvider).selectedIndex;
    final severity = slideQualitySeverityForField(
      result: ref.watch(deckQualityProvider),
      slideIndex: slideIndex,
      field: widget.captionField,
    );
    final showHint = severity != null && widget.caption.trim().isEmpty;
    final isError = severity == MarkdownValidationSeverity.error;
    final isWarning = severity == MarkdownValidationSeverity.warning;
    final hintColor = isError
        ? AppTheme.amber700
        : isWarning
        ? AppTheme.amber700
        : AppTheme.slate500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: l10n.d(
              'Caption / bronvermelding (bijv. © Naam Fotograaf)',
            ),
            hintStyle: const TextStyle(fontSize: 12, color: AppTheme.blueGray2),
            prefixIcon: Icon(
              Icons.copyright_outlined,
              size: 16,
              color: showHint ? hintColor : AppTheme.slate500,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 10,
            ),
            filled: true,
            fillColor: showHint ? AppTheme.notesBg : AppTheme.slate50,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: showHint && (isError || isWarning)
                    ? AppTheme.amber500
                    : AppTheme.slate300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: showHint && (isError || isWarning)
                    ? AppTheme.amber600
                    : AppTheme.slate500,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppTheme.slate300),
            ),
          ),
          style: const TextStyle(fontSize: 12),
        ),
        if (showHint) ...[
          const SizedBox(height: 4),
          Text(
            isError || isWarning
                ? l10n.d(
                    'Voeg alt-tekst / bijschrift toe voor toegankelijkheid',
                  )
                : l10n.d(
                    'Tip: voeg alt-tekst / bijschrift toe voor toegankelijkheid',
                  ),
            style: TextStyle(
              fontSize: 10,
              color: isError || isWarning
                  ? AppTheme.amber700
                  : AppTheme.slate500,
            ),
          ),
        ],
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        l10n.d(text),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.slate500,
        ),
      ),
    );
  }
}

/// Kies een afbeelding via de bestandskiezer en meld een afwijzing (te groot,
/// geen ondersteund formaat, schrijffout) aan de gebruiker; annuleren blijft
/// stil. Geeft het geïmporteerde pad terug, of null.
Future<String?> pickImageWithFeedback(
  BuildContext context,
  ImageService service, {
  String? projectPath,
}) async {
  final outcome = await service.pickImageDetailed(projectPath: projectPath);
  if (context.mounted) reportImageImportFailure(context, outcome.failure);
  return outcome.path;
}

/// Plak een afbeelding van het klembord en meld waarom het niet lukte (geen
/// afbeelding op het klembord, te groot, schrijffout) i.p.v. stil niets doen.
Future<String?> pasteImageWithFeedback(
  BuildContext context,
  ImageService service, {
  String? projectPath,
}) async {
  final outcome = await service.pasteImageDetailed(projectPath: projectPath);
  if (context.mounted) reportImageImportFailure(context, outcome.failure);
  return outcome.path;
}

/// Toon een SnackBar voor een mislukte afbeeldingsimport. Annuleren (of
/// succes) toont niets.
void reportImageImportFailure(
  BuildContext context,
  ImageImportFailure? failure,
) {
  if (failure == null || failure == ImageImportFailure.cancelled) return;
  final l10n = context.l10n;
  final message = switch (failure) {
    ImageImportFailure.cancelled => '',
    ImageImportFailure.rejected => l10n.d(
      'Afbeelding geweigerd: te groot (max 64 MB) of geen ondersteund formaat.',
    ),
    ImageImportFailure.noClipboardImage => l10n.d(
      'Geen afbeelding op het klembord.',
    ),
    ImageImportFailure.writeFailed => l10n.d('Kon de afbeelding niet opslaan.'),
    ImageImportFailure.memoryBudgetExceeded => l10n.d(
      'Het webgeheugen voor afbeeldingen is vol (maximaal 256 MB). Sla je werk op als .ocideck en herlaad de pagina voordat je meer afbeeldingen toevoegt.',
    ),
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
