/// Bestaande sterkte van de citaatwaas, in procenten.
const kDefaultQuoteImageOverlayStrength = 52;

/// Marp visual directives and local image presentation settings.
///
/// A missing value inherits. An explicitly empty value disables the inherited
/// deck value. Standard directives use `has*` flags for this third state.
/// The local overlay strength is nullable and has an effective default getter.
class MarpStyle {
  final String color;
  final String backgroundColor;
  final String backgroundImage;
  final String header;
  final String footer;
  final String imageFit;
  final List<String> imageFilters;
  final bool headingFit;

  /// Lokale citaatwaas; null behoudt de bestaande standaard en overerving.
  final int? imageOverlayStrength;
  int get effectiveImageOverlayStrength =>
      imageOverlayStrength ?? kDefaultQuoteImageOverlayStrength;

  final bool hasColor;
  final bool hasBackgroundColor;
  final bool hasBackgroundImage;
  final bool hasHeader;
  final bool hasFooter;
  final bool hasImageFit;
  final bool hasImageFilters;

  const MarpStyle({
    String? color,
    String? backgroundColor,
    String? backgroundImage,
    String? header,
    String? footer,
    String? imageFit,
    List<String>? imageFilters,
    this.headingFit = false,
    int? imageOverlayStrength,
  }) : imageOverlayStrength = imageOverlayStrength == null
           ? null
           : imageOverlayStrength < 0
           ? 0
           : imageOverlayStrength > 100
           ? 100
           : imageOverlayStrength,
       color = color ?? '',
       backgroundColor = backgroundColor ?? '',
       backgroundImage = backgroundImage ?? '',
       header = header ?? '',
       footer = footer ?? '',
       imageFit = imageFit ?? '',
       imageFilters = imageFilters ?? const [],
       hasColor = color != null,
       hasBackgroundColor = backgroundColor != null,
       hasBackgroundImage = backgroundImage != null,
       hasHeader = header != null,
       hasFooter = footer != null,
       hasImageFit = imageFit != null,
       hasImageFilters = imageFilters != null;

  const MarpStyle._({
    required this.color,
    required this.backgroundColor,
    required this.backgroundImage,
    required this.header,
    required this.footer,
    required this.imageFit,
    required this.imageFilters,
    required this.headingFit,
    required this.imageOverlayStrength,
    required this.hasColor,
    required this.hasBackgroundColor,
    required this.hasBackgroundImage,
    required this.hasHeader,
    required this.hasFooter,
    required this.hasImageFit,
    required this.hasImageFilters,
  });

  bool get isEmpty =>
      !hasColor &&
      !hasBackgroundColor &&
      !hasBackgroundImage &&
      !hasHeader &&
      !hasFooter &&
      !hasImageFit &&
      !hasImageFilters &&
      !headingFit &&
      imageOverlayStrength == null;

  MarpStyle inherit(MarpStyle fallback) => MarpStyle._(
    color: hasColor ? color : fallback.color,
    backgroundColor: hasBackgroundColor
        ? backgroundColor
        : fallback.backgroundColor,
    backgroundImage: hasBackgroundImage
        ? backgroundImage
        : fallback.backgroundImage,
    header: hasHeader ? header : fallback.header,
    footer: hasFooter ? footer : fallback.footer,
    imageFit: hasImageFit ? imageFit : fallback.imageFit,
    imageFilters: hasImageFilters ? imageFilters : fallback.imageFilters,
    headingFit: headingFit,
    imageOverlayStrength: imageOverlayStrength ?? fallback.imageOverlayStrength,
    hasColor: hasColor || fallback.hasColor,
    hasBackgroundColor: hasBackgroundColor || fallback.hasBackgroundColor,
    hasBackgroundImage: hasBackgroundImage || fallback.hasBackgroundImage,
    hasHeader: hasHeader || fallback.hasHeader,
    hasFooter: hasFooter || fallback.hasFooter,
    hasImageFit: hasImageFit || fallback.hasImageFit,
    hasImageFilters: hasImageFilters || fallback.hasImageFilters,
  );

  MarpStyle copyWith({
    String? color,
    String? backgroundColor,
    String? backgroundImage,
    String? header,
    String? footer,
    String? imageFit,
    List<String>? imageFilters,
    bool? headingFit,
    int? imageOverlayStrength,
    bool clearFooter = false,
    bool clearBackgroundImage = false,
  }) => MarpStyle._(
    color: color ?? this.color,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundImage: clearBackgroundImage
        ? ''
        : (backgroundImage ?? this.backgroundImage),
    header: header ?? this.header,
    footer: clearFooter ? '' : (footer ?? this.footer),
    imageFit: imageFit ?? this.imageFit,
    imageFilters: imageFilters ?? this.imageFilters,
    headingFit: headingFit ?? this.headingFit,
    imageOverlayStrength:
        imageOverlayStrength?.clamp(0, 100) ?? this.imageOverlayStrength,
    hasColor: color != null || hasColor,
    hasBackgroundColor: backgroundColor != null || hasBackgroundColor,
    hasBackgroundImage: clearBackgroundImage
        ? false
        : (backgroundImage != null || hasBackgroundImage),
    hasHeader: header != null || hasHeader,
    hasFooter: clearFooter ? false : (footer != null || hasFooter),
    hasImageFit: imageFit != null || hasImageFit,
    hasImageFilters: imageFilters != null || hasImageFilters,
  );

