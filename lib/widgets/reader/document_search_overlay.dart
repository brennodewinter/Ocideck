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
  });

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
  List<Rect> _boxes = const [];

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Stack(
      children: [
        KeyedSubtree(
          key: _content,
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
              return false;
            },
            child: widget.child,
          ),
        ),
        for (final box in _boxes)
          Positioned.fromRect(
            rect: box.inflate(2),
            child: IgnorePointer(
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
      if (object is _RenderExcludeDocumentSearch) return;
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
        }
      }
      object.visitChildren(visit);
    }

    if (widget.query.isNotEmpty) visit(root);
    widget.onActiveRect?.call(
      boxes.isEmpty ? null : boxes.reduce((a, b) => a.expandToInclude(b)),
    );
    if (_sameRects(boxes, _boxes)) return;
    setState(() => _boxes = boxes);
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
