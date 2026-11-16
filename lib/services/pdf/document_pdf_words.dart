import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import 'document_pdf_blocks.dart';

/// Keeps words together across apostrophes, font fallbacks and formatting changes.
List<pw.InlineSpan> pdfApostropheWords(
  List<PdfSpan> spans, {
  required pw.InlineSpan Function(PdfSpan) render,
  required pw.TextStyle style,
}) {
  if (!spans.map((s) => s.text).join().contains(RegExp(r"['’\u0080-\uFFFF]"))) {
    return spans.map(render).toList();
  }
  final output = <pw.InlineSpan>[];
  PdfSpan? pending;
  void emit(PdfSpan span) {
    if (pending != null &&
        pending!.copyWith(text: '') == span.copyWith(text: '')) {
      pending = pending!.copyWith(text: pending!.text + span.text);
    } else {
      if (pending != null) output.add(render(pending!));
      pending = span;
    }
  }

  void finishPending() {
    if (pending != null) output.add(render(pending!));
    pending = null;
  }

  final word = <PdfSpan>[];
  void flush() {
    if (word.isEmpty) return;
    final text = word.map((s) => s.text).join();
    final children = word.map(render).toList();
    // Lange tokens behouden de noodafbreking van RichText. Deze begrenzing
    // voorkomt dat een onbegrensd token een onbreekbaar inline-kader wordt.
    if (text.length <= 80 &&
        RegExp(r"\S['’]\S|[\u0080-\uFFFF]").hasMatch(text)) {
      finishPending();
      output.add(
        _ApostropheWordSpan(
          child: _ApostropheWord(
            text: pw.TextSpan(style: style, children: children),
          ),
        ),
      );
    } else {
      for (final span in word) {
        emit(span);
      }
    }
    word.clear();
  }

  for (final span in spans) {
    if (span.math) {
      flush();
      finishPending();
      output.add(render(span));
      continue;
    }
    for (final part in RegExp(r'\s+|\S+').allMatches(span.text)) {
      final text = part.group(0)!;
      if (text.trim().isEmpty) {
        flush();
        emit(span.copyWith(text: text));
      } else {
        word.add(span.copyWith(text: text));
      }
    }
  }
  flush();
  finishPending();
  return output;
}

class _ApostropheWordSpan extends pw.WidgetSpan {
  const _ApostropheWordSpan({
    required super.child,
    super.style,
    super.annotation,
  });

  @override
  double get baseline => (child as _ApostropheWord).baseline;

  @override
  pw.InlineSpan copyWith({
    pw.TextStyle? style,
    double? baseline,
    pw.AnnotationBuilder? annotation,
  }) => _ApostropheWordSpan(
    child: child,
    style: style ?? this.style,
    annotation: annotation ?? this.annotation,
  );
}

class _ApostropheWord extends pw.RichText {
  _ApostropheWord({required super.text});

  double baseline = 0;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    // Een inline-woord houdt zijn natuurlijke hoogte, ook wanneer de ouder
    // bijna geen verticale ruimte meer heeft. Anders meet een proefopmaak
    // een nulhoog woord en lijkt de rest van de alinea ten onrechte te passen.
    super.layout(
      context,
      constraints.copyWith(maxHeight: double.infinity),
      parentUsesSize: parentUsesSize,
    );
    baseline = 0;
    text.visitChildren(
      (span, style, annotation) {
        if (span is! pw.TextSpan || span.text == null) return true;
        final base = style!.font!.getFont(context);
        for (final rune in span.text!.runes) {
          var font = base;
          if (!font.isRuneSupported(rune)) {
            for (final fallback in style.fontFallback) {
              final candidate = fallback.getFont(context);
              if (candidate.isRuneSupported(rune)) {
                font = candidate;
                break;
              }
            }
          }
          // RichText tekent zelf een placeholder wanneer geen font dit teken
          // kent. Vraag dan geen Latin-1-metriek voor de ontbrekende glyph op.
          if (!font.isRuneSupported(rune)) continue;
          baseline = math.min(
            baseline,
            font.stringMetrics(String.fromCharCode(rune)).descent *
                style.fontSize!,
          );
        }
        return true;
      },
      pw.Theme.of(context).defaultTextStyle,
      null,
    );
  }
}
