/// Standard Marp visual directives that OciDeck can round-trip and render.
/// Empty values inherit from the deck style (for a slide) or the active OciDeck
/// theme (for a deck). No OciDeck-specific syntax is introduced.
class MarpStyle {
  final String color;
  final String backgroundColor;
  final String backgroundImage;
  final String header;
  final String footer;
  final String imageFit;
  final List<String> imageFilters;
  final bool headingFit;

  const MarpStyle({
    this.color = '',
    this.backgroundColor = '',
    this.backgroundImage = '',
    this.header = '',
    this.footer = '',
    this.imageFit = '',
    this.imageFilters = const [],
    this.headingFit = false,
  });

  bool get isEmpty =>
      color.isEmpty &&
      backgroundColor.isEmpty &&
      backgroundImage.isEmpty &&
      header.isEmpty &&
      footer.isEmpty &&
      imageFit.isEmpty &&
      imageFilters.isEmpty &&
      !headingFit;

  MarpStyle inherit(MarpStyle fallback) => MarpStyle(
    color: color.isEmpty ? fallback.color : color,
    backgroundColor: backgroundColor.isEmpty
        ? fallback.backgroundColor
        : backgroundColor,
    backgroundImage: backgroundImage.isEmpty
        ? fallback.backgroundImage
        : backgroundImage,
    header: header.isEmpty ? fallback.header : header,
    footer: footer.isEmpty ? fallback.footer : footer,
    imageFit: imageFit.isEmpty ? fallback.imageFit : imageFit,
    imageFilters: imageFilters.isEmpty ? fallback.imageFilters : imageFilters,
    headingFit: headingFit,
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
  }) => MarpStyle(
    color: color ?? this.color,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundImage: backgroundImage ?? this.backgroundImage,
    header: header ?? this.header,
    footer: footer ?? this.footer,
    imageFit: imageFit ?? this.imageFit,
    imageFilters: imageFilters ?? this.imageFilters,
    headingFit: headingFit ?? this.headingFit,
  );

  Map<String, Object?> toJson() => {
    'color': color,
    'backgroundColor': backgroundColor,
    'backgroundImage': backgroundImage,
    'header': header,
    'footer': footer,
    'imageFit': imageFit,
    'imageFilters': imageFilters,
    'headingFit': headingFit,
  };

  factory MarpStyle.fromJson(Map<String, Object?> json) => MarpStyle(
    color: json['color'] is String ? json['color']! as String : '',
    backgroundColor: json['backgroundColor'] is String
        ? json['backgroundColor']! as String
        : '',
    backgroundImage: json['backgroundImage'] is String
        ? json['backgroundImage']! as String
        : '',
    header: json['header'] is String ? json['header']! as String : '',
    footer: json['footer'] is String ? json['footer']! as String : '',
    imageFit: json['imageFit'] is String ? json['imageFit']! as String : '',
    imageFilters: json['imageFilters'] is List
        ? (json['imageFilters']! as List).whereType<String>().toList()
        : const [],
    headingFit: json['headingFit'] == true,
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
      headingFit == other.headingFit;

  @override
  int get hashCode => Object.hash(
    color,
    backgroundColor,
    backgroundImage,
    header,
    footer,
    imageFit,
    Object.hashAll(imageFilters),
    headingFit,
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Extracts a single `url(...)` asset from a Marp background directive.
/// Gradients and other CSS remain preserved in Markdown but are not treated as
/// local files by Flutter's image resolver.
String marpBackgroundAssetPath(String value) {
  final match = RegExp(
    r'''^url\(\s*(["']?)(.*?)\1\s*\)$''',
    caseSensitive: false,
  ).firstMatch(value.trim());
  return match?.group(2)?.trim() ?? '';
}
