import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/app_localizations.dart';
import '../../models/page_size.dart';
import '../../models/settings.dart' show ThemeProfile;
import '../../services/document_pagination.dart';
import '../../theme/app_theme.dart';
import '../document_page_chrome.dart';
import 'document_markdown_view.dart';

/// Millimeters naar beeldpunten. 96 dpi is de CSS-referentie (1 inch = 96 px),
/// dus dit is dezelfde maat als waarin de HTML-export haar pagina uitmeet — een
/// A4 wordt hier net zo breed als daar.
const double kPxPerMm = 96 / 25.4;

/// Toont een document als échte pagina's: op maat, met de gekozen marges, een
/// kop- en voetband per pagina en een paginanummer.
///
/// Waarom niet gewoon een lange rol met een streepje erin: een pagina-einde
/// bepaalt wat er nog nét op de bladzijde komt, en dat is precies wat je bij
/// het schrijven wilt zien. De einden worden daarom niet geschat maar gemeten —
/// het document wordt één keer doorlopend gerenderd, de blokhoogtes worden
/// opgenomen, en [documentPageOffsets] bepaalt daarmee waar de vellen breken.
///
/// De drukkersafloop ([PageMargins.bleedMm]) wordt getoond als een rand rondom
/// het snijformaat, met een snijlijn erlangs: zo zie je wat de drukker wegsnijdt
/// zonder dat je het hoeft voor te stellen.
class PagedDocumentView extends StatefulWidget {
  const PagedDocumentView({
    super.key,
    required this.markdown,
    required this.pageSize,
    required this.margins,
    this.profile,
    this.projectPath,
    this.scale = 1.0,
  });

  final String markdown;
  final PageSizeSpec pageSize;
  final PageMargins margins;
  final ThemeProfile? profile;
  final String? projectPath;

  /// Zoomfactor op het vel. 1,0 is ware grootte op een 96-dpi scherm.
  final double scale;

  @override
  State<PagedDocumentView> createState() => _PagedDocumentViewState();
}

class _PagedDocumentViewState extends State<PagedDocumentView> {
  /// De gemeten hoogte per blok, of `null` zolang er nog niet gemeten is. Tot
  /// dat moment staat er een meetopstelling buiten beeld in plaats van een
  /// weergave.
  List<double>? _blockHeights;

  /// De hoogtes die tijdens de meetronde binnenkomen, op blokvolgorde.
  final Map<int, double> _measuring = {};

  @override
  void didUpdateWidget(PagedDocumentView old) {
    super.didUpdateWidget(old);
    // Andere tekst of een ander vel betekent opnieuw meten; de oude einden
    // slaan dan nergens meer op.
    if (widget.markdown != old.markdown ||
        widget.pageSize != old.pageSize ||
        widget.margins != old.margins ||
        widget.profile != old.profile) {
      _blockHeights = null;
      _measuring.clear();
    }
  }

  /// De papierkleur van het vel: die van het stijlprofiel wanneer er een is —
  /// dezelfde die `DocumentMarkdownView` op het tekstvlak zet — en anders de
  /// themakleur, zodat het vel in donkere modus meedimt.
  Color get _paperColor {
    final background = widget.profile?.slideBackgroundColor;
    if (background == null || background.isEmpty) return AppTheme.paper;
    return AppTheme.parseHexColor(background, fallback: AppTheme.paper);
  }

  (double width, double height) get _sheetPx {
    final (w, h) = widget.pageSize.dimensions;
    final bleed = widget.margins.bleedMm * 2;
    return ((w + bleed) * kPxPerMm, (h + bleed) * kPxPerMm);
  }

  double get _contentWidthPx {
    final (w, _) = widget.pageSize.dimensions;
    return (w - widget.margins.leftMm - widget.margins.rightMm) * kPxPerMm;
  }

  double get _contentHeightPx {
    final (_, h) = widget.pageSize.dimensions;
    return (h - widget.margins.topMm - widget.margins.bottomMm) * kPxPerMm;
  }

