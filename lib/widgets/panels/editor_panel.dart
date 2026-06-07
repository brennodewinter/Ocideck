import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../editors/bullets_editor.dart';
import '../editors/bullets_image_editor.dart';
import '../editors/audio_attachment_editor.dart';
import '../editors/chart_editor.dart';
import '../editors/code_editor.dart';
import '../editors/free_markdown_editor.dart';
import '../editors/image_slide_editor.dart';
import '../editors/quote_editor.dart';
import '../editors/section_editor.dart';
import '../editors/table_editor.dart';
import '../editors/title_editor.dart';
import '../editors/two_bullets_editor.dart';
import '../editors/two_images_editor.dart';
import '../editors/video_slide_editor.dart';

class EditorPanel extends ConsumerWidget {
  const EditorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deckState = ref.watch(deckProvider);
    final editor = ref.watch(editorProvider);

    final deck = deckState.deck!;
    final idx = editor.selectedIndex.clamp(0, deck.slides.length - 1);
    final slide = deck.slides[idx];

    final deckNotifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);
    final imgService = ref.read(imageServiceProvider);

    void update(Slide updated) => deckNotifier.updateSlide(idx, updated);

    final settings = ref.watch(settingsProvider);

    // Zoekpaden voor de afbeeldingencarousel
    final searchPaths = [
      if (deck.projectPath != null) '${deck.projectPath}/images',
      if (deck.projectPath != null) deck.projectPath!,
      if (settings.homeDirectory != null) settings.homeDirectory!,
    ];

    if (editor.mode == EditorMode.markdown) {
      return _MarkdownModeEditor(
        // Verse instantie na undo/redo zodat de markdown opnieuw wordt geladen.
        key: ValueKey('md-${deckState.revision}'),
        initialContent: deckNotifier.generateMarkdown(),
        onApply: (md) {
          final ok = deckNotifier.applyMarkdown(md);
          editorNotifier.setParseError(!ok);
          return ok;
        },
        parseError: editor.parseError,
        onExitMarkdown: () => editorNotifier.setMode(EditorMode.visual),
      );
    }

    // De tekstvelden cachen hun inhoud in eigen controllers en verversen alleen
    // op slide-id. Bij undo/redo verandert [revision], waardoor deze subtree
    // remount en de velden de teruggedraaide inhoud tonen.
    return KeyedSubtree(
      key: ValueKey('editor-rev-${deckState.revision}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Toolbar: slide-type + stijlprofiel ─────────────────────────────
          _EditorToolbar(
            slide: slide,
            profiles: settings.themeProfiles,
            activeProfile: deck.themeProfile,
            defaultProfile: settings.themeProfile,
            onTypeChanged: (newType) {
              if (newType == slide.type) return;
              update(_convertSlideType(slide, newType));
            },
            onProfileChanged: (profile) =>
                deckNotifier.updateThemeProfile(profile),
            onDefaultProfileRequested: () =>
                deckNotifier.updateThemeProfile(settings.themeProfile),
          ),
          const Divider(height: 1),

          // ── Slide editor body ────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _buildEditor(
                    slide,
                    update,
                    imgService,
                    searchPaths,
                    deck.projectPath,
                  ),
                ),
                if (slide.type != SlideType.video) ...[
                  const Divider(height: 1),
                  Container(
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.all(12),
                    child: AudioAttachmentEditor(
                      slide: slide,
                      imageService: imgService,
                      onUpdate: update,
                    ),
                  ),
                ],
                if (deck.themeProfile.logoPath?.isNotEmpty == true) ...[
                  const Divider(height: 1),
                  _SlideLogoControl(slide: slide, onUpdate: update),
                ],
                if (deck.themeProfile.footerText.trim().isNotEmpty ||
                    deck.themeProfile.footerShowPageNumbers) ...[
                  const Divider(height: 1),
                  _SlideFooterControl(slide: slide, onUpdate: update),
                ],
                const Divider(height: 1),
                _SlideTimingControl(slide: slide, onUpdate: update),
                const Divider(height: 1),
                _SlideTlpControl(slide: slide, onUpdate: update),
                const Divider(height: 1),
                _NotesField(slide: slide, onUpdate: update),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Re-type a slide while carrying over text fields where they make sense.
  static Slide _convertSlideType(Slide slide, SlideType newType) {
    final keepsBullets =
        newType == SlideType.bullets ||
        newType == SlideType.twoBullets ||
        newType == SlideType.bulletsImage;
    final keepsImage =
        newType == SlideType.bulletsImage ||
        newType == SlideType.image ||
        newType == SlideType.twoImages;
    return Slide(
      id: slide.id,
      type: newType,
      title: slide.title,
      subtitle: slide.subtitle,
      bullets: keepsBullets
          ? (slide.bullets.isNotEmpty ? slide.bullets : [''])
          : const [],
      bullets2: newType == SlideType.twoBullets
          ? (slide.bullets2.isNotEmpty ? slide.bullets2 : [''])
          : const [],
      imagePath: keepsImage ? slide.imagePath : '',
      imagePath2: newType == SlideType.twoImages ? slide.imagePath2 : '',
      imageCaption: keepsImage ? slide.imageCaption : '',
      imageCaption2: newType == SlideType.twoImages ? slide.imageCaption2 : '',
      videoPath: newType == SlideType.video ? slide.videoPath : '',
      videoAutoplay: slide.videoAutoplay,
      audioPath: slide.audioPath,
      audioAutoplay: slide.audioAutoplay,
      quote: slide.quote,
      quoteAuthor: slide.quoteAuthor,
      customMarkdown: slide.customMarkdown,
      codeLanguage: slide.codeLanguage,
      cssClass: slide.cssClass,
      notes: slide.notes,
      advanceDuration: slide.advanceDuration,
      imageSize: slide.imageSize,
      showLogo: slide.showLogo,
      showFooter: slide.showFooter,
      tlp: slide.tlp,
      tableRows: newType == SlideType.table
          ? (slide.tableRows.isNotEmpty
                ? slide.tableRows
                : const [
                    // Lege koppen; de editor toont 'Kolom 1' etc. als hint.
                    ['', ''],
                    ['', ''],
                  ])
          : const [],
    );
  }

  Widget _buildEditor(
    Slide slide,
    ValueChanged<Slide> onUpdate,
    ImageService imgService,
    List<String> searchPaths,
    String? captionBasePath,
  ) {
    switch (slide.type) {
      case SlideType.title:
        return TitleEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
        );
      case SlideType.section:
        return SectionEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
        );
      case SlideType.bullets:
        return BulletsEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
        );
      case SlideType.twoBullets:
        return TwoBulletsEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
        );
      case SlideType.bulletsImage:
        return BulletsImageEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          imageService: imgService,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
        );
      case SlideType.twoImages:
        return TwoImagesEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
        );
      case SlideType.image:
        return ImageSlideEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          imageService: imgService,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
        );
      case SlideType.video:
        return VideoSlideEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          imageService: imgService,
        );
      case SlideType.quote:
        return QuoteEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
        );
      case SlideType.table:
        return TableEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
        );
      case SlideType.freeMarkdown:
        return FreeMarkdownEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
        );
      case SlideType.code:
        return CodeEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
        );
      case SlideType.chart:
        return ChartEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          projectPath: captionBasePath,
        );
    }
  }
}

