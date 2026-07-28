import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/app_localizations.dart';
import '../../services/mermaid_render_service.dart';
import '../../utils/sanitize_svg.dart';

/// Zet Mermaid-brontekst om in SVG-opmaak, of `null` als dat niet lukt.
/// Standaard de gedeelde [MermaidRenderService].
///
/// Eén dunne indirectie, in hetzelfde patroon als `FileService.saveDestination`:
/// de renderer draait op een verborgen [WebView] die onder `flutter test` niet
/// bestaat, en zonder deze naad is alles eráchter onbereikbaar — het opschonen
/// van de SVG, het kader eromheen, en de terugval op de brontekst wanneer de
/// opmaak wordt geweigerd.
typedef MermaidRenderer = Future<String?> Function(String source);

/// De grootste zoomfactor voor een mermaid-diagram in de presentatie.
const double kMermaidMaxZoom = 5.0;

/// Harde ondergrens voor de controller (voorkomt nul/negatief). De echte
/// ondergrens is per diagram de passend-in-het-venster-factor ([mermaidFitScale]),
/// die de widget afdwingt; deze is alleen een vangnet ver onder elk realistisch
/// geval.
const double kMermaidMinZoom = 0.02;

/// De zoomfactor waarbij het héle diagram in het venster past — kleiner dan 1
/// voor een diagram dat op leesbare maat groter is dan het venster (dan kun je
/// uitzoomen tot het overzicht). Nooit boven 1: een diagram dat al past hoeft
/// niet verkleind te worden. Puur, zodat het los te toetsen is.
double mermaidFitScale(double vw, double vh, double childW, double childH) {
  if (childW <= 0 || childH <= 0) return 1.0;
  return math.min(1.0, math.min(vw / childW, vh / childH));
}

/// De genormaliseerde kijkstand van een groot mermaid-diagram: zoomfactor plus
/// de fractie van het diagram die linksboven in beeld staat. Bewust
/// *maat-onafhankelijk* (geen pixels): het presentatiescherm en de beamer hebben
/// een andere pixelmaat, maar dezelfde fractie wijst op beide naar hetzelfde
/// punt. Zo kan de presentator zijn zoom én scrollpositie naar het publieksscherm
/// spiegelen (#930, opvolger van de scroll-only spiegeling van #872).
class MermaidViewController extends ChangeNotifier {
  double _scale = 1.0;
  double _fx = 0.0;
  double _fy = 0.0;

  /// Zoomfactor. 1 = leesbare volle breedte; groter = inzoomen; kleiner dan 1 =
  /// uitzoomen tot het hele diagram past (#944).
  double get scale => _scale;

  /// Kind-fractie (0..1) die aan de linkerrand van het venster staat.
  double get fx => _fx;

  /// Kind-fractie (0..1) die aan de bovenrand van het venster staat.
  double get fy => _fy;

  void set({required double scale, required double fx, required double fy}) {
    // Ondergrens is de vangnet-factor; de widget klemt op de echte passend-maat
    // (zodat je kunt uitzoomen tot het hele diagram past, #944).
    final s = scale.isNaN ? 1.0 : scale.clamp(kMermaidMinZoom, kMermaidMaxZoom);
    final nx = fx.isNaN ? 0.0 : fx.clamp(0.0, 1.0);
    final ny = fy.isNaN ? 0.0 : fy.clamp(0.0, 1.0);
    if (s == _scale && nx == _fx && ny == _fy) return;
    _scale = s;
    _fx = nx;
    _fy = ny;
    notifyListeners();
  }

  void reset() => set(scale: 1.0, fx: 0.0, fy: 0.0);

  // De laatst bekende venster- en (ongeschaalde) kindmaat van het zoombare
  // venster. Puur geometrie, geen kijkstand — dit notificeert dus niet. Het
  // zoombare venster zet ze bij elke layout; zo kan [zoomBy] hetzelfde
  // midden-vasthoudend zoomen als de knoppen, óók vanaf een plek die die maten
  // zelf niet kent (de toetsenbord-zoom in de presentatie, #930).
  double _vw = 0, _vh = 0, _childW = 0, _childH = 0;

  void setMetrics({
    required double vw,
    required double vh,
    required double childW,
    required double childH,
  }) {
    _vw = vw;
    _vh = vh;
    _childW = childW;
    _childH = childH;
  }

