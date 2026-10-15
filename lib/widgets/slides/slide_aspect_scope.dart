import 'package:flutter/widgets.dart';

import '../../models/slide_format.dart';

/// De diaverhouding (breedte/hoogte) die de slides onder deze scope aannemen.
///
/// De preview-binnenwerkenden meten hun ruimte uit `breedte / aspect`; voorheen
/// stond die `9 / 16` overal letterlijk in de code, zodat een staand diaformaat
/// op een dozijn plekken tegelijk had moeten worden bijgewerkt — en elke
/// gemiste plek had stil afgeknipte inhoud betekend. Één scope boven de
/// renderboom maakt dat onmogelijk: [SlidePreviewWidget] zet hem, elk
/// deelwidget leest hem.
///
/// Buiten een scope (zelfstandige previews, dialoogvoorbeelden) geldt de
/// schermstandaard 16:9 — precies wat een deck zonder aanduiding ook betekent.
class SlideAspectScope extends InheritedWidget {
  const SlideAspectScope({
    super.key,
    required this.aspect,
    required super.child,
  });

  /// Breedte/hoogte van de dia. `kScreenSlideAspect` (16/9) voor decks zonder
  /// papierformaat.
  final double aspect;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlideAspectScope>()?.aspect ??
      kScreenSlideAspect;

  @override
  bool updateShouldNotify(SlideAspectScope oldWidget) =>
      aspect != oldWidget.aspect;
}
