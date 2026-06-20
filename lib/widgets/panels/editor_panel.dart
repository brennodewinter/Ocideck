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
import '../panels/slide_quality_panel.dart';
import '../editors/markdown_deck_editor.dart';
import '../markdown_notes_editor.dart';

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
      return MarkdownDeckEditor(
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
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SlideQualityPanel(),
                const Divider(height: 1),
                _buildEditor(
                  slide,
                  update,
                  imgService,
                  searchPaths,
                  deck.projectPath,
                  (variants) {
                    final first = deckNotifier.insertSlides(
                      variants,
                      afterIndex: idx,
                    );
                    if (first >= 0) editorNotifier.select(first);
                  },
                  nestedInScrollView: true,
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
                      projectPath: deck.projectPath,
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
                const Divider(height: 1),
                _UserNotesField(
                  slide: slide,
                  note: deck.userNotes[slide.id] ?? '',
                  onChanged: (text) =>
                      deckNotifier.setUserNoteForSlide(slide.id, text),
                ),
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
      listStyle: slide.listStyle,
      showChecklistProgress: slide.showChecklistProgress,
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
    ValueChanged<List<Slide>> onAddChartVariants, {
    bool nestedInScrollView = false,
  }) {
    switch (slide.type) {
      case SlideType.title:
        return TitleEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.section:
        return SectionEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.bullets:
        return BulletsEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.twoBullets:
        return TwoBulletsEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.bulletsImage:
        return BulletsImageEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          imageService: imgService,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.twoImages:
        return TwoImagesEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.image:
        return ImageSlideEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          imageService: imgService,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.video:
        return VideoSlideEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          imageService: imgService,
          projectPath: captionBasePath,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.quote:
        return QuoteEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          searchPaths: searchPaths,
          captionBasePath: captionBasePath,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.table:
        return TableEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.freeMarkdown:
        return FreeMarkdownEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.code:
        return CodeEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          nestedInScrollView: nestedInScrollView,
        );
      case SlideType.chart:
        return ChartEditor(
          key: ValueKey(slide.id),
          slide: slide,
          onUpdate: onUpdate,
          onAddVariants: onAddChartVariants,
          projectPath: captionBasePath,
          nestedInScrollView: nestedInScrollView,
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
                      level == TlpLevel.none ? l10n.d('Geen') : level.menuLabel,
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

double _notesEditorHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.28).clamp(240.0, 420.0);

class _NotesDiscardButton extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onDiscard;
  final Color color;

  const _NotesDiscardButton({
    super.key,
    required this.controller,
    required this.onDiscard,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final enabled = value.text.trim().isNotEmpty;
        return Tooltip(
          message: l10n.d('Notities weggooien'),
          child: IconButton(
            onPressed: enabled ? onDiscard : null,
            icon: const Icon(Icons.delete_outline, size: 16),
            color: color,
            disabledColor: color.withValues(alpha: 0.35),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        );
      },
    );
  }
}

class _NotesField extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  const _NotesField({required this.slide, required this.onUpdate});

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final TextEditingController _ctrl;
  bool _expanded = true;

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

  void _discardNotes() {
    if (_ctrl.text.trim().isEmpty) return;
    _ctrl.removeListener(_emit);
    _ctrl.text = '';
    _ctrl.addListener(_emit);
    widget.onUpdate(widget.slide.copyWith(notes: ''));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: const Color(0xFFFFFBEB),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: const Color(0xFFFCD34D)),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (open) => setState(() => _expanded = open),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: const Icon(Icons.notes, size: 18, color: Color(0xFFB45309)),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.d('Sprekersnotities'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              _NotesDiscardButton(
                key: ValueKey('discard-speaker-notes-${widget.slide.id}'),
                controller: _ctrl,
                onDiscard: _discardNotes,
                color: const Color(0xFFB45309),
              ),
            ],
          ),
          subtitle: widget.slide.notes.trim().isEmpty
              ? Text(
                  l10n.d('Notities voor tijdens het presenteren'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFD97706),
                  ),
                )
              : null,
          children: [
            SizedBox(
              height: _notesEditorHeight(context),
              child: MarkdownNotesEditor.legacy(
                key: ValueKey('speaker-notes-${widget.slide.id}'),
                controller: _ctrl,
                expand: true,
                baseStyle: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF78350F),
                  height: 1.45,
                ),
                linkColor: const Color(0xFFB45309),
                codeBackground: const Color(0xFFFFF7ED),
                hintText: l10n.d('Sprekersnotities...'),
                minLines: 10,
                contentPadding: const EdgeInsets.all(10),
                inputDecoration: InputDecoration(
                  hintText: l10n.d('Sprekersnotities...'),
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFD97706),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFFCD34D)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFFCD34D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gebruikersnotities veld ────────────────────────────────────────────────────

class _UserNotesField extends StatefulWidget {
  final Slide slide;
  final String note;
  final ValueChanged<String> onChanged;

  const _UserNotesField({
    required this.slide,
    required this.note,
    required this.onChanged,
  });

  @override
  State<_UserNotesField> createState() => _UserNotesFieldState();
}

class _UserNotesFieldState extends State<_UserNotesField> {
  late final TextEditingController _ctrl;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note);
    _ctrl.addListener(_emit);
  }

  @override
  void didUpdateWidget(_UserNotesField old) {
    super.didUpdateWidget(old);
    if (old.slide.id != widget.slide.id || old.note != widget.note) {
      _ctrl.removeListener(_emit);
      _ctrl.text = widget.note;
      _ctrl.addListener(_emit);
    }
  }

  void _emit() => widget.onChanged(_ctrl.text);

  void _discardNotes() {
    if (_ctrl.text.trim().isEmpty) return;
    _ctrl.removeListener(_emit);
    _ctrl.text = '';
    _ctrl.addListener(_emit);
    widget.onChanged('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: const Color(0xFFEFF6FF),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: const Color(0xFFBFDBFE)),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (open) => setState(() => _expanded = open),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: const Icon(
            Icons.edit_note_outlined,
            size: 18,
            color: Color(0xFF2563EB),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.d('Gebruikersnotities'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
              _NotesDiscardButton(
                key: ValueKey('discard-user-notes-${widget.slide.id}'),
                controller: _ctrl,
                onDiscard: _discardNotes,
                color: const Color(0xFF2563EB),
              ),
            ],
          ),
          subtitle: widget.note.trim().isEmpty
              ? Text(
                  l10n.d('Notities voor de ontvanger tijdens een cursus'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF60A5FA),
                  ),
                )
              : null,
          children: [
            SizedBox(
              height: _notesEditorHeight(context),
              child: MarkdownNotesEditor.legacy(
                key: ValueKey('user-notes-${widget.slide.id}'),
                controller: _ctrl,
                expand: true,
                baseStyle: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1E3A8A),
                  height: 1.45,
                ),
                linkColor: const Color(0xFF2563EB),
                codeBackground: const Color(0xFFEFF6FF),
                hintText: l10n.d('Gebruikersnotities voor deze slide...'),
                minLines: 10,
                contentPadding: const EdgeInsets.all(10),
                inputDecoration: InputDecoration(
                  hintText: l10n.d('Gebruikersnotities voor deze slide...'),
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF93C5FD),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFBFDBFE)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFBFDBFE)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