  /// Zoomt met [factor] rond het midden van het venster, met de laatst bekende
  /// maten. Geeft terug óf er een zoombaar diagram in beeld was: zonder maten
  /// (geen groot diagram op de dia) gebeurt er niets en telt de toets niet als
  /// afgehandeld, zodat hij niet stilletjes wordt opgeslokt. Bij de zoomgrens
  /// verandert de stand niet, maar de toets geldt wél als afgehandeld — je
  /// stáát dan immers op een zoombaar diagram.
  bool zoomBy(double factor) {
    if (_childW <= 0 || _childH <= 0 || _vw <= 0 || _vh <= 0) return false;
    final next = mermaidZoomAroundCentre(
      (scale: _scale, fx: _fx, fy: _fy),
      factor: factor,
      vw: _vw,
      vh: _vh,
      childW: _childW,
      childH: _childH,
    );
    set(scale: next.scale, fx: next.fx, fy: next.fy);
    return true;
  }
}

/// De `Matrix4` voor een [InteractiveViewer] die het diagram op zoomfactor
/// [scale] toont met kind-fractie ([fx], [fy]) linksboven, gegeven de
/// ongeschaalde kindmaat. Puur, zodat de rekenkern los te toetsen is.
///
/// De transform beeldt een kindpunt `p` af op `scale·p + t`, met
/// `t = -scale·fractie·kindmaat`; het kindpunt op `fractie·kindmaat` landt dan
/// precies op de vensterrand (0).
Matrix4 mermaidViewMatrix(
  double scale,
  double fx,
  double fy,
  double childW,
  double childH,
) {
  // Onder 1 mag: uitzoomen tot het hele diagram past (#944). Alleen nul/negatief
  // en NaN vangen we af.
  final s = (scale.isNaN || scale <= 0) ? 1.0 : scale;
  // Rechtstreeks gezet (kolom-major: schaal op de diagonaal, translatie in
  // kolom 3), zodat we niet op de afgekeurde `translate`/`scale`-bouwers leunen.
  return Matrix4.identity()
    ..setEntry(0, 0, s)
    ..setEntry(1, 1, s)
    ..setEntry(2, 2, s)
    ..setEntry(0, 3, -s * fx * childW)
    ..setEntry(1, 3, -s * fy * childH);
}

/// De genormaliseerde kijkstand terug uit een [InteractiveViewer]-matrix. De
/// inverse van [mermaidViewMatrix]; puur en los getoetst.
({double scale, double fx, double fy}) mermaidViewNormalized(
  Matrix4 m,
  double childW,
  double childH,
) {
  final s = m.getMaxScaleOnAxis();
  final t = m.getTranslation();
  final fx = (childW > 0 && s > 0) ? (-t.x / (s * childW)) : 0.0;
  final fy = (childH > 0 && s > 0) ? (-t.y / (s * childH)) : 0.0;
  return (scale: s, fx: fx, fy: fy);
}

/// Zoomt [view] met [factor] rond het midden van het venster en houdt de rest
/// binnen het diagram. Puur, zodat de knop-zoom los te toetsen is. [vw]/[vh] is
/// de venstermaat, [childW]/[childH] de ongeschaalde diagrammaat.
({double scale, double fx, double fy}) mermaidZoomAroundCentre(
  ({double scale, double fx, double fy}) view, {
  required double factor,
  required double vw,
  required double vh,
  required double childW,
  required double childH,
}) {
  double visible(double scale, double viewport, double child) =>
      (child <= 0 || scale <= 0)
      ? 1.0
      : (viewport / (scale * child)).clamp(0.0, 1.0);
  double clampFraction(double f, double vis) =>
      f.clamp(0.0, (1.0 - vis).clamp(0.0, 1.0));

  final visX = visible(view.scale, vw, childW);
  final visY = visible(view.scale, vh, childH);
  // Kind-fractie in het midden van het venster; die houden we vast.
  final centreX = view.fx + visX / 2;
  final centreY = view.fy + visY / 2;

  // Ondergrens is de passend-maat (#944): uitzoomen mag tot het hele diagram
  // in het venster past, niet slechts tot leesbare volle breedte.
  final fit = mermaidFitScale(vw, vh, childW, childH);
  final target = (view.scale * factor).clamp(fit, kMermaidMaxZoom);
  final visX2 = visible(target, vw, childW);
  final visY2 = visible(target, vh, childH);
  return (
    scale: target,
    fx: clampFraction(centreX - visX2 / 2, visX2),
    fy: clampFraction(centreY - visY2 / 2, visY2),
  );
}

