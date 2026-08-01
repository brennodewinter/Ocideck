/// Elke afbeelding waar een dia naar verwijst, ongeacht wáár de verwijzing
/// staat — het aangewezen afbeeldingsveld, een `![alt](pad)` midden in de
/// vrije tekst, óf de antwoord-afbeeldingen van een imagePair-vraag.
///
/// Dit bestand bestaat omdat het antwoord op "welke afbeeldingen gebruikt deze
/// dia" op zo'n twintig plekken werd uitgeschreven als `slide.imagePath` en
/// `slide.imagePath2`, en dat antwoord sinds afbeeldingen in de tekst niet meer
/// compleet is. Een gemiste plek is geen schoonheidsfoutje: de privacyscan zou
/// een gezicht overslaan, de opruimer van ongebruikte assets zou een bestand dat
/// wél in gebruik is als wees aanmerken, en de `mem:`-sweep op web zou bytes
/// weggooien waar nog naar verwezen wordt. Eén definitie, en elke plek leest
/// hem.
library;

import 'dart:convert';

import '../models/slide.dart';

/// Markdown-afbeelding: `![alt of directive](pad)`. Dezelfde vorm als
/// `ImageReferenceService._imageRef` en `AssetIndex.referencesIn` gebruiken, en
/// met opzet geen echte markdown-parser: we willen élke verwijzing zien, ook
/// eentje in een regel die een parser als iets anders zou lezen.
final _imageRef = RegExp(r'!\[([^\]]*)\]\(([^)\n]+)\)');

/// Waar een afbeeldingsverwijzing op een dia vandaan komt.
enum SlideImageSlot {
  /// Het eerste afbeeldingsveld ([Slide.imagePath]).
  image,

  /// Het tweede afbeeldingsveld ([Slide.imagePath2]).
  image2,

  /// Een `![…](…)` in de vrije tekst ([Slide.customMarkdown]).
  inline,

  /// Een antwoord-afbeelding van een imagePair-vraag, in het `question`-blok
  /// ([Slide.customMarkdown]). Daar is de afbeelding *het antwoord*, niet een
  /// illustratie — en ze zat tot #853 in geen enkele verwijzing, waardoor de
  /// privacyscan een gezicht oversloeg, de asset-opruiming ze als wees zag en
  /// de `mem:`-sweep op web de bytes weggooide.
  questionImage,
}

/// Eén afbeeldingsverwijzing van een dia.
class SlideImageRef {
  /// Het pad zoals het in de dia staat — ongewijzigd, dus mogelijk relatief,
  /// absoluut, een `mem:`/`repo:`-verwijzing of een URL. Filteren is aan de
  /// aanroeper; die weet welke soorten voor hém betekenis hebben.
  final String path;

  /// De alt-tekst uit `![…]`, leeg voor een veldverwijzing. Bij een inline
  /// afbeelding is dít de alt-tekst — een inline afbeelding heeft geen
  /// `imageAltText`-veld om op terug te vallen.
  final String alt;

  final SlideImageSlot slot;

  const SlideImageRef({required this.path, required this.slot, this.alt = ''});

  @override
  bool operator ==(Object other) =>
      other is SlideImageRef &&
      other.path == path &&
      other.alt == alt &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(path, alt, slot);

  @override
  String toString() => 'SlideImageRef(${slot.name}: $path)';
}

/// Elke afbeeldingsverwijzing van [slide], in leesvolgorde: eerst de velden,
/// dan de tekst. Lege paden vallen weg — een leeg veld is geen verwijzing.
List<SlideImageRef> slideImageRefs(Slide slide) {
  final refs = <SlideImageRef>[];
  final image = slide.imagePath.trim();
  if (image.isNotEmpty) {
    refs.add(
      SlideImageRef(
        path: image,
        slot: SlideImageSlot.image,
        alt: slide.imageAltText,
      ),
    );
  }
  final image2 = slide.imagePath2.trim();
  if (image2.isNotEmpty) {
    refs.add(
      SlideImageRef(
        path: image2,
        slot: SlideImageSlot.image2,
        alt: slide.imageAltText2,
      ),
    );
  }
  // Een vraag-slide draagt zijn `question`-blok (JSON) in [Slide.customMarkdown],
  // niet vrije Markdown; de imagePair-antwoorden staan daar als `image`-velden,
  // niet als `![…](…)`. Daarom leest deze tak het blok in plaats van de inline
  // regex — anders bleven de antwoord-afbeeldingen onzichtbaar (#853). Lees de
  // ruwe records, niet QuestionSpec.answers: een te grote vraag wordt bewust
  // niet uitvoerbaar gemaakt, maar opslag moet ook dan alle assets behouden.
  if (slide.type == SlideType.question) {
    for (final answer in _questionAnswerMaps(slide.customMarkdown)) {
      final image = (answer['image'] ?? '').toString().trim();
      if (image.isEmpty) continue;
      refs.add(
        SlideImageRef(
          path: image,
          slot: SlideImageSlot.questionImage,
          alt: (answer['text'] ?? '').toString(),
        ),
      );
    }
  } else {
    for (final match in _imageRef.allMatches(slide.customMarkdown)) {
      final path = (match.group(2) ?? '').trim();
      if (path.isEmpty) continue;
      refs.add(
        SlideImageRef(
          path: path,
          slot: SlideImageSlot.inline,
          alt: (match.group(1) ?? '').trim(),
        ),
      );
    }
  }
  return refs;
}

