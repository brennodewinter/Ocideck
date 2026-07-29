// Part of the slide_preview library — see ../slide_preview.dart.
part of '../slide_preview.dart';

/// Preview for a Procesverbetering `canvas` slide: regions → Scene → painter.
class _CanvasPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String languageCode;

  const _CanvasPreview({
    required this.slide,
    required this.w,
    required this.languageCode,
  });

  @override
  Widget build(BuildContext context) {
    final templateId = slide.improvementTemplateId.isEmpty
        ? kDefaultCanvasTemplateId
        : slide.improvementTemplateId;
    final template = canvasTemplateById(templateId);
    final regions = canvasRegionsFromMarkdown(
      slide.customMarkdown,
      templateId: templateId,
    );
    final scene = buildCanvasScene(
      template: template,
      regions: regions,
      measurer: const ApproximateTextMeasurer(),
      title: slide.title,
      languageCode: languageCode.isEmpty ? 'nl' : languageCode,
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