  Map<String, Object?> toJson() => {
    if (hasColor) 'color': color,
    if (hasBackgroundColor) 'backgroundColor': backgroundColor,
    if (hasBackgroundImage) 'backgroundImage': backgroundImage,
    if (hasHeader) 'header': header,
    if (hasFooter) 'footer': footer,
    if (hasImageFit) 'imageFit': imageFit,
    if (hasImageFilters) 'imageFilters': imageFilters,
    'headingFit': headingFit,
    if (imageOverlayStrength != null)
      'imageOverlayStrength': imageOverlayStrength,
  };

  factory MarpStyle.fromJson(Map<String, Object?> json) => MarpStyle(
    color: _optional<String>(json, 'color'),
    backgroundColor: _optional<String>(json, 'backgroundColor'),
    backgroundImage: _optional<String>(json, 'backgroundImage'),
    header: _optional<String>(json, 'header'),
    footer: _optional<String>(json, 'footer'),
    imageFit: _optional<String>(json, 'imageFit'),
    imageFilters: _stringList(json, 'imageFilters'),
    headingFit: _optional<bool>(json, 'headingFit') ?? false,
    imageOverlayStrength: _optional<int>(json, 'imageOverlayStrength'),
  );

  @override
  bool operator ==(Object other) =>
      other is MarpStyle &&
      color == other.color &&
      backgroundColor == other.backgroundColor &&
      backgroundImage == other.backgroundImage &&
      header == other.header &&
      footer == other.footer &&
      imageFit == other.imageFit &&
      _listEquals(imageFilters, other.imageFilters) &&
      headingFit == other.headingFit &&
      imageOverlayStrength == other.imageOverlayStrength &&
      hasColor == other.hasColor &&
      hasBackgroundColor == other.hasBackgroundColor &&
      hasBackgroundImage == other.hasBackgroundImage &&
      hasHeader == other.hasHeader &&
      hasFooter == other.hasFooter &&
      hasImageFit == other.hasImageFit &&
      hasImageFilters == other.hasImageFilters;

  @override
  int get hashCode => Object.hash(
    color,
    backgroundColor,
    backgroundImage,
    header,
    footer,
    imageFit,
    Object.hashAll(imageFilters),
    imageOverlayStrength,
    headingFit,
    hasColor,
    hasBackgroundColor,
    hasBackgroundImage,
    hasHeader,
    hasFooter,
    hasImageFit,
    hasImageFilters,
  );
}

T? _optional<T>(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value is T) return value;
  throw FormatException('MarpStyle.$key must be a $T');
}

List<String>? _stringList(Map<String, Object?> json, String key) {
  final value = _optional<List<Object?>>(json, key);
  if (value == null) return null;
  if (value.any((item) => item is! String)) {
    throw FormatException('MarpStyle.$key must contain only strings');
  }
  return value.cast<String>();
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _backgroundUrl = RegExp(
  r'''^url\(\s*(["']?)(.*?)\1\s*\)$''',
  caseSensitive: false,
);

/// Extracts a single `url(...)` asset from a Marp background directive.
/// Gradients and other CSS remain preserved in Markdown but are not treated as
/// local files by Flutter's image resolver.
String marpBackgroundAssetPath(String value) {
  final match = _backgroundUrl.firstMatch(value.trim());
  return match?.group(2)?.trim() ?? '';
}

/// De tegenhanger van [marpBackgroundAssetPath]: dezelfde `url(...)`-vorm, met
/// het pad erin vervangen door wat [map] ervan maakt. `null` — of een waarde
/// die geen enkele url() draagt, zoals een gradient — laat [value] staan.
/// Alleen het pad verandert; de aanhalingstekens om het pad blijven staan.
String rewriteMarpBackgroundAssetPath(
  String value,
  String? Function(String path) map,
) {
  final match = _backgroundUrl.firstMatch(value.trim());
  if (match == null) return value;
  final path = match.group(2)!.trim();
  final replacement = path.isEmpty ? null : map(path);
  if (replacement == null || replacement == path) return value;
  final quote = match.group(1)!;
  return 'url($quote$replacement$quote)';
}
