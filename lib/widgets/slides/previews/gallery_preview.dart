// Part of the slide_preview library — see ../slide_preview.dart.
// The imageGallery slide (#2838): a grid or a pile of `![alt](pad)` entries.
part of '../slide_preview.dart';

/// Rendert een `imageGallery`-dia (#2838): de beelden uit [Slide.galleryImages]
/// als raster (allemaal tegelijk) of als stapel (per klik één erbij).
///
/// [visibleCount] is hoeveel beelden getoond worden; in de presentatie komt
/// die uit het [ImageStackStepPlan], in de editor is alles zichtbaar. De
/// stapelverdeling is deterministisch per dia (seed uit het dia-id), zodat
/// presentator, beamerscherm en export exact dezelfde stapel tonen.
class GalleryPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final ThemeProfile profile;

  /// Zichtbaar aantal (per-klik-onthulling). `null` = allemaal.
  final int? visibleCount;

  const GalleryPreview({
    super.key,
    required this.slide,
    required this.w,
    this.projectPath,
    required this.profile,
    this.visibleCount,
  });

  /// Haalt pad en alt-tekst uit een `![alt](pad)`-entry.
  static ({String path, String alt}) _entry(String raw) {
    final m = RegExp(r'!\[([^\]]*)\]\(([^)\n]+)\)').firstMatch(raw);
    return (path: (m?.group(2) ?? '').trim(), alt: (m?.group(1) ?? '').trim());
  }

  /// Kolommen voor het raster bij [n] beelden.
  static int _colsFor(int n) => n <= 1
      ? 1
      : n <= 4
      ? 2
      : n <= 6
      ? 3
      : 4;

  /// Deterministische verschuiving en draaiing voor beeld [index] in [seed] —
  /// dezelfde invoer geeft altijd dezelfde stapel, in elke weergave.
  static ({double dx, double dy, double turns}) _offset(
    String seed,
    int index,
  ) {
    var h = seed.hashCode + index * 31;
    double frac(int bits) => ((h >> bits) & 0xff) / 255.0;
    return (
      dx: (frac(0) - 0.5) * 0.10,
      dy: (frac(8) - 0.5) * 0.10,
      turns: (frac(16) - 0.5) * 0.03,
    );
  }

  Widget _image(BuildContext context, ({String path, String alt}) e) =>
      _zoomedImage(
        context,
        e.path,
        projectPath,
        0,
        bgColor: AppTheme.parseHexColor(profile.slideBackgroundColor),
        semanticLabel: e.alt.isEmpty ? null : e.alt,
      );

  Widget _grid(BuildContext context, List<({String path, String alt})> images) {
    final cols = _colsFor(images.length);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (images.length + cols - 1) ~/ cols;
        final gap = w * 0.015;
        return Column(
          children: [
            for (var r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var c = 0; c < cols; c++) ...[
                      if (r * cols + c < images.length)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(gap / 2),
                            child: _image(context, images[r * cols + c]),
                          ),
                        )
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _stack(
    BuildContext context,
    List<({String path, String alt})> images,
  ) {
    final shown = visibleCount ?? images.length;
    final seed = slide.id;
    return Stack(
      children: [
        for (var i = 0; i < shown && i < images.length; i++)
          Builder(
            builder: (context) {
              final off = _offset(seed, i);
              return Transform.translate(
                offset: Offset(off.dx * w, off.dy * w),
                child: Transform.rotate(
                  angle: off.turns * 6.28318,
                  alignment: Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.all(w * 0.03),
                    child: _image(context, images[i]),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final e in slide.galleryImages) _entry(e),
    ].where((e) => e.path.isNotEmpty).toList();
    final safe = _mediaBrandStripInsets(w, slide, profile);
    final body = slide.galleryLayout == GalleryLayout.stack
        ? _stack(context, images)
        : _grid(context, images);
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(padding: safe, child: body),
        if (slide.title.isNotEmpty)
          Positioned(
            left: w * 0.06,
            right: w * 0.06,
            bottom: w * 0.06 + safe.bottom,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.04,
                vertical: w * 0.02,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                slide.title,
                style: _applyFont(
                  'sans',
                  TextStyle(
                    color: Colors.white,
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}
