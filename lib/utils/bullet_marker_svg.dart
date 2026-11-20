import '../models/settings.dart';

/// The cat paw used for unordered lists in document and presentation exports.
String pawBulletSvg(String accent) {
  const path =
      "M8 9.28Q12.64 9.28 10.32 12.4Q8 15.52 5.68 12.4Q3.36 9.28 8 9.28Z";
  return "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>"
      "<path d='$path' fill='$accent'/>"
      "<ellipse cx='2.56' cy='6.88' rx='1.76' ry='2.4' fill='$accent' transform='rotate(-31.5 2.56 6.88)'/>"
      "<ellipse cx='6.24' cy='3.36' rx='1.92' ry='2.8' fill='$accent' transform='rotate(-10.3 6.24 3.36)'/>"
      "<ellipse cx='9.76' cy='3.36' rx='1.92' ry='2.8' fill='$accent' transform='rotate(10.3 9.76 3.36)'/>"
      "<ellipse cx='13.44' cy='6.88' rx='1.76' ry='2.4' fill='$accent' transform='rotate(31.5 13.44 6.88)'/>"
      "</svg>";
}

/// Vector artwork for the selected document style, or null for a dot.
String? documentBulletSvg(ThemeProfile? profile) => switch (profile) {
  ThemeProfile(bulletMarker: BulletMarker.paw, :final accentColor) =>
    pawBulletSvg(accentColor),
  ThemeProfile(bulletMarker: BulletMarker.customSvg, :final customBulletSvg) =>
    customBulletSvg,
  _ => null,
};
