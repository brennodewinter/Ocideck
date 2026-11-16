import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Text with measured line boundaries and two-line widow/orphan protection.
class PaginatedPdfText extends pw.RichText {
  PaginatedPdfText({required super.text, this.pageHeight, super.textAlign})
    : super(overflow: pw.TextOverflow.span);

  final double Function(pw.Context context)? pageHeight;
  _TextProbe? _probe;
  double? _width;
  double _fullHeight = 0;
  int _totalSpans = 0;
  int _lastLineStart = 0;
  final _minimums = <int, ({double height, int spans})>{};

  void _measure(pw.Context context, double width) {
    if (_width == width) return;
    _width = width;
    _minimums.clear();
    final probe = _probe = _TextProbe(text: text);
    final full = probe.measure(
      context,
      width,
      double.infinity,
      pw.RichTextContext(),
    );
    _fullHeight = full.height;
    _totalSpans = full.spans;
    _lastLineStart = probe
        .measure(
          context,
          width,
          math.max(0, _fullHeight - .01),
          pw.RichTextContext(),
        )
        .spans;
  }

  ({double height, int spans}) _nextLine(
    pw.Context context,
    pw.RichTextContext from,
    int after,
    double high,
  ) {
    var low = 0.0;
    // Meet de overgang tussen twee werkelijk geplaatste regels. maxLines is
    // hier ongeschikt: RichText telt inline-widgets anders dan tekstspans.
    while (high - low > .001) {
      final mid = (low + high) / 2;
      if (_probe!.measure(context, _width!, mid, from).spans > after) {
        high = mid;
      } else {
        low = mid;
      }
    }
    final height = high + .01;
    return (
      height: height,
      spans: _probe!.measure(context, _width!, height, from).spans,
    );
  }

  ({double height, int spans}) _firstTwo(
    pw.Context context,
    pw.RichTextContext from,
  ) => _minimums.putIfAbsent(from.spanStart, () {
    final remaining = _fullHeight + from.startOffset;
    final first = _nextLine(context, from, from.spanStart, remaining);
    if (first.spans >= _totalSpans) return first;
    return _nextLine(context, from, first.spans, remaining);
  });

  /// Measures two rendered lines, including mixed fonts and inline widgets.
  double firstLinesHeight(pw.Context context, double width) {
    _measure(context, width);
    return _firstTwo(context, pw.RichTextContext()).height;
  }

  @override
  bool get hasMoreWidgets =>
      _width == null ||
      (super.saveContext() as pw.RichTextContext).spanEnd < _totalSpans;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    if (!constraints.maxHeight.isFinite) {
      super.layout(context, constraints, parentUsesSize: parentUsesSize);
      return;
    }
    _measure(context, constraints.maxWidth);
    final from =
        (super.saveContext() as pw.RichTextContext).clone()
            as pw.RichTextContext;
    super.layout(context, constraints, parentUsesSize: parentUsesSize);
    var end = (super.saveContext() as pw.RichTextContext).spanEnd;
    if (end >= _totalSpans) return;
    final minimum = _firstTwo(context, from);
    final freshHeight =
        pageHeight?.call(context) ?? context.page.pageFormat.availableHeight;
    final fresh = constraints.maxHeight >= freshHeight - .01;
    var height = constraints.maxHeight;
    if (end == _lastLineStart && end > from.spanStart) {
      final boundary = _nextLine(context, from, end - 1, height);
      final reduced = math.max(0.0, boundary.height - .03);
      final candidate = _probe!.measure(context, _width!, reduced, from);
      // Op een te klein vers blad krijgt voortgang voorrang boven binding.
      if (candidate.spans >= minimum.spans || !fresh) {
        height = reduced;
        end = candidate.spans;
      }
    }
    final defer = end < minimum.spans && !fresh;
    // Probes delen de inline-widgets met de tekst. De laatste opmaak moet die
    // daarom altijd opnieuw op hun werkelijke positie op dit blad zetten.
    (super.saveContext() as pw.RichTextContext).apply(from);
    super.layout(
      context,
      constraints.copyWith(maxHeight: defer ? 0 : height),
      parentUsesSize: parentUsesSize,
    );
    if (defer) {
      final state = super.saveContext() as pw.RichTextContext;
      state
        ..spanEnd = from.spanStart
        ..endOffset = -from.startOffset;
      box = PdfRect(0, 0, box!.width, 0);
    }
  }
}

class _TextProbe extends pw.RichText {
  _TextProbe({required super.text}) : super(overflow: pw.TextOverflow.span);

  ({double height, int spans}) measure(
    pw.Context context,
    double width,
    double height,
    pw.RichTextContext from,
  ) {
    (super.saveContext() as pw.RichTextContext).apply(from);
    super.layout(
      context,
      pw.BoxConstraints(maxWidth: width, maxHeight: height),
    );
    return (
      height: box!.height,
      spans: (super.saveContext() as pw.RichTextContext).spanEnd,
    );
  }
}

/// Measures a keep-with-next requirement before MultiPage checks free space.
class PdfKeepMeasure extends pw.Widget {
  PdfKeepMeasure({required this.pageBreak, required this.measure});

  final PdfMeasuredBreak pageBreak;
  final double Function(pw.Context, double width) measure;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    pageBreak.requiredHeight = measure(context, constraints.maxWidth);
    box = PdfRect.zero;
  }
}

/// A conditional page break populated by the preceding measurement widget.
class PdfMeasuredBreak extends pw.NewPage {
  double requiredHeight = 0;

  @override
  bool newPageNeeded(double availableSpace) =>
      requiredHeight > availableSpace + .001;
}
