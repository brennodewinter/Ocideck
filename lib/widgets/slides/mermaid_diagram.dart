import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  /// Verticale scrolpositie voor een diagram dat te hoog is om leesbaar te passen
  /// (#872). Blijft ongebruikt zolang het diagram gewoon past.
  final ScrollController _scrollController = ScrollController();

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
      // Nieuwe inhoud: terug naar de bovenkant, ook bij een gedeelde
      // presentatie-controller — anders begint een volgende dia op de oude
      // scrollpositie (#872).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller =
            MermaidRenderScope.controllerOf(context) ?? _scrollController;
        if (controller.hasClients) controller.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  /// Kiest tussen passend tonen en scrollen (#868/#872).
  ///
  /// Past het diagram op volle breedte binnen het kader, dan tonen we het gewoon
  /// passend. Is het daarvoor te hoog, dan hangt het van de context af: op een
  /// interactief oppervlak (editor, presentatie) tonen we het op leesbare volle
  /// breedte in een vast-hoog scrollvenster; op een statisch oppervlak (export,
  /// rasteraar, publieksvenster) kan er niet gescrold worden, dus schalen we het
  /// hele diagram passend omlaag — liever klein-maar-heel dan afgesneden.
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
    // Een gedeelde controller (presentatie) wint van de eigen; zo kan de
    // presentator de scrollpositie naar het publiek spiegelen (#872). Werkt voor
    // beide assen — de gedeelde offset gaat als fractie, richting-onafhankelijk.
    final controller =
        MermaidRenderScope.controllerOf(context) ?? _scrollController;

    final Widget content;
    if (scrollable && naturalHeight != null && naturalHeight > maxH) {
      // Te hoog én interactief: leesbaar op volle breedte, verticaal scrollen
      // binnen een vast-hoog venster. Zo blijft het kader even hoog als bij een
      // passend diagram en trekt de slide-FittedBox de rest niet mee omlaag.
      content = SizedBox(
        height: maxH,
        child: SingleChildScrollView(
          controller: controller,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1.0,
            child: SvgPicture.string(
              safe,
              fit: BoxFit.contain,
              width: maxW,
              height: naturalHeight,
            ),
          ),
        ),
      );
    } else if (scrollable &&
        naturalHeight != null &&
        naturalHeight < minH &&
        aspect != null) {
      // Te breed/dun én interactief: leesbaar op volle hoogte (maxH), horizontaal
      // scrollen. Het venster blijft even hoog als een passend diagram; de
      // tekening loopt naar rechts en is af te scrollen.
      content = SizedBox(
        height: maxH,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: controller,
          child: SvgPicture.string(
            safe,
            fit: BoxFit.contain,
            width: maxH * aspect,
            height: maxH,
          ),
        ),
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

/// Geeft aan een subboom door of een mermaid-diagram mag scrollen (#872).
///
/// Scrollen is bewust *opt-in*: de standaard is passend verkleinen (het hele
/// diagram zichtbaar), zoals overal — thumbnails, de slidestrook, dialogen, de
/// export-rasteraar. Alleen de grote interactieve previews (het editor-
/// previewpaneel, het play-scherm) zetten het aan, zodat een te groot diagram
/// dáár leesbaar op volle breedte in een scrollvenster komt in plaats van tot
/// een postzegel te verkleinen. Zo kan een klein oppervlak nooit per ongeluk een
/// half, weggescrold diagram tonen.
class MermaidRenderScope extends InheritedWidget {
  const MermaidRenderScope({
    super.key,
    required this.scrollable,
    this.controller,
    required super.child,
  });

  final bool scrollable;

  /// Optionele externe scroll-controller (#872). Zet de presentatie in om de
  /// scrollpositie te delen: de presentator luistert erop en zendt de offset naar
  /// het publieksvenster, dat zijn eigen controller op die offset zet. Zonder dit
  /// gebruikt elk diagram zijn eigen interne controller (editor/losse preview).
  final ScrollController? controller;

  /// De dichtstbijzijnde waarde, of `false` als er geen scope boven staat —
  /// passend verkleinen is de veilige standaard.
  static bool scrollableOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MermaidRenderScope>();
    return scope?.scrollable ?? false;
  }

  /// De gedeelde scroll-controller voor dit oppervlak, of `null` als er geen is.
  static ScrollController? controllerOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MermaidRenderScope>();
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(MermaidRenderScope oldWidget) =>
      scrollable != oldWidget.scrollable || controller != oldWidget.controller;
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
