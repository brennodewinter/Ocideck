import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../editors/slide_type_help.dart';

part 'add_slide_dialog_painter.dart';
part 'add_slide_dialog_pills.dart';

class AddSlideDialog extends StatefulWidget {
  /// Whether the Informatieveiligheid module is revealed (enabled + a matching
  /// pack provisioned). Gates the security slide types and their picker tab, so
  /// they stay hidden until the module is on (see `infoSafetyRevealProvider`,
  /// PENTEST_MIAUW §6). Off by default; the caller passes the provider's value.
  final bool revealInfoSafety;

  /// Whether the Procesverbetering module is revealed. Gates improvement slide
  /// types and their picker tab (PROCESS_IMPROVEMENT.md Phase 0).
  final bool revealProcesverbetering;

  /// Whether the Managementsysteem module is revealed. Gates the `controlStatus`
  /// type and its picker tab, so they stay hidden until a deck already carries
  /// such a slide — the shared module contract "tonen zodra de inhoud er is"
  /// (ISO_MANAGEMENTSYSTEEM §5). Off by default; the caller passes the value.
  final bool revealManagementsysteem;

  const AddSlideDialog({
    super.key,
    this.revealInfoSafety = false,
    this.revealProcesverbetering = false,
    this.revealManagementsysteem = false,
  });

  static Future<SlideType?> show(
    BuildContext context, {
    bool revealInfoSafety = false,
    bool revealProcesverbetering = false,
    bool revealManagementsysteem = false,
  }) {
    return showDialog<SlideType>(
      context: context,
      builder: (_) => AddSlideDialog(
        revealInfoSafety: revealInfoSafety,
        revealProcesverbetering: revealProcesverbetering,
        revealManagementsysteem: revealManagementsysteem,
      ),
    );
  }

  /// Curated display order for the built-in types. Any [SlideType] missing here
  /// (a later package's addition) is appended in enum order, so the list is
  /// still derived from [slideTypeMeta] — the single source of truth — and no
  /// type can be forgotten.
  static const _curatedOrder = <SlideType>[
    SlideType.title,
    SlideType.section,
    SlideType.bullets,
    SlideType.twoBullets,
    SlideType.bulletsImage,
    SlideType.twoImages,
    SlideType.image,
    SlideType.video,
    SlideType.quote,
    SlideType.table,
    SlideType.chart,
    SlideType.timeline,
    SlideType.question,
    SlideType.code,
    SlideType.freeMarkdown,
    // Cockpit en scorecard zijn specialismes, geen algemeen slidetype —
    // onderaan de algemene lijst, niet tussen tabel en tijdlijn (#1957).
    SlideType.cockpit,
    SlideType.scorecard,
    // Informatieveiligheid-module — grouped last; shown under their own picker
    // tab (P0-PICK) once the category carries types.
    SlideType.assets,
    SlideType.discoveries,
    SlideType.finding,
    SlideType.findingsSummary,
    SlideType.checklist,
    SlideType.scopeMatrix,
    SlideType.signOff,
    // Procesverbetering-module — eigen tabblad zodra de module de types
    // onthult (PROCESS_IMPROVEMENT §6).
    SlideType.matrix,
    SlideType.canvas,
    SlideType.tree,
    SlideType.flow,
    SlideType.phaseGate,
    // Managementsysteem-module — eigen tabblad zodra de module de types
    // onthult (ISO_MANAGEMENTSYSTEEM §5).
    SlideType.controlStatus,
  ];

  @override
  State<AddSlideDialog> createState() => _AddSlideDialogState();
}

class _AddSlideDialogState extends State<AddSlideDialog> {
  final _searchCtrl = TextEditingController();
  bool _alphabetical = false;

  /// The active category filter, or `null` for the "all types" tab. Only
  /// meaningful when the tab bar is shown (i.e. ≥2 categories carry types).
  SlideCategory? _activeCategory;

  /// Het type waarvan de uitleg onder het rooster staat: dat wat de muis of de
  /// toetsenbordfocus aanwijst.
  ///
  /// Blijft staan als de muis het kaartje verlaat. Leegmaken zou de uitleg
  /// laten knipperen bij elke beweging over het rooster, en de dialoog laten
  /// springen — terwijl de vraag "wat is dit?" juist beantwoord blijft moeten
  /// worden tot je iets anders aanwijst.
  SlideType? _highlighted;

