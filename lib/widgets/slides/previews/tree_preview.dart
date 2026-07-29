// Part of the slide_preview library — see ../slide_preview.dart.
part of '../slide_preview.dart';

/// Preview for a Procesverbetering `tree` slide: nested bullets → Scene.
class _TreePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String languageCode;

  const _TreePreview({
    required this.slide,
    required this.w,
    required this.languageCode,
  });

  @override
  Widget build(BuildContext context) {
    final lang = languageCode.isEmpty ? 'nl' : languageCode;
    final templateId = slide.improvementTemplateId.isEmpty
        ? kDefaultTreeTemplateId
        : slide.improvementTemplateId;
    final template = treeTemplateById(templateId);
    final scene = buildTreeScene(
      bullets: slide.bullets,
      layout: treeLayoutOf(slide),
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