// ── Editor toolbar: slide-type + stijlprofiel dropdowns ──────────────────────

IconData _slideTypeIcon(SlideType type) {
  switch (type) {
    case SlideType.title:
      return Icons.title;
    case SlideType.section:
      return Icons.bookmark_outline;
    case SlideType.bullets:
      return Icons.format_list_bulleted;
    case SlideType.twoBullets:
      return Icons.view_column_outlined;
    case SlideType.bulletsImage:
      return Icons.view_agenda_outlined;
    case SlideType.twoImages:
      return Icons.auto_stories_outlined;
    case SlideType.image:
      return Icons.image_outlined;
    case SlideType.video:
      return Icons.movie_outlined;
    case SlideType.quote:
      return Icons.format_quote_outlined;
    case SlideType.table:
      return Icons.table_chart_outlined;
    case SlideType.freeMarkdown:
      return Icons.code;
    case SlideType.code:
      return Icons.terminal;
    case SlideType.chart:
      return Icons.bar_chart;
  }
}

class _EditorToolbar extends StatelessWidget {
  final Slide slide;
  final List<ThemeProfile> profiles;
  final ThemeProfile activeProfile;
  final ThemeProfile defaultProfile;
  final ValueChanged<SlideType> onTypeChanged;
  final ValueChanged<ThemeProfile> onProfileChanged;
  final VoidCallback onDefaultProfileRequested;

