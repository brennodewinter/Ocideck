import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/document_pagination.dart';

/// De hoogtes van de blokken in de schrijfstand, in de volgorde waarin ze
/// staan.
///
/// Dit is de enige eerlijke bron voor een pagina-einde tijdens het schrijven:
/// het einde hoort te vallen waar het blok dat je aan het typen bent
/// werkelijk eindigt, niet waar een schatting denkt dat het eindigt. Een
/// alinea die één regel langer wordt verschuift het einde meteen mee.
///
/// Leeg wanneer de editor nog niet is uitgemeten — dan valt er niets te
/// tekenen.
List<double> writingBlockHeights(RenderEditor? editor) {
  if (editor == null || !editor.hasSize) return const [];
  final heights = <double>[];
  editor.visitChildren((child) {
    if (child is RenderBox && child.hasSize) heights.add(child.size.height);
  });
  return heights;
}

/// Waar de pagina's breken in de schrijfstand, in de coördinaten van de
/// editor-inhoud. De eerste pagina begint op 0 en levert dus geen lijn op.
List<double> writingPageBreaks({
  required List<double> blockHeights,
  required double pageContentHeight,
}) {
  if (blockHeights.isEmpty || pageContentHeight <= 0) return const [];
  return documentPageOffsets(
    blockHeights: blockHeights,
    pageHeight: pageContentHeight,
  ).skip(1).toList();
}

/// Tekent de pagina-einden over het schrijfoppervlak.
///
/// De tekst loopt door — de schrijfstand is één doorlopende editor, en die in
/// vellen knippen zou het typen, de cursor en het selecteren kapotmaken. Wat
/// hier bij komt is de vraag die een doorlopende rol niet beantwoordt: *wat
/// komt er nog op deze bladzijde?* Vandaar een lijn waar het vel vol is, met
/// het nummer van de pagina die daarna begint.
///
/// De lijnen worden gemeten aan de echte render van de editor, niet aan een
/// tweede opbouw van dezelfde tekst. Ze staan daarmee waar ze in de
/// schrijfstand horen te staan; het exacte afdrukresultaat zie je in de
/// Pagina's-stand, die met de lettermaten van de weergave rekent.
class WritingPageBreakOverlay extends StatefulWidget {
  const WritingPageBreakOverlay({
    super.key,
    required this.editorKey,
    required this.pageContentHeight,
    required this.child,
    this.enabled = true,
  });

  final GlobalKey<EditorState> editorKey;

  /// De hoogte van het tekstvlak van één pagina, in dezelfde eenheid als de
  /// editor tekent (beeldpunten).
  final double pageContentHeight;

  final bool enabled;
  final Widget child;

  @override
  State<WritingPageBreakOverlay> createState() =>
      _WritingPageBreakOverlayState();
}

class _WritingPageBreakOverlayState extends State<WritingPageBreakOverlay> {
  /// De y-posities van de lijnen, in de coördinaten van dit omhulsel — dus
  /// mét de schuifstand erin verrekend.
  final ValueNotifier<List<double>> _lines = ValueNotifier(const []);

  /// De laatst gemeten pagina-einden in de inhoudscoördinaten van de editor.
  /// Bewaard omdat rollen ze niet verandert — alleen waar ze in beeld staan
  /// verandert. De blokken opnieuw uitmeten bij elke schuifstap zou werk zijn
  /// dat niets oplevert.
  List<double> _breaks = const [];

  @override
  void initState() {
    super.initState();
    _scheduleRecompute();
  }

  @override
  void didUpdateWidget(WritingPageBreakOverlay old) {
    super.didUpdateWidget(old);
    _scheduleRecompute();
  }

  @override
  void dispose() {
    _lines.dispose();
    super.dispose();
  }

  void _scheduleRecompute() {
    if (!widget.enabled) {
      _lines.value = const [];
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
  }

  /// Meet de blokken opnieuw en werkt de lijnen bij. Nodig zodra de tekst of de
  /// paginamaat verandert.
  void _remeasure() {
    if (!mounted || !widget.enabled) return;
    _breaks = writingPageBreaks(
      blockHeights: writingBlockHeights(
        widget.editorKey.currentState?.renderEditor,
      ),
      pageContentHeight: widget.pageContentHeight,
    );
    _recompute();
  }

  /// Zet de bekende einden om naar posities in dit omhulsel. Dit is wat er bij
  /// het rollen gebeurt: hetzelfde einde, een andere plek in beeld.
  void _recompute() {
    if (!mounted || !widget.enabled) return;
    final editor = widget.editorKey.currentState?.renderEditor;
    final breaks = _breaks;
    if (breaks.isEmpty || editor == null || !editor.hasSize) {
      _lines.value = const [];
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // Van de inhoudscoördinaten van de editor naar die van dit omhulsel: zo
    // schuiven de lijnen vanzelf mee met de schuifbalk, zonder dat dit
    // omhulsel weet hoe ver er gerold is.
    final origin = box.globalToLocal(editor.localToGlobal(Offset.zero));
    final height = box.size.height;
    final visible = <double>[
      for (final y in breaks)
        if (origin.dy + y >= 0 && origin.dy + y <= height) origin.dy + y,
    ];
    if (!_sameLines(visible, _lines.value)) _lines.value = visible;
  }

  static bool _sameLines(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  /// Het paginanummer dat ná lijn [index] begint. De eerste lijn sluit pagina
  /// 1 af, dus daarachter begint pagina 2.
  int _pageAfter(int index) => index + 2;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final theme = Theme.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _recompute();
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<List<double>>(
                valueListenable: _lines,
                builder: (context, lines, _) => CustomPaint(
                  painter: _PageBreakPainter(
                    lines: lines,
                    color: theme.colorScheme.outline,
                    labels: [
                      for (var i = 0; i < lines.length; i++)
                        _pageLabel(theme, _pageAfter(i)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Het paginanummer als geschilderde tekst. Los opgebouwd zodat de schilder
  /// alleen nog hoeft te tekenen.
  TextPainter _pageLabel(ThemeData theme, int page) => TextPainter(
    text: TextSpan(
      // Alleen een cijfer: het wóórd "pagina" erbij zou hier per taal moeten
      // worden vertaald voor een label van vier millimeter breed, en het cijfer
      // op een pagina-einde spreekt voor zich.
      text: '$page',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

class _PageBreakPainter extends CustomPainter {
  _PageBreakPainter({
    required this.lines,
    required this.labels,
    required this.color,
  });

  final List<double> lines;
  final List<TextPainter> labels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i < lines.length; i++) {
      final y = lines[i];
      // Streepjes, geen doorgetrokken lijn: een volle streep leest als een
      // horizontale regel in het document zelf, en dat is dit niet.
      for (var x = 0.0; x < size.width - 24; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
      }
      final label = labels[i];
      label.paint(canvas, Offset(size.width - label.width - 2, y + 2));
    }
  }

  @override
  bool shouldRepaint(_PageBreakPainter old) =>
      old.lines != lines || old.color != color;
}
