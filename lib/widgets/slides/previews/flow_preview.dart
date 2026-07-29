// Part of the slide_preview library — see ../slide_preview.dart.
part of '../slide_preview.dart';

/// Preview for a Procesverbetering `flow` slide: bullets → Scene.
class _FlowPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String languageCode;

  const _FlowPreview({
    required this.slide,
    required this.w,
    required this.languageCode,
  });

  @override
  Widget build(BuildContext context) {
    final lang = languageCode.isEmpty ? 'nl' : languageCode;
    final templateId = slide.improvementTemplateId.isEmpty
        ? kDefaultFlowTemplateId
        : slide.improvementTemplateId;
    final template = flowTemplateById(templateId);
    final scene = buildFlowScene(
      steps: flowStepsFromBullets(slide.bullets),
      layout: flowLayoutOf(slide),
      measurer: const ApproximateTextMeasurer(),
      title: slide.title,
      guidance: template?.guidance(lang) ?? '',
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