/// Klemt een kijkstand binnen het toelaatbare: zoom tussen de passend-maat en
/// het maximum, en de fracties zo dat de inhoud in beeld blijft. Puur. Nodig
/// omdat [InteractiveViewer] met een onbegrensde `boundaryMargin` zelf niet meer
/// klemt (#944) — die grens bewaken we hier.
({double scale, double fx, double fy}) mermaidClampView(
  ({double scale, double fx, double fy}) view, {
  required double vw,
  required double vh,
  required double childW,
  required double childH,
}) {
  final fit = mermaidFitScale(vw, vh, childW, childH);
  final scale = view.scale.clamp(fit, kMermaidMaxZoom);
  double visible(double viewport, double child) => (child <= 0 || scale <= 0)
      ? 1.0
      : (viewport / (scale * child)).clamp(0.0, 1.0);
  double clampFraction(double f, double vis) =>
      f.clamp(0.0, (1.0 - vis).clamp(0.0, 1.0));
  return (
    scale: scale,
    fx: clampFraction(view.fx, visible(vw, childW)),
    fy: clampFraction(view.fy, visible(vh, childH)),
  );
}

/// Renders a Mermaid diagram definition as inline SVG in slide previews.
class MermaidDiagram extends StatefulWidget {
  final String source;
  final double width;

  /// Zie [MermaidRenderer]. `null` betekent: de gedeelde renderdienst.
  final MermaidRenderer? renderer;

  const MermaidDiagram({
    super.key,
    required this.source,
    required this.width,
    this.renderer,
  });

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  late Future<String?> _svgFuture;

  /// Eigen kijk-controller wanneer er geen gedeelde boven staat (buiten de
  /// presentatie): dan zoomt/scrollt het diagram nog steeds, alleen zonder
  /// spiegeling naar een tweede scherm.
  final MermaidViewController _localView = MermaidViewController();

  MermaidRenderer get _render =>
      widget.renderer ?? MermaidRenderService.instance.render;

  @override
  void initState() {
    super.initState();
    _svgFuture = _render(widget.source);
  }

  @override
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _svgFuture = _render(widget.source);
      // Nieuwe inhoud: terug naar de bovenkant én naar zoomfactor 1, ook bij een
      // gedeelde presentatie-controller — anders begint een volgende dia op de
      // oude kijkstand (#872/#930).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (MermaidRenderScope.viewControllerOf(context) ?? _localView).reset();
      });
    }
  }

  @override
  void dispose() {
    _localView.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _svgFuture,
      builder: (context, snapshot) {
        final svg = snapshot.data;
        if (svg != null) {
          final safe = sanitizeMermaidSvg(svg);
          if (safe != null) {
            return _buildDiagram(context, safe);
          }
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: widget.width * 0.02),
            child: Center(
              child: SizedBox(
                width: widget.width * 0.04,
                height: widget.width * 0.04,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _fallbackCode();
      },
    );
  }

  /// Kiest tussen passend tonen, en zoombaar/scrollbaar tonen (#868/#872/#930).
  ///
  /// Past het diagram op volle breedte binnen het kader, dan tonen we het gewoon
  /// passend. Is het te hoog of te breed, dan hangt het van de context af: op een
  /// interactief oppervlak (presentatie) tonen we het op leesbare maat in een
  /// zoombaar/verschuifbaar venster; op een statisch oppervlak (export,
  /// rasteraar, publieksvenster zonder controller) kan er niet gezoomd worden,
  /// dus schalen we het hele diagram passend omlaag — liever klein-maar-heel dan
  /// afgesneden.
  Widget _buildDiagram(BuildContext context, String safe) {
    final w = widget.width;
    final maxW = w * 0.84;
    final maxH = w * 0.32;
    // Leesbaarheidsvloer voor de hoogte: een zeer breed diagram (bv. een gantt,
    // viewBox ~1384×148) zou passend maar een dunne strip worden. Zakt de
    // passende hoogte hieronder, dan tonen we het op volle hoogte en scrollen
    // horizontaal (#895), spiegelbeeld van het te-hoge geval.
    final minH = w * 0.16;
    final aspect = _diagramAspectRatio(safe);
    final naturalHeight = (aspect != null && aspect > 0) ? maxW / aspect : null;
    final scrollable = MermaidRenderScope.scrollableOf(context);

    final Widget content;
    if (scrollable && naturalHeight != null && naturalHeight > maxH) {
      // Te hoog én interactief: leesbaar op volle breedte, verticaal zoombaar/
      // verschuifbaar binnen een vast-hoog venster.
      content = _zoomable(
        context,
        safe,
        childW: maxW,
        childH: naturalHeight,
        viewportH: maxH,
      );
    } else if (scrollable &&
        naturalHeight != null &&
        naturalHeight < minH &&
        aspect != null) {
      // Te breed/dun én interactief: leesbaar op volle hoogte (maxH), horizontaal
      // zoombaar/verschuifbaar.
      content = _zoomable(
        context,
        safe,
        childW: maxH * aspect,
        childH: maxH,
        viewportH: maxH,
      );
    } else {
      // Past binnen het kader, of statisch oppervlak: passend (zoals #868).
      final size = _fittedDiagramSize(safe, w);
      content = Center(
        heightFactor: 1.0,
        child: SvgPicture.string(
          safe,
          fit: BoxFit.contain,
          width: size.width,
          height: size.height,
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: w * 0.008),
      padding: EdgeInsets.all(w * 0.012),
      decoration: BoxDecoration(
        color: AppTheme.nearWhite,
        borderRadius: BorderRadius.circular(w * 0.008),
        border: Border.all(color: AppTheme.ghBorder),
      ),
      child: content,
    );
  }

  Widget _zoomable(
    BuildContext context,
    String safe, {
    required double childW,
    required double childH,
    required double viewportH,
  }) {
    // Een gedeelde controller (presentatie) wint van de eigen; zo kan de
    // presentator de kijkstand naar het publiek spiegelen (#930). De beamer
    // toont alleen mee: interactie staat daar uit.
    final shared = MermaidRenderScope.viewControllerOf(context);
    return _ZoomableMermaid(
      svg: safe,
      childW: childW,
      childH: childH,
      viewportH: viewportH,
      controller: shared ?? _localView,
      interactive: MermaidRenderScope.interactiveOf(context),
      buttonSize: widget.width * 0.04,
    );
  }

  Widget _fallbackCode() {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: widget.width * 0.008),
      padding: EdgeInsets.all(widget.width * 0.018),
      decoration: BoxDecoration(
        color: AppTheme.ghSurface,
        borderRadius: BorderRadius.circular(widget.width * 0.008),
        border: Border.all(color: AppTheme.ghBorder),
      ),
      child: Text(
        widget.source,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: widget.width * 0.02,
          height: 1.3,
          color: AppTheme.ghInk,
        ),
      ),
    );
  }
}