  @override
  void initState() {
    super.initState();
    // Default to the first category tab when the tab bar is shown (≥2
    // categories carry types); otherwise no tab bar and the value is unused.
    // Computed without l10n — `context.l10n` is illegal in initState, and the
    // labelled tabs are built later in [_tabs] (during build). This mirrors
    // `_tabs`' first entry: the first present category in enum order.
    final present = _categoriesPresent();
    _activeCategory = present.length < 2
        ? null
        : SlideCategory.values.firstWhere(present.contains);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// The types the picker may offer: every registered type, minus module-gated
  /// types while their module is not revealed. Derived from [slideTypeMeta] so
  /// a new type shows up automatically.
  Iterable<SlideType> _availableTypes() => slideTypeMeta.keys.where((t) {
    if (t.category == SlideCategory.informationSecurity &&
        !widget.revealInfoSafety) {
      return false;
    }
    if (t.category == SlideCategory.procesverbetering &&
        !widget.revealProcesverbetering) {
      return false;
    }
    if (t.category == SlideCategory.managementsysteem &&
        !widget.revealManagementsysteem) {
      return false;
    }
    return true;
  });

  /// Available types in curated order, with any uncurated type appended in enum
  /// order.
  List<SlideType> _orderedTypes() {
    final order = AddSlideDialog._curatedOrder;
    int rank(SlideType t) {
      final i = order.indexOf(t);
      return i == -1 ? order.length + t.index : i;
    }

    return _availableTypes().toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  Set<SlideCategory> _categoriesPresent() =>
      _availableTypes().map((t) => t.category).toSet();

  /// The tab bar's tabs, or an empty list when only one category carries
  /// types (today's state) — in which case no tab bar is drawn. A category tab
  /// only appears when types of that category exist, so the
  /// `informatieveiligheid` tab is gated on the presence of such types.
  List<_PickerTab> _tabs() {
    final present = _categoriesPresent();
    if (present.length < 2) return const [];
    final l10n = context.l10n;
    return [
      for (final c in SlideCategory.values)
        if (present.contains(c)) _PickerTab(c, _categoryLabel(l10n, c)),
      _PickerTab(null, l10n.d('Alle')),
    ];
  }

  String _categoryLabel(AppLocalizations l10n, SlideCategory category) {
    switch (category) {
      case SlideCategory.general:
        return l10n.d('Algemeen');
      case SlideCategory.informationSecurity:
        return l10n.d('Informatieveiligheid');
      case SlideCategory.procesverbetering:
        return l10n.d('Procesverbetering');
      case SlideCategory.managementsysteem:
        return l10n.d('Managementsysteem');
    }
  }

  /// The visible types after applying the active category tab, the search
  /// query (case/diacritic-insensitive contains on the localised label) and
  /// the sort mode (curated by default, alphabetical when toggled).
  List<SlideType> _visibleTypes(AppLocalizations l10n, bool hasTabs) {
    var types = _orderedTypes();
    if (hasTabs && _activeCategory != null) {
      types = types.where((t) => t.category == _activeCategory).toList();
    }
    final query = AppLocalizations.sortKey(_searchCtrl.text.trim());
    if (query.isNotEmpty) {
      types = types
          .where(
            (t) => AppLocalizations.sortKey(l10n.d(t.label)).contains(query),
          )
          .toList();
    }
    if (_alphabetical) {
      types.sort(
        (a, b) => AppLocalizations.sortKey(
          l10n.d(a.label),
        ).compareTo(AppLocalizations.sortKey(l10n.d(b.label))),
      );
    }
    return types;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = _tabs();
    final types = _visibleTypes(l10n, tabs.isNotEmpty);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l10n.d('Slide type kiezen')),
        content: SizedBox(
          width: 440,
          // Reading-order tabbing through the controls and cards; the first
          // card takes focus so the dialog is keyboard-operable right away.
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tabs.isNotEmpty) ...[
                  _buildTabBar(tabs),
                  const SizedBox(height: 10),
                ],
                _buildSearchRow(l10n),
                const SizedBox(height: 12),
                Flexible(child: _buildGrid(context, l10n, types)),
                if (types.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildHelpStrip(context, l10n, types),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<_PickerTab> tabs) {
    return Semantics(
      container: true,
      child: Wrap(
        key: const Key('addSlideCategoryTabs'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tab in tabs)
            _CategoryPill(
              label: tab.label,
              selected: _activeCategory == tab.category,
              onTap: () => setState(() => _activeCategory = tab.category),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchRow(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: l10n.d('Zoek een slidetype'),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: l10n.d('Zoekopdracht wissen'),
                      onPressed: () => setState(() => _searchCtrl.clear()),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.sort_by_alpha),
          isSelected: _alphabetical,
          tooltip: l10n.d('Alfabetisch sorteren'),
          onPressed: () => setState(() => _alphabetical = !_alphabetical),
          style: IconButton.styleFrom(
            backgroundColor: _alphabetical
                ? AppTheme.accent.withValues(alpha: 0.14)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(
    BuildContext context,
    AppLocalizations l10n,
    List<SlideType> types,
  ) {
    if (types.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l10n.d('Geen resultaten'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.slate500),
        ),
      );
    }
    return SingleChildScrollView(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < types.length; i++)
            _TypeCard(
              type: types[i],
              label: l10n.d(types[i].label),
              help: slideTypeHelpText(l10n, types[i]),
              autofocus: i == 0,
              onTap: () => Navigator.pop(context, types[i]),
              onHighlight: () => _highlight(types[i]),
            ),
        ],
      ),
    );
  }

  void _highlight(SlideType type) {
    if (_highlighted == type) return;
    setState(() => _highlighted = type);
  }

  /// De uitleg bij het aangewezen slidetype, onder het rooster.
  ///
  /// Deze tekst bestond al — volledig, in 32 talen — maar verscheen pas ná het
  /// invoegen, achter een dichtgeklapte "Wat kan ik hier?". Wie moest kiezen,
  /// koos dus op een draadframe en een woord. Nu staat het antwoord waar de
  /// vraag gesteld wordt.
  ///
  /// De hoogte is begrensd in regelhoogtes, niet in pixels: bij 200%
  /// interfacetekst groeit het vak mee, en een uitzonderlijk lange vertaling
  /// scrolt binnen het vak in plaats van de dialoog te laten springen.
  Widget _buildHelpStrip(
    BuildContext context,
    AppLocalizations l10n,
    List<SlideType> types,
  ) {
    // Bij het openen wijst niets aan; het eerste kaartje heeft de focus, dus
    // dat is ook wat de uitleg toont.
    final shown = types.contains(_highlighted) ? _highlighted! : types.first;
    final line = MediaQuery.textScalerOf(context).scale(12.5) * 1.45;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.teal.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.teal.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: line * 3, maxHeight: line * 5),
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 15, color: AppTheme.tealFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slideTypeHelpText(l10n, shown),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppTheme.slate700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final SlideType type;
  final String label;

  /// De uitleg bij dit type. Gaat als schermlezer-hint mee op het kaartje zelf,
  /// zodat wie niet kijkt hem hoort op het moment van kiezen — niet pas in het
  /// vak eronder, dat een schermlezer nooit passeert.
  final String help;

  final VoidCallback onTap;
  final bool autofocus;

  /// Aangewezen door muis of toetsenbordfocus: het vak onder het rooster toont
  /// dan de uitleg van dit type.
  final VoidCallback onHighlight;

  const _TypeCard({
    required this.type,
    required this.label,
    required this.help,
    required this.onTap,
    required this.onHighlight,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: help,
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus,
        onHover: (hovering) {
          if (hovering) onHighlight();
        },
        onFocusChange: (focused) {
          if (focused) onHighlight();
        },
        borderRadius: BorderRadius.circular(8),
        focusColor: AppTheme.accent.withValues(alpha: 0.14),
        hoverColor: AppTheme.accent.withValues(alpha: 0.06),
        child: Container(
          width: 100,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.slate300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A stylised wireframe of the layout, so the card shows what
              // the slide will look like instead of an abstract icon.
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CustomPaint(
                      painter: SlideTypePreviewPainter(type: type),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FittedTypeLabel(label: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// A type card's label, stepped down just far enough that its longest word fits
/// the card.
///
/// Type names are one or a few words, and Dutch and German turn them into long
/// compounds — "Aanvalsoppervlak", "Angriffsfläche", "Bevindingenoverzicht".
/// Left alone, Flutter breaks such a word wherever it runs out of room
/// ("Aanvalsopperv / lak"), which reads as a typo rather than as a line break.
/// Shortening the Dutch label would not help: the translations are longer still
/// (*Superficie di attacco*, *Атакуема повърхност*), so the card has to give
/// instead of the word.
///
/// Wrapping at spaces is untouched — a two-word label still breaks in two. Only
/// when a *single* word is wider than the card does the whole label step down,
/// in half-point stages, to a floor of 8pt. Below that the text would stop being
/// readable, so a pathological label is ellipsised instead.
@visibleForTesting
class FittedTypeLabel extends StatelessWidget {
  final String label;

  /// The size a label uses when it fits, and the size every card shows in
  /// practice — the step-down is the exception, not the rule.
  static const baseFontSize = 11.0;
  static const minFontSize = 8.0;

  const FittedTypeLabel({super.key, required this.label});

  static TextStyle _styleAt(double fontSize) =>
      TextStyle(fontSize: fontSize, height: 1.15);

  /// The pieces a label may be broken into without breaking *inside* a word.
  ///
  /// Whitespace, and after a hyphen — Flutter's line breaker treats a hyphen as
  /// a break opportunity and keeps it on the first line, which was measured
  /// rather than assumed: Swedish *Cockpit-instrumentpanel* renders as
  /// "Cockpit-" / "instrumentpanel", two lines that both fit the card.
  ///
  /// Counting it as one unbreakable token made the card shrink to the 8pt floor
  /// for a label that reads fine at 11. Measuring what the renderer will
  /// actually do is the difference between a cautious layout and a small one.
  static Iterable<String> _breakablePieces(String label) =>
      label.split(RegExp(r'(?<=-)|\s+')).where((p) => p.isNotEmpty);

  /// The width the longest unbreakable piece needs, measured in [base] at
  /// [fontSize].
  ///
  /// [base] must be the style the label is actually **rendered** in — the
  /// inherited [DefaultTextStyle] merged with the size. Measuring a bare
  /// `TextStyle` measures the framework's default font while the card draws the
  /// theme's, which is wider: the measurement then reports that the word fits
  /// and the eye reports otherwise.
  static double _longestWordWidth(
    String label,
    double fontSize,
    TextDirection direction,
    TextStyle base,
  ) {
    final longest = _breakablePieces(
      label,
    ).fold<String>('', (a, b) => b.length > a.length ? b : a);
    final painter = TextPainter(
      text: TextSpan(text: longest, style: base.merge(_styleAt(fontSize))),
      textDirection: direction,
    )..layout();
    return painter.width;
  }

  /// The largest size at or below [baseFontSize] whose longest word fits
  /// [maxWidth] when rendered in [base]. Exposed for the test that guards the
  /// step-down.
  @visibleForTesting
  static double fittedFontSize(
    String label,
    double maxWidth,
    TextDirection direction, {
    TextStyle base = const TextStyle(),
  }) {
    var size = baseFontSize;
    while (size > minFontSize &&
        _longestWordWidth(label, size, direction, base) > maxWidth) {
      size -= 0.5;
    }
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    // The style the Text will inherit. Measure against this, or the card
    // measures one font and draws another.
    final inherited = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) => Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _styleAt(
          fittedFontSize(
            label,
            constraints.maxWidth,
            direction,
            base: inherited,
          ),
        ),
      ),
    );
  }
}

/// Paints a miniature 16:9 wireframe of a slide layout, in the spirit of the
/// layout pickers in other presentation tools: title bars, text lines, image
/// placeholders. All geometry lives on a 160×90 design canvas and is scaled
/// to whatever size the card provides.
@visibleForTesting
class SlideTypePreviewPainter extends CustomPainter {
  final SlideType type;

  /// Wireframe palette: dark bars for titles, soft bars for body text.
  static Color get _canvas => AppTheme.slate50;
  static Color get _ink => AppTheme.slate700;
  static const _soft = AppTheme.blueGray;
  static Color get _fill => AppTheme.slate200;
  static const _accent = AppTheme.accent;

  const SlideTypePreviewPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 160;
    canvas.scale(u);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 160, 90), _paint(_canvas));

    switch (type) {
      case SlideType.title:
        _bar(canvas, 30, 34, 100, 12, _ink);
        _bar(canvas, 45, 53, 70, 7, _accent);
      case SlideType.section:
        _bar(canvas, 16, 36, 5, 24, _accent);
        _bar(canvas, 30, 38, 86, 11, _ink);
        _bar(canvas, 30, 54, 52, 6, _soft);
      case SlideType.bullets:
        _bar(canvas, 14, 12, 84, 9, _ink);
        _bullets(canvas, 14, 34, 110, 4);
      case SlideType.menu:
        _paintMenuWireframe(canvas);
      case SlideType.twoBullets:
        _bar(canvas, 14, 12, 84, 9, _ink);
        _bullets(canvas, 14, 32, 56, 3);
        _bullets(canvas, 90, 32, 56, 3);
      case SlideType.bulletsImage:
        _bar(canvas, 14, 12, 66, 9, _ink);
        _bullets(canvas, 14, 32, 60, 3);
        _imageBox(canvas, 90, 26, 56, 50);
      case SlideType.twoImages:
        _imageBox(canvas, 12, 16, 64, 46);
        _imageBox(canvas, 84, 16, 64, 46);
        _bar(canvas, 20, 68, 48, 5, _soft);
        _bar(canvas, 92, 68, 48, 5, _soft);
      case SlideType.image:
        _imageBox(canvas, 10, 10, 140, 70);
      case SlideType.video:
        _imageBox(canvas, 10, 10, 140, 70, pictogram: false);
        canvas.drawCircle(const Offset(80, 45), 14, _paint(Colors.white));
        final play = Path()
          ..moveTo(75, 37)
          ..lineTo(89, 45)
          ..lineTo(75, 53)
          ..close();
        canvas.drawPath(play, _paint(_ink));
      case SlideType.quote:
        _quoteMark(canvas, 16, 16);
        _bar(canvas, 42, 30, 96, 7, _ink);
        _bar(canvas, 42, 43, 78, 7, _ink);
        _bar(canvas, 42, 60, 42, 5, _accent);
      case SlideType.table:
        _bar(canvas, 14, 16, 132, 14, _soft, radius: 2);
        final line = _paint(_ink.withValues(alpha: 0.45))..strokeWidth = 1.5;
        for (var r = 1; r <= 4; r++) {
          canvas.drawLine(
            Offset(14, 16 + r * 14),
            Offset(146, 16 + r * 14),
            line,
          );
        }
        for (var c = 0; c <= 3; c++) {
          canvas.drawLine(
            Offset(14 + c * 44, 16),
            Offset(14 + c * 44, 72),
            line,
          );
        }
      case SlideType.chart:
        final axis = _paint(_soft)..strokeWidth = 2;
        canvas.drawLine(const Offset(20, 14), const Offset(20, 74), axis);
        canvas.drawLine(const Offset(20, 74), const Offset(148, 74), axis);
        _bar(canvas, 34, 50, 18, 24, _soft, radius: 2);
        _bar(canvas, 64, 36, 18, 38, _accent, radius: 2);
        _bar(canvas, 94, 44, 18, 30, _soft, radius: 2);
        _bar(canvas, 124, 24, 18, 50, _accent, radius: 2);
      case SlideType.cockpit:
        _dial(canvas, 24, 24, 22);
        _dial(canvas, 69, 24, 22);
        _dial(canvas, 114, 24, 22);
        _dial(canvas, 46, 58, 22);
        _dial(canvas, 92, 58, 22);
      case SlideType.timeline:
        _paintTimelineWireframe(canvas);
      case SlideType.code:
        _bar(canvas, 10, 10, 140, 70, AppTheme.slate800, radius: 4);
        _bar(canvas, 20, 22, 44, 6, AppTheme.successSoft, radius: 3);
        _bar(canvas, 30, 34, 64, 6, AppTheme.paleBlue, radius: 3);
        _bar(canvas, 30, 46, 50, 6, AppTheme.goldSoft2, radius: 3);
        _bar(canvas, 20, 58, 32, 6, AppTheme.successSoft, radius: 3);
      case SlideType.freeMarkdown:
        _bar(canvas, 14, 12, 10, 9, _accent, radius: 2);
        _bar(canvas, 28, 12, 62, 9, _ink);
        _bar(canvas, 14, 32, 120, 6, _soft);
        _bar(canvas, 14, 44, 132, 6, _soft);
        _bar(canvas, 14, 56, 92, 6, _soft);
        _bar(canvas, 14, 68, 110, 6, _soft);
      case SlideType.question:
        // Prompt line on top, then four answer pills — the first highlighted
        // as the (correct) selected option.
        _bar(canvas, 14, 12, 96, 9, _ink);
        for (var r = 0; r < 4; r++) {
          final y = 30.0 + r * 13;
          _bar(canvas, 14, y, 132, 10, r == 0 ? _accent : _soft, radius: 3);
        }
      case SlideType.scorecard:
        _paintScorecardWireframe(canvas);
      case SlideType.assets:
        _paintAssetsWireframe(canvas);
      case SlideType.discoveries:
        _paintDiscoveriesWireframe(canvas);
      case SlideType.finding:
      case SlideType.findingsSummary:
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.signOff:
        _paintSecurityWireframe(canvas, type);
      case SlideType.matrix:
        _paintMatrixWireframe(canvas);
      case SlideType.canvas:
        _paintCanvasWireframe(canvas);
      case SlideType.tree:
        _paintTreeWireframe(canvas);
      case SlideType.flow:
        _paintFlowWireframe(canvas);
      // controlStatus leent de checklist-wireframe, net als phaseGate: rijen met
      // statusvakjes.
      case SlideType.phaseGate:
      case SlideType.controlStatus:
        _paintSecurityWireframe(canvas, SlideType.checklist);
      case SlideType.gantt:
        _paintGanttWireframe(canvas);
    }
  }

  /// Horizontal process chain off a title bar.
  void _paintFlowWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 8, _ink);
    for (var i = 0; i < 3; i++) {
      final x = 14.0 + i * 44;
      _bar(canvas, x, 32, 36, 22, _fill, radius: 3);
      if (i < 2) {
        canvas.drawLine(
          Offset(x + 38, 43),
          Offset(x + 44, 43),
          _paint(_accent.withValues(alpha: 0.6))..strokeWidth = 1.5,
        );
      }
    }
    _bar(canvas, 14, 62, 100, 5, _soft);
  }

