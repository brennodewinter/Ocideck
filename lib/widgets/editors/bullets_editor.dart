import 'package:material_ui/material_ui.dart';
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
import 'bullet_editor_items.dart';
import 'editor_text_controller.dart';
import 'ai_condense_button.dart';
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
  late final EditorTextController _title;
  late final EditorTextController _subtitle;
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
    _subtitle = EditorTextController(text: widget.slide.subtitle);
    _subtitle.addTextListener(_emit);
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
    if (index < 0 || index >= _bullets.controllers.length) return;
    _bullets.focusNodes[index].requestFocus();
    applyQualitySpanSelection(
      _bullets.controllers[index],
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
    final stripped = _bullets.controllers[index].text;
    if (!raw.endsWith(stripped)) return null;
    final shift = raw.length - stripped.length;
    if (span.start - shift < 0) return null;
    return SlideQualitySpan(
      start: span.start - shift,
      end: span.end - shift,
      fragmentIndex: index,
    );
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
            : _bullets.values(_listStyle),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _richText.dispose();
    _bullets.dispose();
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
          AiCondenseButton(slide: widget.slide),
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
          const SectionLabel('Bullets'),
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
              for (int i = 0; i < _bullets.controllers.length; i++)
                BulletEditorRow(
                  key: ValueKey(_bullets.controllers[i]),
                  bullets: _bullets,
                  index: i,
                  listStyle: _listStyle,
                  mutate: (mutation) => setState(mutation),
                  reorderable: true,
                ),
            ],
          ),
          const SizedBox(height: 4),
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
          Icon(Icons.splitscreen, size: 16, color: AppTheme.accentFg),
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
}
