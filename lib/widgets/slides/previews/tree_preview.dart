// Part of the slide_preview library — see ../slide_preview.dart.
part of '../slide_preview.dart';

/// Preview for a Procesverbetering `tree` slide: nested bullets → Scene.
class _TreePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String languageCode;
  final ThemeProfile profile;

  const _TreePreview({
    required this.slide,
    required this.w,
    required this.languageCode,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final lang = languageCode.isEmpty ? 'nl' : languageCode;
    final templateId = slide.improvementTemplateId.isEmpty
        ? kDefaultTreeTemplateId
        : slide.improvementTemplateId;
    final template = treeTemplateById(templateId);
    final aspect = SlideAspectScope.of(context);
    const sceneW = 960.0;
    final scene = buildTreeScene(
      bullets: slide.bullets,
      layout: treeLayoutOf(slide),
      measurer: const ApproximateTextMeasurer(),
      title: slide.title,
      guidance: template?.guidance(lang) ?? '',
      palette: treePaletteFromTheme(
        background: profile.slideBackgroundColor,
        text: profile.textColor,
        accent: profile.accentColor,
      ),
      width: sceneW,
      height: sceneW / aspect,
    );
    return SizedBox(
      width: w,
      height: w / aspect,
      child: CustomPaint(
        painter: ScenePainter(
          scene,
          fontFamily: profile.fontFamily.isEmpty ? null : profile.fontFamily,
        ),
        size: Size(w, w / aspect),
      ),
    );
  }
}
