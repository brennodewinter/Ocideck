import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../utils/text_search.dart';

/// Meet de echte tekstregels, zodat lange alinea's en tabelcellen op dezelfde
/// manier bereikbaar zijn. Een bloktint alleen wijst geen voorkomen aan.
class DocumentSearchOverlay extends StatefulWidget {
  const DocumentSearchOverlay({
    super.key,
    required this.child,
    required this.query,
    required this.activeIndex,
    this.caseSensitive = false,
    this.onActiveRect,
    this.revealSignal = 0,
    this.revealIntoView = false,
    this.geometry,
    this.measure = true,
    this.paintBounds,
  });

  /// Zichtbare paginakopieën tekenen de gedeelde meting zonder opnieuw te zoeken.
  final DocumentSearchGeometry? geometry;
  final bool measure;
  final Rect? paintBounds;
  final bool revealIntoView;
  final int revealSignal;
  final Widget child;
  final String query;
  final int activeIndex;
  final bool caseSensitive;
  final ValueChanged<Rect?>? onActiveRect;

  @override
  State<DocumentSearchOverlay> createState() => _DocumentSearchOverlayState();
}

class _DocumentSearchOverlayState extends State<DocumentSearchOverlay> {
  final _content = GlobalKey();
  final _activeHighlight = GlobalKey();
  int _revealedSignal = 0;
  List<Rect> _boxes = const [];

  @override
  void initState() {
    super.initState();
    if (!widget.measure) widget.geometry?.addListener(_geometryChanged);
  }

  @override
  void didUpdateWidget(DocumentSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.geometry != widget.geometry ||
        oldWidget.measure != widget.measure) {
      oldWidget.geometry?.removeListener(_geometryChanged);
      if (!widget.measure) widget.geometry?.addListener(_geometryChanged);
    }
  }

  List<Rect> _paintedBoxes = const [];

  List<Rect> get _paintBoxes {
    final boxes = widget.geometry?.boxes ?? _boxes;
    final bounds = widget.paintBounds;
    return bounds == null
        ? boxes
        : boxes.where((box) => box.overlaps(bounds)).toList();
  }

  void _geometryChanged() {
    final boxes = _paintBoxes;
    if (mounted &&
        (!_sameRects(boxes, _paintedBoxes) ||
            (boxes.isNotEmpty && widget.geometry?.pendingReveal == true))) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.geometry?.removeListener(_geometryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.measure) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
    final boxes = _paintBoxes;
    _paintedBoxes = boxes;
    if (!widget.measure) _revealBoxes(boxes);
    return Stack(
      children: [
        KeyedSubtree(
          key: _content,
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              if (widget.measure) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
              }
              return false;
            },
            child: widget.child,
          ),
        ),
        for (var i = 0; i < boxes.length; i++)
          Positioned.fromRect(
            rect: boxes[i].inflate(2),
            child: IgnorePointer(
              key: i == 0 ? _activeHighlight : null,
              child: DecoratedBox(
                key: const Key('document-search-highlight'),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .2),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _measure() {
    if (!mounted) return;
    final root = _content.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return;
    final boxes = <Rect>[];
    var ordinal = 0;
    void visit(RenderObject object) {
      if (object is _RenderExcludeDocumentSearch ||
          ordinal > widget.activeIndex) {
        return;
      }
      if (object is RenderParagraph || object is RenderEditable) {
        final box = object as RenderBox;
        if (!box.hasSize) return;
        final span = object is RenderParagraph
            ? object.text
            : (object as RenderEditable).text;
        final matches = findAllMatches(
          span?.toPlainText() ?? '',
          widget.query,
          caseSensitive: widget.caseSensitive,
        );
        for (final match in matches) {
          if (ordinal++ != widget.activeIndex) continue;
          final origin = box.localToGlobal(Offset.zero, ancestor: root);
          final selection = TextSelection(
            baseOffset: match.start,
            extentOffset: match.end,
          );
          final found = object is RenderParagraph
              ? object.getBoxesForSelection(selection)
              : (object as RenderEditable).getBoxesForSelection(selection);
          boxes.addAll(found.map((box) => box.toRect().shift(origin)));
          break;
        }
      }
      object.visitChildren(visit);
    }

    if (widget.query.isNotEmpty && widget.activeIndex >= 0) visit(root);
    widget.onActiveRect?.call(
      boxes.isEmpty ? null : boxes.reduce((a, b) => a.expandToInclude(b)),
    );
    _revealBoxes(boxes);
    if (widget.geometry case final geometry?) {
      geometry.update(boxes, revealSignal: widget.revealSignal);
      return;
    }
    if (_sameRects(boxes, _boxes)) return;
    setState(() => _boxes = boxes);
  }

  void _revealBoxes(List<Rect> boxes) {
    final signal = widget.geometry?.revealSignal ?? widget.revealSignal;
    if (widget.revealIntoView &&
        boxes.isNotEmpty &&
        (widget.geometry?.pendingReveal ?? (signal != _revealedSignal))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            (widget.geometry != null
                ? !widget.geometry!.pendingReveal
                : signal == _revealedSignal)) {
          return;
        }
        if (signal != (widget.geometry?.revealSignal ?? widget.revealSignal)) {
          return;
        }
        final target = _activeHighlight.currentContext;
        if (target == null) return;
        _revealedSignal = signal;
        widget.geometry?.completeReveal();
        Scrollable.ensureVisible(target, alignment: .5);
      });
    }
  }

  bool _sameRects(List<Rect> a, List<Rect> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);
}

/// Gegenereerde nummering en onzichtbare invoerlagen zijn geen documenttekst.
class ExcludeDocumentSearch extends SingleChildRenderObjectWidget {
  const ExcludeDocumentSearch({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExcludeDocumentSearch();
}

class _RenderExcludeDocumentSearch extends RenderProxyBox {}

/// Eén tekstmeting kan door alle geknipte paginaweergaven worden hergebruikt.
class DocumentSearchGeometry extends ChangeNotifier {
  List<Rect> _boxes = const [];
  List<Rect> get boxes => _boxes;

  int revealSignal = 0;
  bool _pendingReveal = false;
  bool get pendingReveal => _pendingReveal;

  void completeReveal() => _pendingReveal = false;

  void update(List<Rect> boxes, {int revealSignal = 0}) {
    if (revealSignal == this.revealSignal &&
        boxes.length == _boxes.length &&
        List.generate(
          boxes.length,
          (i) => boxes[i] == _boxes[i],
        ).every((v) => v)) {
      return;
    }
    if (this.revealSignal != revealSignal) {
      _pendingReveal = revealSignal != 0 && boxes.isNotEmpty;
    }
    this.revealSignal = revealSignal;
    _boxes = List.unmodifiable(boxes);
    notifyListeners();
  }
}
