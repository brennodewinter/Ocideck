// Part of the slide_preview library — see slide_preview.dart.
part of '../slide_preview.dart';

extension _ImprovementPreviewDispatch on SlidePreviewWidget {
  /// Procesverbetering-slidetypes (matrix/canvas/tree/flow/fasepoort).
  ///
  /// Uit [_buildContent] gehaald zodat die methode onder het lengteplafond
  /// blijft wanneer er een engine-type bijkomt.
  Widget _improvementPreview(Slide slide, double w) {
    switch (slide.type) {
      case SlideType.matrix:
        return _MatrixPreview(slide: slide, w: w, languageCode: reportLanguage);
      case SlideType.canvas:
        return _CanvasPreview(slide: slide, w: w, languageCode: reportLanguage);
      case SlideType.tree:
        return _TreePreview(slide: slide, w: w, languageCode: reportLanguage);
      case SlideType.flow:
        return _FlowPreview(slide: slide, w: w, languageCode: reportLanguage);
      case SlideType.phaseGate:
        return _BulletsPreview(
          slide: slide.copyWith(listStyle: ListStyle.checklist),
          w: w,
          projectPath: projectPath,
          font: fontFamily,
          profile: themeProfile,
          richTextPage: _effectivePage,
          numberStart: numberStart,
          fitScaleOverride: fitScaleOverride,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
