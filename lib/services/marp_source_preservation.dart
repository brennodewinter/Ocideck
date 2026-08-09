import '../models/marp_style.dart';
import '../models/slide.dart';

final _backgroundImage = RegExp(r'!\[bg');
final _wholeBackground = RegExp(r'^!\[([^\]]*)\]\([^)]+\)$');
final _htmlComment = RegExp(r'<!--([\s\S]*?)-->', multiLine: true);
final _marpitDirective = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*\s*:');
final _imageFilter = RegExp(
  r'\b(?:blur(?::[^\s\]]+)?|brightness(?::[^\s\]]+)?|saturate(?::[^\s\]]+)?|grayscale|sepia|invert)\b',
  caseSensitive: false,
);
final _contain = RegExp(r'\b(?:fit|contain)\b', caseSensitive: false);

/// Whether typed serialization would move or rewrite authored Marpit source.
bool requiresWholeMarpBlockPreservation(String block) {
  final backgrounds = block
      .split('\n')
      .map((line) => line.trim())
      .where(_backgroundImage.hasMatch)
      .toList();
  if (backgrounds.length > 2) return true;
  for (var i = 0; i < backgrounds.length; i++) {
    if (!_hasOnlyTypedBackgroundOptions(
      backgrounds[i],
      allowVisualStyle: i == 0,
    )) {
      return true;
    }
  }

  final lines = block.split('\n');
  final fitLines = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == '<!-- fit -->') fitLines.add(i);
  }
  if (fitLines.length > 1) return true;
  if (fitLines.length == 1) {
    final fit = fitLines.single;
    final firstHeading = lines.indexWhere(
      (line) => RegExp(r'^#{1,6}\s+\S').hasMatch(line.trim()),
    );
    if (fit == 0 || fit - 1 != firstHeading) return true;
  }
  final fitComments = _htmlComment
      .allMatches(block)
      .where((match) => match.group(1)!.trim() == 'fit')
      .length;
  if (fitComments != fitLines.length) return true;

  for (final match in _htmlComment.allMatches(block)) {
    final raw = match.group(1)!;
    if (raw.contains('\n')) continue;
    final content = raw.trim();
    if (_marpitDirective.hasMatch(content) &&
        !_isKnownOciDeckOrTypedDirective(content)) {
      return true;
    }
  }
  return false;
}

bool _hasOnlyTypedBackgroundOptions(
  String line, {
  required bool allowVisualStyle,
}) {
  final match = _wholeBackground.firstMatch(line);
  if (match == null) return false;
  var options = match.group(1)!.trim();
  if (!RegExp(r'^bg(?:\s|$)').hasMatch(options)) return false;
  options = options.substring(2).trim();
  if (allowVisualStyle) {
    options = options
        .replaceAll(_imageFilter, '')
        .replaceAll(RegExp(r'\bopacity:\.45\b'), '')
        .replaceAll(_contain, '');
  }
  options = options
      .replaceAll(RegExp(r'\b(?:left|right):\d+%'), '')
      .replaceAll(RegExp(r'\b\d+%'), '')
      .trim();
  return options.isEmpty;
}

bool _isKnownOciDeckOrTypedDirective(String content) =>
    content.startsWith('advance:') ||
    content.startsWith('tlp:') ||
    content.startsWith('ocideck_') ||
    content.startsWith('_');

/// Separates background lines the typed image fields cannot carry losslessly.
({String remaining, List<String> preserved}) unsupportedMarpImageLines(
  String source,
) {
  final preserved = <String>[];
  var backgroundCount = 0;
  final kept = <String>[];
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (!_backgroundImage.hasMatch(trimmed)) {
      kept.add(line);
      continue;
    }
    backgroundCount++;
    final laterExtended =
        backgroundCount > 1 &&
        (_imageFilter.hasMatch(trimmed) || _contain.hasMatch(trimmed));
    if (backgroundCount > 2 || laterExtended) {
      preserved.add(line);
    } else {
      kept.add(line);
    }
  }
  return (remaining: kept.join('\n').trim(), preserved: preserved);
}

/// Reads the visual options represented by the first Marp background image.
MarpStyle marpImageStyleFromSource(String source) {
  for (final line in source.split('\n')) {
    if (!_backgroundImage.hasMatch(line)) continue;
    final options = RegExp(r'!\[([^\]]*)\]').firstMatch(line)?.group(1) ?? '';
    return MarpStyle(
      imageFit: _contain.hasMatch(options) ? 'contain' : '',
      imageFilters: _imageFilter
          .allMatches(options)
          .map((match) => match.group(0)!)
          .toList(),
    );
  }
  return const MarpStyle();
}

/// Serializes the standard Marp options for a slide background image.
String marpBackgroundOptions(
  Slide slide, {
  String positional = '',
  bool overlay = false,
}) => [
  'bg',
  if (positional.isNotEmpty) positional,
  if (slide.marpStyle.imageFit == 'contain')
    'contain'
  else if (slide.imageSize > 0 && positional.isEmpty)
    '${slide.imageSize}%',
  ...slide.marpStyle.imageFilters,
  if (overlay) 'opacity:.45',
].join(' ');
