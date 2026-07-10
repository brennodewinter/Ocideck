import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// A picker tab: one [SlideCategory] to filter by, or `null` for "all types".
class _PickerTab {
  final SlideCategory? category;
  final String label;
  const _PickerTab(this.category, this.label);
}

class AddSlideDialog extends StatefulWidget {
  /// Whether the Informatieveiligheid module is revealed (enabled + a matching
  /// pack provisioned). Gates the security slide types and their picker tab, so
  /// they stay hidden until the module is on (see `secModuleRevealProvider`,
  /// PENTEST_MIAUW §6). Off by default; the caller passes the provider's value.
  final bool revealSecurityModule;

  const AddSlideDialog({super.key, this.revealSecurityModule = false});

  static Future<SlideType?> show(
    BuildContext context, {
    bool revealSecurityModule = false,
  }) {
    return showDialog<SlideType>(
      context: context,
      builder: (_) =>
          AddSlideDialog(revealSecurityModule: revealSecurityModule),
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
    SlideType.cockpit,
    SlideType.timeline,
    SlideType.question,
    SlideType.code,
    SlideType.freeMarkdown,
    // Informatieveiligheid-module — grouped last; shown under their own picker
    // tab (P0-PICK) once the category carries types.
    SlideType.finding,
    SlideType.findingsSummary,
    SlideType.checklist,
    SlideType.scopeMatrix,
    SlideType.signOff,
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

  /// The types the picker may offer: every registered type, minus the
  /// Informatieveiligheid types while the module is not revealed. Derived from
  /// [slideTypeMeta] so a new type shows up automatically.
  Iterable<SlideType> _availableTypes() => slideTypeMeta.keys.where(
    (t) =>
        widget.revealSecurityModule ||
        t.category != SlideCategory.informatieveiligheid,
  );

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
      case SlideCategory.algemeen:
        return l10n.d('Algemeen');
      case SlideCategory.informatieveiligheid:
        return l10n.d('Informatieveiligheid');
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
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tab in tabs)
            ChoiceChip(
              label: Text(tab.label),
              selected: _activeCategory == tab.category,
              onSelected: (_) => setState(() => _activeCategory = tab.category),
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
              autofocus: i == 0,
              onTap: () => Navigator.pop(context, types[i]),
            ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final SlideType type;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  const _TypeCard({
    required this.type,
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus,
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
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 11, height: 1.15),
              ),
            ],
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
        // Horizontal rail with four nodes and cards alternating above/below.
        canvas.drawLine(
          const Offset(18, 45),
          const Offset(146, 45),
          _paint(_accent)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
        const xs = [26.0, 66.0, 106.0, 142.0];
        for (var i = 0; i < xs.length; i++) {
          final x = xs[i];
          final above = i.isEven;
          final cardY = above ? 12.0 : 56.0;
          _bar(canvas, x - 16, cardY, 32, 22, _fill, radius: 3);
          _bar(canvas, x - 12, cardY + 4, 14, 5, _accent, radius: 2);
          _bar(canvas, x - 12, cardY + 12, 22, 4, _soft, radius: 2);
          canvas.drawLine(
            Offset(x, 45),
            Offset(x, above ? 34 : 56),
            _paint(_accent.withValues(alpha: 0.4))..strokeWidth = 1.5,
          );
          canvas.drawCircle(
            Offset(x, 45),
            6,
            _paint(_accent.withValues(alpha: 0.18)),
          );
          canvas.drawCircle(Offset(x, 45), 4, _paint(_accent));
          canvas.drawCircle(
            Offset(x, 45),
            4,
            _paint(_ink)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
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
      case SlideType.finding:
      case SlideType.findingsSummary:
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.signOff:
        _paintSecurityWireframe(canvas, type);
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
      default:
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
