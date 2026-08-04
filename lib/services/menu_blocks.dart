// Keuze-menu-blokken (#1162).
//
// Een menudia bewaart zijn blokken als gewone bullets in [Slide.bullets], elk
// een stukje Markdown: `[label](#anker)` voor een blok dat naar een dia springt,
// optioneel gevolgd door `![](mem:…)` voor een afbeelding, of gewoon platte tekst
// voor een blok zonder doel. Zo blijft een menu een leesbare linklijst in elke
// Markdown-lezer, en round-trippt het verliesvrij via de bestaande bullet-opslag.
//
// Dit bestand is de enige plek die dat stukje Markdown leest en schrijft — puur,
// zonder Flutter, zodat editor, preview, presentator en beamer dezelfde
// interpretatie delen en het los te toetsen valt.

import '../models/slide.dart';
import 'slide_anchors.dart';

/// Eén blok op een keuze-menudia: een label, optioneel een doel-anker (leeg =
/// een gewoon tekstblok dat nergens heen springt) en optioneel een afbeelding.
class MenuBlock {
  final String label;

  /// Het [Slide.anchor] van de doeldia, zonder de `#`. Leeg = geen sprong.
  final String targetAnchor;

  /// `mem:`- of asset-pad van de blokafbeelding. Leeg = geen afbeelding.
  final String imagePath;

  const MenuBlock({
    this.label = '',
    this.targetAnchor = '',
    this.imagePath = '',
  });

  bool get hasTarget => targetAnchor.isNotEmpty;
  bool get hasImage => imagePath.isNotEmpty;

  MenuBlock copyWith({
    String? label,
    String? targetAnchor,
    String? imagePath,
  }) => MenuBlock(
    label: label ?? this.label,
    targetAnchor: targetAnchor ?? this.targetAnchor,
    imagePath: imagePath ?? this.imagePath,
  );

  @override
  bool operator ==(Object other) =>
      other is MenuBlock &&
      other.label == label &&
      other.targetAnchor == targetAnchor &&
      other.imagePath == imagePath;

  @override
  int get hashCode => Object.hash(label, targetAnchor, imagePath);
}

final _reMenuLink = RegExp(r'\[([^\]]*)\]\(#([^)]*)\)');
final _reMenuImage = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');

/// Lees één bullet-tekst als [MenuBlock]. Een `[label](#anker)` levert label +
/// anker; een `![](pad)` levert de afbeelding; wat overblijft (of een bullet
/// zonder link) is het platte label. Fail-safe: onbekende opmaak wordt gewoon het
/// label, nooit een fout.
MenuBlock parseMenuBlock(String bullet) {
  // Eerst de afbeelding eruit halen, zodat hij niet in het label blijft plakken.
  final imageMatch = _reMenuImage.firstMatch(bullet);
  final imagePath = imageMatch?.group(1)?.trim() ?? '';
  final withoutImage = bullet.replaceAll(_reMenuImage, '').trim();

  final linkMatch = _reMenuLink.firstMatch(withoutImage);
  if (linkMatch != null) {
    return MenuBlock(
      label: linkMatch.group(1)!.trim(),
      targetAnchor: linkMatch.group(2)!.trim(),
      imagePath: imagePath,
    );
  }
  return MenuBlock(label: withoutImage, imagePath: imagePath);
}

/// Schrijf een [MenuBlock] terug als bullet-tekst — de tegenhanger van
/// [parseMenuBlock], zodat een rondgang door de editor niets verliest.
String menuBlockToBullet(MenuBlock block) {
  final head = block.hasTarget
      ? '[${block.label}](#${block.targetAnchor})'
      : block.label;
  return block.hasImage ? '$head ![](${block.imagePath})' : head;
}

/// Alle blokken van een menudia, in volgorde.
List<MenuBlock> menuBlocksFor(List<String> bullets) => [
  for (final b in bullets) parseMenuBlock(b),
];

/// De dia-lijst nadat menublok [blockIndex] van de menudia [menuIndex] naar dia
/// [targetIndex] is gaan wijzen (`null` = geen doel meer). De doeldia krijgt zo
/// nodig een uniek, bevroren anker — de gebruiker kiest een dia, niet een anker.
/// `null` terug = er verandert niets (ongeldige index of sprong naar de menudia
/// zelf). Puur over de lijst zodat de notifier alleen hoeft te muteren.
List<Slide>? slidesWithMenuTarget(
  List<Slide> slides,
  int menuIndex,
  int blockIndex,
  int? targetIndex,
) {
  if (menuIndex < 0 || menuIndex >= slides.length) return null;
  final blocks = menuBlocksFor(slides[menuIndex].bullets);
  if (blockIndex < 0 || blockIndex >= blocks.length) return null;
  final out = List<Slide>.from(slides);

  var anchor = '';
  if (targetIndex != null) {
    if (targetIndex < 0 ||
        targetIndex >= out.length ||
        targetIndex == menuIndex) {
      return null;
    }
    var target = out[targetIndex];
    if (target.anchor.isEmpty) {
      final taken = {
        for (final s in out)
          if (s.anchor.isNotEmpty) s.anchor,
      };
      target = target.copyWith(
        anchor: uniqueAnchor(slugifyAnchor(target.title), taken),
      );
      out[targetIndex] = target;
    }
    anchor = target.anchor;
  }

  final updated = [...blocks];
  updated[blockIndex] = updated[blockIndex].copyWith(targetAnchor: anchor);
  out[menuIndex] = out[menuIndex].copyWith(
    bullets: [for (final b in updated) menuBlockToBullet(b)],
  );
  return out;
}
