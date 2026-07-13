import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/log.dart' show logError;

/// A freehand signature pad: draw a signature with the mouse, trackpad, touch or
/// stylus, then it is rasterised to a transparent PNG and returned as an
/// embedded `data:image/png;base64,…` URI — the exact form
/// [DocumentSignature.imagePath] and [DocumentSignatureView] already expect, so
/// the drawn signature round-trips in the deck and is covered by the seal like
/// the rest of the attestation. Returns null when cancelled or nothing was
/// drawn (so the caller can keep the typed signature instead).
class SignatureDrawDialog extends StatefulWidget {
  const SignatureDrawDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const SignatureDrawDialog(),
    );
  }

  @override
  State<SignatureDrawDialog> createState() => _SignatureDrawDialogState();
}

class _SignatureDrawDialogState extends State<SignatureDrawDialog> {
  /// Each entry is one uninterrupted stroke, in canvas-local coordinates.
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;

  static const double _height = 180;
  static const Color _ink = AppTheme.navy;
  static const double _strokeWidth = 2.4;

  bool get _hasDrawing => _strokes.any((s) => s.isNotEmpty);

  void _start(Offset p) => setState(() => _strokes.add([_clamp(p)]));

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.add(_clamp(p)));
  }

  Offset _clamp(Offset p) => Offset(
    p.dx.clamp(0.0, _canvasSize.width),
    p.dy.clamp(0.0, _canvasSize.height),
  );

  void _clear() => setState(_strokes.clear);

  Future<void> _accept() async {
    if (!_hasDrawing || _canvasSize.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final uri = await _rasterize();
    if (!mounted) return;
    Navigator.pop(context, uri);
  }

  /// Paint the strokes onto an offscreen canvas at 3× and encode as a
  /// transparent PNG data URI. Uses the same geometry as the live painter.
  Future<String?> _rasterize() async {
    const scale = 3.0;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(scale);
      _paintStrokes(canvas);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (_canvasSize.width * scale).round(),
        (_canvasSize.height * scale).round(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (data == null) return null;
      return 'data:image/png;base64,${base64Encode(data.buffer.asUint8List())}';
    } catch (e, s) {
      logError('SignatureDrawDialog: rasterise signature', e, s);
      return null;
    }
  }

  void _paintStrokes(Canvas canvas) {
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final stroke in _strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        // A tap: a dot, drawn as a tiny filled circle.
        canvas.drawCircle(
          stroke.first,
          _strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l10n.d('Handtekening tekenen')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d('Teken je handtekening in het vak hieronder.'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  _canvasSize = Size(constraints.maxWidth, _height);
                  return Container(
                    height: _height,
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      border: Border.all(color: AppTheme.slate300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: GestureDetector(
                      key: const Key('signature-canvas'),
                      onPanStart: (d) => _start(d.localPosition),
                      onPanUpdate: (d) => _extend(d.localPosition),
                      child: CustomPaint(
                        painter: _SignaturePainter(_strokes),
                        size: Size.infinite,
                        child: _hasDrawing
                            ? null
                            : Center(
                                child: Container(
                                  width: constraints.maxWidth * 0.7,
                                  height: 1,
                                  color: AppTheme.slate300,
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _hasDrawing ? _clear : null,
            icon: const Icon(Icons.undo, size: 16),
            label: Text(l10n.d('Wissen')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton.icon(
            onPressed: _accept,
            icon: const Icon(Icons.check, size: 18),
            label: Text(l10n.d('Klaar')),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  const _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.navy
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.2, Paint()..color = AppTheme.navy);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
