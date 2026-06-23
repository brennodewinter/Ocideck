import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class AddSlideDialog extends StatelessWidget {
  const AddSlideDialog({super.key});

  static Future<SlideType?> show(BuildContext context) {
    return showDialog<SlideType>(
      context: context,
      builder: (_) => const AddSlideDialog(),
    );
  }

  static const _types = [
    (SlideType.title, 'Titelpagina'),
    (SlideType.section, 'Tussentitel'),
    (SlideType.bullets, 'Alleen Bullets'),
    (SlideType.twoBullets, 'Twee Bulletkolommen'),
    (SlideType.bulletsImage, 'Bullets + Afbeelding'),
    (SlideType.twoImages, 'Twee Afbeeldingen'),
    (SlideType.image, 'Grote Afbeelding'),
    (SlideType.video, 'Video'),
    (SlideType.quote, 'Quote'),
    (SlideType.table, 'Tabel'),
    (SlideType.chart, 'Grafiek'),
    (SlideType.cockpit, 'Cockpit'),
    (SlideType.question, 'Vraag'),
    (SlideType.code, 'Broncode'),
    (SlideType.freeMarkdown, 'Vrije Markdown'),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: AlertDialog(
        title: Text(l10n.d('Slide type kiezen')),
        content: SizedBox(
          width: 440,
          // Reading-order tabbing through the cards; the first one takes
          // focus so the dialog is fully keyboard-operable right away.
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _types.length; i++)
                  _TypeCard(
                    type: _types[i].$1,
                    label: l10n.d(_types[i].$2),
                    autofocus: i == 0,
                    onTap: () => Navigator.pop(context, _types[i].$1),
                  ),
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
            border: Border.all(color: const Color(0xFFCBD5E1)),
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
  static const _canvas = Color(0xFFF8FAFC);
  static const _ink = Color(0xFF334155);
  static const _soft = Color(0xFFB6C2D2);
  static const _fill = Color(0xFFE2E8F0);
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
      case SlideType.code:
        _bar(canvas, 10, 10, 140, 70, const Color(0xFF1E293B), radius: 4);
        _bar(canvas, 20, 22, 44, 6, const Color(0xFF7DD3A7), radius: 3);
        _bar(canvas, 30, 34, 64, 6, const Color(0xFF93B8F8), radius: 3);
        _bar(canvas, 30, 46, 50, 6, const Color(0xFFE2C08D), radius: 3);
        _bar(canvas, 20, 58, 32, 6, const Color(0xFF7DD3A7), radius: 3);
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
