// De gezamenlijke beeldgeometrie voor de 'Gelijke hoogte'-weergave van een
// twoImages-dia (#2867). Flutter-vrij, zodat de widget-preview, de
// rasterexports en de tests exact dezelfde uitkomst rekenen.
//
// De regel: beide beelden krijgen exact dezelfde zichtbare hoogte, blijven
// volledig zichtbaar en onvervormd, en hun breedtes volgen de
// bronverhoudingen — nooit de handmatige paneelverdeling (imageSize), want
// die zou de gelijke hoogte bij extreme verhoudingen weer verbreken.

import 'dart:math' as math;

/// De uitgerekende rij: één gedeelde hoogte, twee breedtes en de
/// tussenruimte. De aanroeper centreert de rij in het beschikbare vlak.
class TwoImagesRow {
  /// De gedeelde zichtbare hoogte van beide beelden.
  final double height;

  /// Beeldbreedte van de linker- resp. rechterafbeelding — `height × aspect`.
  final double leftWidth;
  final double rightWidth;

  /// De tussenruimte tussen de twee beelden.
  final double gap;

  const TwoImagesRow({
    required this.height,
    required this.leftWidth,
    required this.rightWidth,
    required this.gap,
  });

  double get totalWidth => leftWidth + gap + rightWidth;
}

/// Legt twee beelden met bronverhoudingen [aspect1] en [aspect2] (breedte /
/// hoogte) naast elkaar op één hoogte binnen [availW] × [availH], met [gap]
/// als tussenruimte. De hoogte is `min(availH, (availW - gap) / (a1 + a2))`:
/// past de rij op de breedte niet, dan schaalt hij mee zonder te vervormen.
///
/// `null` bij ontbrekende of ongeldige invoer (lege/negatieve/oneindige
/// waarden) — de aanroeper valt dan terug op de gewone paneelverdeling
/// in plaats van NaN of een eindeloze relayout te tekenen.
TwoImagesRow? twoImagesEqualHeight({
  required double aspect1,
  required double aspect2,
  required double availW,
  required double availH,
  double gap = 0,
}) {
  if (!aspect1.isFinite || !aspect2.isFinite || aspect1 <= 0 || aspect2 <= 0) {
    return null;
  }
  final usableW = availW - gap;
  if (!usableW.isFinite || !availH.isFinite || usableW <= 0 || availH <= 0) {
    return null;
  }
  final h = math.min(availH, usableW / (aspect1 + aspect2));
  return TwoImagesRow(
    height: h,
    leftWidth: h * aspect1,
    rightWidth: h * aspect2,
    gap: gap,
  );
}