/// Het zoombare/verschuifbare venster om een groot diagram (#930). Houdt een
/// eigen [TransformationController] voor de [InteractiveViewer] en
/// synchroniseert die met de genormaliseerde [MermaidViewController] — beide
/// kanten op, met een vlag tegen terugkoppeling — zodat de presentator zijn
/// kijkstand deelt en de beamer meebeweegt.
class _ZoomableMermaid extends StatefulWidget {
  final String svg;
  final double childW;
  final double childH;
  final double viewportH;
  final MermaidViewController controller;
  final bool interactive;
  final double buttonSize;

  const _ZoomableMermaid({
    required this.svg,
    required this.childW,
    required this.childH,
    required this.viewportH,
    required this.controller,
    required this.interactive,
    required this.buttonSize,
  });

  @override
  State<_ZoomableMermaid> createState() => _ZoomableMermaidState();
}

class _ZoomableMermaidState extends State<_ZoomableMermaid> {
  final TransformationController _tc = TransformationController();
  bool _applyingRemote = false;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onLocalChanged);
    widget.controller.addListener(_onSharedChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyShared());
  }

  @override
  void didUpdateWidget(_ZoomableMermaid old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onSharedChanged);
      old.controller.setMetrics(vw: 0, vh: 0, childW: 0, childH: 0);
      widget.controller.addListener(_onSharedChanged);
    }
    // Een nieuwe kindmaat (andere dia/diagram) betekent een andere matrix voor
    // dezelfde kijkstand: opnieuw toepassen.
    if (old.childW != widget.childW || old.childH != widget.childH) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyShared());
    }
  }

  @override
  void dispose() {
    _tc.removeListener(_onLocalChanged);
    widget.controller.removeListener(_onSharedChanged);
    // Geen zoombaar diagram meer in beeld: wis de maten, zodat een
    // toetsenbord-zoom op een volgende dia zonder groot diagram niets doet in
    // plaats van op een verdwenen diagram in te werken.
    widget.controller.setMetrics(vw: 0, vh: 0, childW: 0, childH: 0);
    _tc.dispose();
    super.dispose();
  }

  void _onSharedChanged() {
    if (!mounted) return;
    _applyShared();
  }

  void _applyShared() {
    final target = mermaidViewMatrix(
      widget.controller.scale,
      widget.controller.fx,
      widget.controller.fy,
      widget.childW,
      widget.childH,
    );
    if (_tc.value == target) return;
    _applyingRemote = true;
    _tc.value = target;
    _applyingRemote = false;
  }

  void _onLocalChanged() {
    if (_applyingRemote) return;
    final n = mermaidViewNormalized(_tc.value, widget.childW, widget.childH);
    // InteractiveViewer klemt zelf niet meer (onbegrensde marge, #944), dus
    // houden we een gebaar hier binnen de grenzen.
    final c = mermaidClampView(
      n,
      vw: _viewport.width,
      vh: _viewport.height,
      childW: widget.childW,
      childH: widget.childH,
    );
    widget.controller.set(scale: c.scale, fx: c.fx, fy: c.fy);
  }

  void _zoomBy(double factor) {
    final current = mermaidViewNormalized(
      _tc.value,
      widget.childW,
      widget.childH,
    );
    final next = mermaidZoomAroundCentre(
      current,
      factor: factor,
      vw: _viewport.width,
      vh: _viewport.height,
      childW: widget.childW,
      childH: widget.childH,
    );
    widget.controller.set(scale: next.scale, fx: next.fx, fy: next.fy);
  }

  /// Passend maken: het hele diagram in één klik in beeld (#944). Uitzoomen tot
  /// de passend-maat, linksboven verankerd zodat alles zichtbaar is.
  void _fitWhole() {
    final fit = mermaidFitScale(
      _viewport.width,
      _viewport.height,
      widget.childW,
      widget.childH,
    );
    widget.controller.set(scale: fit, fx: 0, fy: 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.viewportH,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, widget.viewportH);
          // Deel de maten met de controller, zodat een zoom van elders — de
          // toetsenbord-zoom in de presentatie (#930) — hetzelfde midden
          // vasthoudt als de knoppen hier.
          widget.controller.setMetrics(
            vw: _viewport.width,
            vh: _viewport.height,
            childW: widget.childW,
            childH: widget.childH,
          );
          // Ondergrens = passend in het venster, zodat knijpen/uitzoomen tot het
          // hele diagram past (#944), niet slechts tot leesbare volle breedte.
          final minScale = mermaidFitScale(
            constraints.maxWidth,
            widget.viewportH,
            widget.childW,
            widget.childH,
          );
          final viewer = ClipRect(
            child: InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              panEnabled: widget.interactive,
              scaleEnabled: widget.interactive,
              minScale: minScale,
              maxScale: kMermaidMaxZoom,
              // Onbegrensd: met `EdgeInsets.zero` klemt InteractiveViewer de
              // minimale zoom stil terug op "diagram vult nog het venster" —
              // dan kun je een hoog diagram niet kleiner maken dan volle breedte
              // (#944). Wij bewaken de grenzen zelf in [_onLocalChanged] en de
              // knop-zoom, dus laten we die van InteractiveViewer los.
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: SizedBox(
                width: widget.childW,
                height: widget.childH,
                child: SvgPicture.string(
                  widget.svg,
                  fit: BoxFit.fill,
                  width: widget.childW,
                  height: widget.childH,
                ),
              ),
            ),
          );
          if (!widget.interactive) return viewer;
          return Stack(
            children: [
              Positioned.fill(child: viewer),
              Positioned(
                right: widget.buttonSize * 0.3,
                bottom: widget.buttonSize * 0.3,
                child: _ZoomControls(
                  size: widget.buttonSize,
                  onZoomIn: () => _zoomBy(1.25),
                  onZoomOut: () => _zoomBy(0.8),
                  onReset: _fitWhole,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// De toegankelijke zoomknoppen op een groot diagram: groter, kleiner, en terug
/// naar passend. Naast de knijp- en scrollbediening, zodat zoomen ook zonder
/// trackpad-gebaar lukt (#930).
class _ZoomControls extends StatelessWidget {
  final double size;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.size,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppTheme.nearWhite.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(size * 0.3),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(Icons.add, l10n.d('Inzoomen'), onZoomIn),
            _button(Icons.remove, l10n.d('Uitzoomen'), onZoomOut),
            _button(
              Icons.center_focus_strong,
              l10n.d('Zoom resetten'),
              onReset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: size * 0.6),
      color: AppTheme.ghInk,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}

/// Geeft aan een subboom door of een mermaid-diagram interactief mag zijn
/// (zoombaar/verschuifbaar), en deelt eventueel een kijk-controller (#872/#930).
///
/// Interactie is bewust *opt-in*: de standaard is passend verkleinen (het hele
/// diagram zichtbaar), zoals overal — thumbnails, de slidestrook, dialogen, de
/// export-rasteraar. Alleen de presentatie zet het aan, zodat een te groot
/// diagram dáár leesbaar in een zoombaar venster komt in plaats van tot een
/// postzegel te verkleinen. Zo kan een klein oppervlak nooit per ongeluk een
/// half, weggeschoven diagram tonen.
class MermaidRenderScope extends InheritedWidget {
  const MermaidRenderScope({
    super.key,
    required this.scrollable,
    this.viewController,
    this.interactive = true,
    required super.child,
  });

  final bool scrollable;

  /// Optionele gedeelde kijk-controller (#930). De presentatie zet er één zodat
  /// de presentator zijn zoom/scroll naar het publieksvenster spiegelt; de
  /// beamer luistert erop en toont dezelfde kijkstand. Zonder dit gebruikt elk
  /// diagram zijn eigen interne controller.
  final MermaidViewController? viewController;

  /// Of dit oppervlak gebaren aanneemt en zoomknoppen toont. De presentator: ja;
  /// het publieksvenster: nee (het spiegelt alleen mee).
  final bool interactive;

  /// De dichtstbijzijnde waarde, of `false` als er geen scope boven staat —
  /// passend verkleinen is de veilige standaard.
  static bool scrollableOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MermaidRenderScope>();
    return scope?.scrollable ?? false;
  }

  /// De gedeelde kijk-controller voor dit oppervlak, of `null` als er geen is.
  static MermaidViewController? viewControllerOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MermaidRenderScope>();
    return scope?.viewController;
  }

  /// Of dit oppervlak gebaren/knoppen toont; standaard `true`.
  static bool interactiveOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MermaidRenderScope>();
    return scope?.interactive ?? true;
  }

  @override
  bool updateShouldNotify(MermaidRenderScope oldWidget) =>
      scrollable != oldWidget.scrollable ||
      viewController != oldWidget.viewController ||
      interactive != oldWidget.interactive;
}

/// De maat waarin het diagram binnen het slidekader past.
///
/// `SvgPicture` met alléén een breedte leidt de hoogte af uit de beeldverhouding
/// en kent geen plafond: een hoge flowchart (veel niveaus) groeit dan onbeperkt
/// door en loopt onder uit de slide (#868). Hier begrenzen we beide maten en
/// schalen we het diagram zo groot mogelijk binnen `maxW × maxH`, met behoud van
/// verhouding. Een breed, laag diagram houdt zijn natuurlijke maat; een hoog
/// diagram schaalt mee omlaag in plaats van eruit te lopen. `maxH` is een
/// fractie van de slidebreedte (net als alle maten hier), zodat de begrenzing
/// meeschaalt met preview, thumbnail en presentatie.
Size _fittedDiagramSize(String svg, double w) {
  final maxW = w * 0.84;
  // Ruim onder de 16:9-hoogte (0.5625·w) blijven: er staat meestal een titel
  // boven het diagram, plus de rand en marge van het kader zelf. Empirisch op de
  // beslisboom-slide teruggebracht tot 0.32, zodat ook de onderste rij knopen
  // binnen het kader valt in plaats van eronder weg te vallen.
  final maxH = w * 0.32;
  final ratio = _diagramAspectRatio(svg);
  if (ratio == null || ratio <= 0) return Size(maxW, maxH);
  var width = maxW;
  var height = width / ratio;
  if (height > maxH) {
    height = maxH;
    width = height * ratio;
  }
  return Size(width, height);
}

/// Breedte/hoogte van het diagram, afgelezen uit de `viewBox`.
///
/// Mermaid zet de echte maten in de `viewBox` (`minX minY breedte hoogte`); de
/// `width`/`height`-attributen zijn `100%` en zeggen niets. `null` als er geen
/// bruikbare `viewBox` is — dan valt de aanroeper terug op het volle kader.
double? _diagramAspectRatio(String svg) {
  final match = RegExp(r'viewBox\s*=\s*"([^"]*)"').firstMatch(svg);
  if (match == null) return null;
  final parts = match.group(1)!.trim().split(RegExp(r'[\s,]+'));
  if (parts.length != 4) return null;
  final width = double.tryParse(parts[2]);
  final height = double.tryParse(parts[3]);
  if (width == null || height == null || height <= 0) return null;
  return width / height;
}