  const _EditorToolbar({
    required this.slide,
    required this.profiles,
    required this.activeProfile,
    required this.defaultProfile,
    required this.onTypeChanged,
    required this.onProfileChanged,
    required this.onDefaultProfileRequested,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Make sure the active profile is always selectable, even when it was
    // loaded from a file and is not part of the saved profile list.
    final profileItems = <ThemeProfile>[
      ...profiles,
      if (!profiles.any((p) => p.name == activeProfile.name)) activeProfile,
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: _ToolbarField(
              label: 'TYPE',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SlideType>(
                  value: slide.type,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(6),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (final type in SlideType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _slideTypeIcon(type),
                              size: 14,
                              color: AppTheme.navy,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                l10n.d(type.label),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onTypeChanged(v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ToolbarField(
              label: 'STIJL',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: activeProfile.name,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(6),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.teal,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (final profile in profileItems)
                      DropdownMenuItem(
                        value: profile.name,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.palette_outlined,
                              size: 14,
                              color: AppTheme.teal,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                profile.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (name) {
                    if (name == null) return;
                    final profile = profileItems.firstWhere(
                      (p) => p.name == name,
                      orElse: () => activeProfile,
                    );
                    onProfileChanged(profile);
                  },
                ),
              ),
            ),
          ),
          // Alleen tonen wanneer de stijl afwijkt van de standaard — anders
          // voegt het niets toe. Eén klik zet 'm terug op het standaardprofiel.
          if (activeProfile.name != defaultProfile.name) ...[
            const SizedBox(width: 2),
            Tooltip(
              message:
                  '${context.l10n.d('Terug naar standaardstijl')} ${defaultProfile.name}',
              child: IconButton(
                onPressed: onDefaultProfileRequested,
                icon: const Icon(Icons.restart_alt, size: 16),
                color: AppTheme.teal,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolbarField extends StatelessWidget {
  final String label;
  final Widget child;

  const _ToolbarField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Text(
          l10n.d(label),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ── Timing instelling ─────────────────────────────────────────────────────────

class _SlideTimingControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideTimingControl({required this.slide, required this.onUpdate});

  void _setDuration(double value) {
    final clamped = (value * 10).round() / 10; // snap to 0.1s
    onUpdate(slide.copyWith(advanceDuration: clamped < 0 ? 0 : clamped));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = slide.advanceDuration > 0;
    final duration = slide.advanceDuration;

    return Container(
      color: const Color(0xFFF0F9FF),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF0369A1)),
          const SizedBox(width: 8),
          Checkbox(
            value: enabled,
            onChanged: (v) => _setDuration(v == true ? 3.0 : 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.d('Automatisch doorgaan na'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1)),
          ),
          const SizedBox(width: 8),
          // Minus knop
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.remove, size: 14),
              onPressed: enabled && duration > 0.1
                  ? () => _setDuration(duration - 0.1)
                  : null,
              color: const Color(0xFF0369A1),
            ),
          ),
          // Waarde
          Container(
            width: 52,
            alignment: Alignment.center,
            child: Text(
              enabled ? '${duration.toStringAsFixed(1)} s' : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? const Color(0xFF0369A1)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
          // Plus knop
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, size: 14),
              onPressed: enabled ? () => _setDuration(duration + 0.1) : null,
              color: const Color(0xFF0369A1),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-slide logo-zichtbaarheid ──────────────────────────────────────────────

class _SlideLogoControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideLogoControl({required this.slide, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          const Icon(
            Icons.branding_watermark_outlined,
            size: 14,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          Checkbox(
            value: slide.showLogo,
            onChanged: (v) => onUpdate(slide.copyWith(showLogo: v ?? true)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.d('Logo tonen op deze slide'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

// ── Per-slide footer-zichtbaarheid ────────────────────────────────────────────

class _SlideFooterControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideFooterControl({required this.slide, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          const Icon(
            Icons.short_text_outlined,
            size: 14,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          Checkbox(
            value: slide.showFooter,
            onChanged: (v) => onUpdate(slide.copyWith(showFooter: v ?? true)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.d('Footer tonen op deze slide'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

// ── Per-slide TLP-classificatie ───────────────────────────────────────────────

class _SlideTlpControl extends StatelessWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _SlideTlpControl({required this.slide, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.d('TLP van deze slide'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<TlpLevel>(
              value: slide.tlp,
              isDense: true,
              borderRadius: BorderRadius.circular(6),
              style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
              items: [
                for (final level in TlpLevel.values)
                  DropdownMenuItem(
                    value: level,
                    child: Text(
                      level == TlpLevel.none
                          ? l10n.d('Geen')
                          : level.menuLabel,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onUpdate(slide.copyWith(tlp: v));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Speakernotes veld ─────────────────────────────────────────────────────────

class _NotesField extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _NotesField({required this.slide, required this.onUpdate});

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.slide.notes);
    _ctrl.addListener(_emit);
  }

  @override
  void didUpdateWidget(_NotesField old) {
    super.didUpdateWidget(old);
    if (old.slide.id != widget.slide.id) {
      _ctrl.removeListener(_emit);
      _ctrl.text = widget.slide.notes;
      _ctrl.addListener(_emit);
    }
  }

  void _emit() => widget.onUpdate(widget.slide.copyWith(notes: _ctrl.text));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: const Color(0xFFFFFBEB),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Icon(Icons.notes, size: 14, color: Color(0xFFB45309)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: l10n.d('Sprekersnotities...'),
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFD97706),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Markdown mode editor ──────────────────────────────────────────────────────

class _MarkdownModeEditor extends StatefulWidget {
  final String initialContent;
  final bool Function(String) onApply;
  final bool parseError;
  final VoidCallback onExitMarkdown;

  const _MarkdownModeEditor({
    super.key,
    required this.initialContent,
    required this.onApply,
    required this.parseError,
    required this.onExitMarkdown,
  });

  @override
  State<_MarkdownModeEditor> createState() => _MarkdownModeEditorState();
}

class _MarkdownModeEditorState extends State<_MarkdownModeEditor> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar
        Container(
          color: const Color(0xFFFFF9E6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.code, size: 14, color: Color(0xFF92400E)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.d(
                    'Markdown modus — bewerk de volledige presentatie als Marp Markdown',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  final ok = widget.onApply(_ctrl.text);
                  if (ok) widget.onExitMarkdown();
                },
                child: Text(l10n.d('Toepassen')),
              ),
              TextButton(
                onPressed: widget.onExitMarkdown,
                child: Text(l10n.t('cancel')),
              ),
            ],
          ),
        ),
        if (widget.parseError)
          Container(
            color: const Color(0xFFFEE2E2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_outlined,
                  size: 14,
                  color: Colors.red,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.d(
                      'Markdown kon niet worden verwerkt. Controleer de syntax.',
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        // Code editor
        Expanded(
          child: TextField(
            controller: _ctrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(16),
              border: InputBorder.none,
              filled: true,
              fillColor: Color(0xFFF8FAFC),
            ),
          ),
        ),
      ],
    );
  }
}