/// De paden van [slideImageRefs], zonder de rest. Voor de vele plekken die
/// alleen "welke bestanden" hoeven te weten.
Iterable<String> slideImagePaths(Slide slide) =>
    slideImageRefs(slide).map((r) => r.path);

/// De paden van elke `![…](…)` in [markdown], in leesvolgorde.
List<String> inlineImagePaths(String markdown) => [
  for (final match in _imageRef.allMatches(markdown))
    if ((match.group(2) ?? '').trim().isNotEmpty) (match.group(2) ?? '').trim(),
];

/// [markdown] met elk afbeeldingspad vervangen door wat [map] ervan maakt.
/// `null` (of hetzelfde pad) laat de verwijzing staan.
///
/// Alleen het pad verandert; de alt-tekst en de rest van de regel blijven
/// letterlijk staan. Dat is wat de aanroepers nodig hebben: kopiëren naar de
/// presentatiemap, poolen naar een `repo:`-verwijzing, en het opruimen van
/// duplicaten herschrijven allemaal het pad en verder niets.
String rewriteInlineImagePaths(
  String markdown,
  String? Function(String path) map,
) {
  if (markdown.isEmpty) return markdown;
  return markdown.replaceAllMapped(_imageRef, (match) {
    final alt = match.group(1) ?? '';
    final path = (match.group(2) ?? '').trim();
    if (path.isEmpty) return match.group(0)!;
    final replacement = map(path);
    if (replacement == null || replacement == path) return match.group(0)!;
    return '![$alt]($replacement)';
  });
}

/// De `image`-velden van de antwoorden in een `question`-blok herschreven via
/// [map]. Blijft [markdown] letterlijk als geen enkel antwoord-pad verlegt —
/// dan wordt het blok niet opnieuw geserialiseerd. De tegenhanger die
/// [slideImageRefs] leest, zit in de `questionImage`-tak daar.
String _rewriteQuestionAnswerImages(
  String markdown,
  String? Function(String path) map,
) {
  final decoded = _questionJson(markdown);
  if (decoded == null) return markdown;
  final answers = decoded['answers'];
  if (answers is! List<dynamic>) return markdown;
  var changed = false;
  for (final answer in answers) {
    if (answer is! Map<String, dynamic>) continue;
    final image = (answer['image'] ?? '').toString().trim();
    final replacement = image.isEmpty ? null : map(image);
    if (replacement == null || replacement == image) continue;
    answer['image'] = replacement;
    changed = true;
  }
  return changed
      ? const JsonEncoder.withIndent('  ').convert(decoded)
      : markdown;
}

Map<String, dynamic>? _questionJson(String markdown) {
  try {
    final decoded = jsonDecode(markdown.trim());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

Iterable<Map<String, dynamic>> _questionAnswerMaps(String markdown) sync* {
  final answers = _questionJson(markdown)?['answers'];
  if (answers is! List<dynamic>) return;
  for (final answer in answers) {
    if (answer is Map<String, dynamic>) yield answer;
  }
}

/// [slide] met élk afbeeldingspad vervangen door wat [map] ervan maakt — de
/// velden én de verwijzingen in de tekst. `null` laat een pad staan.
///
/// De tegenhanger van [slideImageRefs]: wie de verzameling kan lezen, moet hem
/// ook in zijn geheel kunnen herschrijven. Een aanroeper die alleen de velden
/// herschrijft, laat een inline afbeelding achter met een pad dat nergens meer
/// heen wijst.
Slide rewriteSlideImagePaths(Slide slide, String? Function(String path) map) {
  final image = slide.imagePath.trim();
  final image2 = slide.imagePath2.trim();
  final newImage = image.isEmpty ? null : map(image);
  final newImage2 = image2.isEmpty ? null : map(image2);
  // Een vraag-slide draagt JSON, geen Markdown: de inline-regex zou de
  // imagePair-antwoorden missen (#853). Herschrijf daar de `image`-velden in het
  // blok; overal elders de `![…](…)` in de vrije tekst.
  final newMarkdown = slide.type == SlideType.question
      ? _rewriteQuestionAnswerImages(slide.customMarkdown, map)
      : rewriteInlineImagePaths(slide.customMarkdown, map);
  if (newImage == null &&
      newImage2 == null &&
      newMarkdown == slide.customMarkdown) {
    return slide;
  }
  return slide.copyWith(
    imagePath: newImage,
    imagePath2: newImage2,
    customMarkdown: newMarkdown,
  );
}