  /// Gantt wireframe: title bar, timeline axis, three task bars.
  void _paintGanttWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 8, _ink);
    final axis = _paint(_soft)..strokeWidth = 1.2;
    canvas.drawLine(const Offset(14, 28), const Offset(146, 28), axis);
    _bar(canvas, 14, 34, 40, 7, _fill, radius: 2);
    _bar(canvas, 14, 46, 60, 7, _accent, radius: 2);
    _bar(canvas, 14, 58, 30, 7, _fill, radius: 2);
  }

  /// Nested list / fishbone branches off a title bar.
  void _paintTreeWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 8, _ink);
    _bar(canvas, 14, 28, 48, 6, _soft);
    _bar(canvas, 22, 40, 56, 5, _fill);
    _bar(canvas, 30, 52, 44, 5, _fill);
    canvas.drawLine(
      const Offset(18, 34),
      const Offset(18, 56),
      _paint(_accent.withValues(alpha: 0.5))..strokeWidth = 1.5,
    );
    canvas.drawLine(
      const Offset(26, 42),
      const Offset(26, 56),
      _paint(_accent.withValues(alpha: 0.35))..strokeWidth = 1.2,
    );
    canvas.drawLine(
      const Offset(120, 48),
      const Offset(146, 48),
      _paint(_bone)..strokeWidth = 2,
    );
    canvas.drawLine(
      const Offset(130, 48),
      const Offset(124, 38),
      _paint(_bone)..strokeWidth = 1.5,
    );
    canvas.drawLine(
      const Offset(130, 48),
      const Offset(124, 58),
      _paint(_bone)..strokeWidth = 1.5,
    );
  }

  static Color get _bone => AppTheme.slate600;

  /// Typed grid: title bar plus a few cells, some accented (high RPN / focus).
  void _paintMatrixWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 8, _ink);
    final grid = _paint(_soft)..strokeWidth = 1.2;
    const gLeft = 14.0, gTop = 28.0, gRight = 146.0, gBottom = 76.0;
    for (var c = 0; c <= 5; c++) {
      final x = gLeft + c * (gRight - gLeft) / 5;
      canvas.drawLine(Offset(x, gTop), Offset(x, gBottom), grid);
    }
    for (var rr = 0; rr <= 3; rr++) {
      final y = gTop + rr * (gBottom - gTop) / 3;
      canvas.drawLine(Offset(gLeft, y), Offset(gRight, y), grid);
    }
    _bar(canvas, 16, 30, (gRight - gLeft) - 4, 12, _fill, radius: 1);
    _bar(canvas, 42, 46, 18, 9, _accent, radius: 2);
    _bar(canvas, 94, 62, 18, 9, _accent, radius: 2);
  }

  /// Named regions: title bar plus four boxes in a 2×2 grid.
  void _paintCanvasWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 8, _ink);
    const left = 14.0, top = 28.0, gap = 4.0;
    const boxW = 66.0, boxH = 22.0;
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        final x = left + col * (boxW + gap);
        final y = top + row * (boxH + gap);
        _bar(canvas, x, y, boxW, boxH, _fill, radius: 2);
        _bar(canvas, x + 4, y + 4, boxW * 0.45, 5, _soft, radius: 1);
      }
    }
  }

  /// Heading plus three tiles, each a label, the figure, and the small change
  /// line underneath that carries the news. Split out of [paint] for the same
  /// reason as [_paintSecurityWireframe]: the length ratchet.
  void _paintScorecardWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 9, _ink);
    for (var i = 0; i < 3; i++) {
      final x = 14.0 + i * 47;
      _bar(canvas, x, 32, 26, 5, _soft, radius: 2);
      _bar(canvas, x, 43, 38, 14, _ink, radius: 3);
      _bar(canvas, x, 63, 18, 6, _accent, radius: 2);
    }
  }

  /// Heading plus four proportional bars of differing length, each with a
  /// filled head standing for the at-risk share. Split out of [paint] for the
  /// length ratchet, like the other reporting wireframes.
  /// Heading, then a named find per row with its exposure bar and an ownership
  /// marker on the right. Longest first, because that is the order the slide
  /// itself argues in — and what tells this wireframe apart from the assets one,
  /// whose bars carry a nested at-risk head instead.
  void _paintDiscoveriesWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 9, _ink);
    const widths = [96.0, 62.0, 38.0, 20.0];
    for (var i = 0; i < widths.length; i++) {
      final y = 32.0 + i * 13;
      _bar(canvas, 14, y, 34, 6, _ink, radius: 2);
      _bar(canvas, 54, y, widths[i], 7, _accent, radius: 2);
      // Ownership: the first two finds have somebody's name against them, the
      // rest do not — the governance half of the slide.
      _bar(canvas, 156, y, 7, 7, i < 2 ? _soft : _accent, radius: 2);
    }
  }

  void _paintAssetsWireframe(Canvas canvas) {
    _bar(canvas, 14, 12, 72, 9, _ink);
    const widths = [118.0, 76.0, 44.0, 22.0];
    for (var i = 0; i < widths.length; i++) {
      final y = 32.0 + i * 13;
      _bar(canvas, 14, y, 26, 6, _soft, radius: 2);
      _bar(canvas, 46, y, widths[i], 7, _fill, radius: 2);
      // The at-risk head: always a slice, never the whole bar.
      _bar(canvas, 46, y, widths[i] * 0.28, 7, _accent, radius: 2);
    }
  }

  /// Wireframe voor het keuze-menu (#1162): titel plus een 2×2 raster van
  /// keuzeblokken met elk een labelbalkje. Losgetrokken uit [paint] om die
  /// binnen de lengte-ratchet te houden.
  void _paintMenuWireframe(Canvas canvas) {
    _bar(canvas, 14, 10, 70, 8, _ink);
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 2; c++) {
        final x = 12.0 + c * 74;
        final y = 26.0 + r * 30;
        _bar(canvas, x, y, 66, 24, _fill, radius: 4);
        _bar(canvas, x + 8, y + 9, 40, 6, _soft);
      }
    }
  }

  /// Wireframes for the Informatieveiligheid slide types (P1-S), split out of
  /// [paint] so that method stays within the length ratchet. Only called for
  /// the five security types; the `default` keeps the switch total.
  void _paintSecurityWireframe(Canvas canvas, SlideType type) {
    switch (type) {
      case SlideType.finding:
        // Finding card: id/title bar with a severity chip, then body lines.
        _bar(canvas, 14, 12, 68, 9, _ink);
        _bar(canvas, 120, 11, 26, 11, _accent, radius: 3);
        _bar(canvas, 14, 32, 132, 6, _soft);
        _bar(canvas, 14, 44, 116, 6, _soft);
        _bar(canvas, 14, 56, 132, 6, _soft);
        _bar(canvas, 14, 68, 88, 6, _soft);
      case SlideType.findingsSummary:
        // Severity roll-up: axis + bars descending from critical to low.
        final sumAxis = _paint(_soft)..strokeWidth = 2;
        canvas.drawLine(const Offset(22, 14), const Offset(22, 74), sumAxis);
        canvas.drawLine(const Offset(22, 74), const Offset(148, 74), sumAxis);
        _bar(canvas, 34, 28, 22, 46, _accent, radius: 2);
        _bar(canvas, 66, 40, 22, 34, _ink, radius: 2);
        _bar(canvas, 98, 52, 22, 22, _soft, radius: 2);
        _bar(canvas, 130, 62, 14, 12, _fill, radius: 2);
      case SlideType.checklist:
        // Title, then rows each with a status box and a text line.
        _bar(canvas, 14, 12, 96, 9, _ink);
        for (var r = 0; r < 4; r++) {
          final y = 30.0 + r * 13;
          _bar(canvas, 14, y, 9, 9, r.isEven ? _accent : _soft, radius: 2);
          _bar(canvas, 30, y + 1, r.isEven ? 116 : 96, 6, _soft);
        }
      case SlideType.scopeMatrix:
        // Objects (rows) × standards (columns) grid with a few tested cells.
        _bar(canvas, 14, 12, 72, 8, _ink);
        final grid = _paint(_soft)..strokeWidth = 1.2;
        const gLeft = 14.0, gTop = 28.0, gRight = 146.0, gBottom = 76.0;
        for (var c = 0; c <= 4; c++) {
          final x = gLeft + c * (gRight - gLeft) / 4;
          canvas.drawLine(Offset(x, gTop), Offset(x, gBottom), grid);
        }
        for (var rr = 0; rr <= 3; rr++) {
          final y = gTop + rr * (gBottom - gTop) / 3;
          canvas.drawLine(Offset(gLeft, y), Offset(gRight, y), grid);
        }
        _bar(canvas, 20, 32, 20, 9, _accent, radius: 2);
        _bar(canvas, 86, 48, 20, 9, _accent, radius: 2);
        _bar(canvas, 53, 64, 20, 9, _accent, radius: 2);
      case SlideType.signOff:
        // Truthfulness statement, a signature scribble over a rule, and a seal.
        _bar(canvas, 14, 12, 90, 9, _ink);
        _bar(canvas, 14, 30, 132, 6, _soft);
        _bar(canvas, 14, 42, 108, 6, _soft);
        canvas.drawLine(
          const Offset(20, 68),
          const Offset(98, 68),
          _paint(_ink)..strokeWidth = 1.5,
        );
        final sig = Path()
          ..moveTo(26, 66)
          ..cubicTo(34, 54, 44, 74, 54, 60)
          ..cubicTo(62, 50, 72, 70, 92, 58);
        canvas.drawPath(
          sig,
          _paint(_accent)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
        canvas.drawCircle(
          const Offset(128, 60),
          12,
          _paint(_accent.withValues(alpha: 0.18)),
        );
        canvas.drawCircle(
          const Offset(128, 60),
          12,
          _paint(_accent)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      // De niet-informatieveiligheidstypen tekenen hun wireframe in [paint]
      // zelf en komen hier nooit. Toch uitgeschreven in plaats van een
      // `default:`: alleen zo blijft de compiler meelezen. Wordt dit ooit een
      // vijfde-plus-type, dan wijst hij de plek aan in plaats van er stil een
      // lege thumbnail van te maken.
      case SlideType.title ||
          SlideType.section ||
          SlideType.bullets ||
          SlideType.menu ||
          SlideType.twoBullets ||
          SlideType.bulletsImage ||
          SlideType.twoImages ||
          SlideType.image ||
          SlideType.video ||
          SlideType.quote ||
          SlideType.table ||
          SlideType.freeMarkdown ||
          SlideType.code ||
          SlideType.chart ||
          SlideType.cockpit ||
          SlideType.question ||
          SlideType.timeline ||
          SlideType.scorecard ||
          SlideType.assets ||
          SlideType.discoveries ||
          SlideType.matrix ||
          SlideType.canvas ||
          SlideType.tree ||
          SlideType.flow ||
          SlideType.phaseGate ||
          SlideType.controlStatus ||
          SlideType.gantt:
        break;
    }
  }

  void _bar(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    Color color, {
    double? radius,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(radius ?? h / 2),
      ),
      _paint(color),
    );
  }

  /// A column of bullet points: accent dot plus a soft text line.
  void _bullets(Canvas canvas, double x, double y, double w, int count) {
    for (var i = 0; i < count; i++) {
      final dy = y + i * 13.0;
      canvas.drawCircle(Offset(x + 3, dy + 3), 3, _paint(_accent));
      _bar(canvas, x + 11, dy, w * (i.isEven ? 1.0 : 0.74), 6, _soft);
    }
  }

  /// Image placeholder: filled box with a sun and mountains pictogram.
  void _imageBox(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h, {
    bool pictogram = true,
  }) {
    _bar(canvas, x, y, w, h, _fill, radius: 4);
    if (!pictogram) return;
    final dark = _paint(_soft);
    canvas.drawCircle(Offset(x + w * 0.28, y + h * 0.30), h * 0.11, dark);
    final hills = Path()
      ..moveTo(x + w * 0.08, y + h * 0.88)
      ..lineTo(x + w * 0.38, y + h * 0.45)
      ..lineTo(x + w * 0.58, y + h * 0.72)
      ..lineTo(x + w * 0.74, y + h * 0.52)
      ..lineTo(x + w * 0.94, y + h * 0.88)
      ..close();
    canvas.drawPath(hills, dark);
  }

  /// A stylised double quotation mark.
  void _quoteMark(Canvas canvas, double x, double y) {
    final paint = _paint(_accent);
    for (final dx in [0.0, 11.0]) {
      canvas.drawCircle(Offset(x + 4 + dx, y + 8), 4, paint);
      final tail = Path()
        ..moveTo(x + dx, y + 8)
        ..quadraticBezierTo(x + dx, y + 17, x + 7 + dx, y + 18)
        ..lineTo(x + 7 + dx, y + 14)
        ..quadraticBezierTo(x + 4 + dx, y + 13, x + 4 + dx, y + 8)
        ..close();
      canvas.drawPath(tail, paint);
    }
  }

  void _dial(Canvas canvas, double x, double y, double r) {
    canvas.drawCircle(Offset(x, y), r, _paint(_accent.withValues(alpha: 0.12)));
    canvas.drawCircle(
      Offset(x, y),
      r,
      _paint(_ink)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawLine(
      Offset(x, y),
      Offset(x + r * 0.55, y - r * 0.35),
      _paint(_accent)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(x, y), 3, _paint(_ink));
  }

  @override
  bool shouldRepaint(SlideTypePreviewPainter old) => old.type != type;
}

Paint _paint(Color color) => Paint()..color = color;