  @override
  Widget build(BuildContext context) {
    final heights = _blockHeights;
    final document = DocumentMarkdownView(
      widget.markdown,
      maxTextWidth: null,
      themeProfile: widget.profile,
      chartTheme: widget.profile,
    );
    if (heights == null) return _measure();
    final offsets = documentPageOffsets(
      blockHeights: heights,
      pageHeight: _contentHeightPx,
    );
    return SingleChildScrollView(
      child: Center(
        child: Column(
          children: [
            const SizedBox(height: 16),
            for (var i = 0; i < offsets.length; i++) ...[
              _sheet(
                context,
                document,
                offsets[i],
                // Waar dít vel ophoudt: bij het begin van het volgende, niet
                // een volle paginahoogte verder. Een blok dat niet meer paste
                // is doorgeschoven, en dan hoort de onderkant van dit vel wit
                // te blijven in plaats van de eerste regels van dat blok
                // doormidden te tonen.
                i + 1 < offsets.length
                    ? offsets[i + 1] - offsets[i]
                    : _contentHeightPx,
                i + 1,
                offsets.length,
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  /// Rendert het document één keer buiten beeld op de tekstbreedte van de
  /// pagina, met een meter om elk blok. Buiten het venster in plaats van in een
  /// `Offstage`: die meet zijn kind niet gegarandeerd uit, en zonder meting
  /// komt er nooit een pagina.
  Widget _measure() {
    final blockCount = DocumentMarkdownView.blockTexts(widget.markdown).length;
    return ClipRect(
      child: Stack(
        children: [
          const SizedBox.expand(),
          Positioned(
            left: -1e5,
            top: 0,
            width: _contentWidthPx,
            child: IgnorePointer(
              child: DocumentMarkdownView(
                widget.markdown,
                maxTextWidth: null,
                themeProfile: widget.profile,
                chartTheme: widget.profile,
                blockWrapper: (index, block) => _MeasuredBlock(
                  index: index,
                  onMeasured: (i, height) => _onMeasured(i, height, blockCount),
                  child: block,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onMeasured(int index, double height, int blockCount) {
    if (!mounted || _blockHeights != null) return;
    _measuring[index] = height;
    if (_measuring.length < blockCount) return;
    setState(() {
      _blockHeights = [for (var i = 0; i < blockCount; i++) _measuring[i] ?? 0];
    });
  }

  /// Eén vel: papier, afloopmarkering, kop- en voetband en het venster op het
  /// doorlopende document dat op deze pagina hoort.
  Widget _sheet(
    BuildContext context,
    Widget document,
    double offset,
    double windowHeight,
    int pageNumber,
    int pageCount,
  ) {
    final (sheetW, sheetH) = _sheetPx;
    final bleedPx = widget.margins.bleedMm * kPxPerMm;
    final theme = Theme.of(context);
    final profile = widget.profile;
    final page = Container(
      width: sheetW,
      height: sheetH,
      decoration: BoxDecoration(
        // Hetzelfde papier als waar de tekst op staat. Niet hardgecodeerd wit
        // (dan staat er in donkere modus een verblindend blok), maar ook niet
        // blind de themakleur: is er een stijlprofiel, dan schildert de
        // weergave het tekstvlak met de achtergrond daaruit, en een vel met een
        // andere kleur rand dan midden is geen vel meer.
        color: _paperColor,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // De kop- en voetband staan ín de marge, niet in het tekstvlak.
          // Zo hoort het op papier — en het is bovendien de enige plek waar ze
          // kúnnen staan: hingen ze boven en onder de tekst in dezelfde kolom,
          // dan aten ze hoogte op waar de paginaverdeling al over had beschikt,
          // en verdween er onderaan elk vel een stuk tekst dat nergens meer
          // terugkwam.
          if (profile != null) ...[
            Positioned(
              left: bleedPx,
              right: bleedPx,
              top: bleedPx,
              height: widget.margins.topMm * kPxPerMm,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: DocumentChromeBand(
                  profile: profile,
                  header: true,
                  pageLabel: '$pageNumber',
                  projectPath: widget.projectPath,
                  compact: true,
                ),
              ),
            ),
            Positioned(
              left: bleedPx,
              right: bleedPx,
              bottom: bleedPx,
              height: widget.margins.bottomMm * kPxPerMm,
              child: Align(
                alignment: Alignment.topCenter,
                child: DocumentChromeBand(
                  profile: profile,
                  header: false,
                  pageLabel: '$pageNumber',
                  projectPath: widget.projectPath,
                  compact: true,
                ),
              ),
            ),
          ],
          Positioned(
            left: (widget.margins.leftMm * kPxPerMm) + bleedPx,
            top: (widget.margins.topMm * kPxPerMm) + bleedPx,
            width: _contentWidthPx,
            // Precies het stuk document dat op dit vel hoort: niet een volle
            // paginahoogte, maar tot waar het volgende vel begint.
            height: windowHeight,
            child: ClipRect(
              // Met een sleutel: dit is hét venster op het document, en een
              // toets moet het kunnen aanwijzen zonder per ongeluk een van de
              // andere clips in de boom te pakken.
              key: const Key('document-page-window'),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(0, -offset),
                  child: SizedBox(width: _contentWidthPx, child: document),
                ),
              ),
            ),
          ),
          if (widget.margins.hasBleed)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(bleedPx),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Semantics(
      label: context.l10n
          .d('Pagina {n} van {m}')
          .replaceAll('{n}', '$pageNumber')
          .replaceAll('{m}', '$pageCount'),
      child: Transform.scale(
        scale: widget.scale,
        alignment: Alignment.topCenter,
        child: page,
      ),
    );
  }
}

/// Meet de hoogte van één documentblok en meldt hem terug.
///
/// Per blok, niet in één keer over de hele kolom: tijdens een layout mag een
/// render-object alleen zijn *eigen* maat lezen, niet die van een kleinkind.
/// Elk blok meet dus zichzelf.
class _MeasuredBlock extends SingleChildRenderObjectWidget {
  const _MeasuredBlock({
    required this.index,
    required this.onMeasured,
    required super.child,
  });

  final int index;
  final void Function(int index, double height) onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredBlock(index, onMeasured);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuredBlock renderObject,
  ) => renderObject
    ..index = index
    ..onMeasured = onMeasured;
}

class _RenderMeasuredBlock extends RenderProxyBox {
  _RenderMeasuredBlock(this.index, this.onMeasured);

  int index;
  void Function(int index, double height) onMeasured;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size.height;
    // Ná de frame melden: een setState tijdens de layout mag niet.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => onMeasured(index, measured),
    );
  }
}
