// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a Procesverbetering `matrix` slide: the scene engine lays the
/// grid out once, and [ScenePainter] draws it (PROCESS_IMPROVEMENT §7).
///
/// Derived columns (RPN) are computed here, never read from storage — the same
/// rule the HTML SVG export follows via [sceneToSvg].
class _MatrixPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String languageCode;

  const _MatrixPreview({
    required this.slide,
    required this.w,
    required this.languageCode,
  });

  @override
  Widget build(BuildContext context) {
    final scene = buildMatrixScene(
      spec: matrixSpecFromSlide(slide),
      displayColumns: matrixDisplayColumns(slide),
      rows: matrixDisplayRows(slide),
      measurer: const ApproximateTextMeasurer(),
      title: slide.title,
      languageCode: languageCode.isEmpty ? 'nl' : languageCode,
      width: 960,
      height: 540,
    );
    return SizedBox(
      width: w,
      height: w * 9 / 16,
      child: CustomPaint(
        painter: ScenePainter(scene),
        size: Size(w, w * 9 / 16),
      ),
    );
  }
}
