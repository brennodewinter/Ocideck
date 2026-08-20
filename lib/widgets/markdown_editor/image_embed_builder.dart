import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../theme/app_theme.dart';
import '../../utils/image_embed_syntax.dart';

/// Tekent een `x-embed-image` in de visuele (Quill) editor: een merkteken op de
/// plek van de afbeelding, met de alt-tekst erin.
///
/// **Niet de afbeelding zelf, en dat is een bewuste grens.** Een pad in een
/// document kan `mem:`, `asset:` of relatief-aan-het-deck zijn, en het uitzoeken
/// daarvan hoort bij `ImageService` met de map van het deck erbij — die staat
/// het schrijfvlak niet ter beschikking. De documentlezer tekent afbeeldingen
/// vandaag óók niet; wél de HTML- en PDF-uitvoer. Zolang die twee uit elkaar
/// lopen, is het eerlijker om te tonen *dát* er een afbeelding staat en welke,
/// dan om er in één van de twee weergaven een te verzinnen.
///
/// Wat deze bouwer wél oplost is de reden dat hij bestaat: zonder bouwer voor
/// dit type wierp Quill `UnimplementedError` en viel het hele schrijfvlak om.
class ImageEmbedBuilder extends EmbedBuilder {
  const ImageEmbedBuilder();

  @override
  String get key => EmbeddableMarkdownImage.imageType;

  /// Een afbeelding staat op zijn plek in de zin, niet op een eigen regel.
  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final image = EmbeddableMarkdownImage.parse(embedContext.node.value);
    final style = DefaultTextStyle.of(context).style;
    final ink = style.color ?? AppTheme.ink;
    // De alt-tekst is waar hij voor bedoeld is: de omschrijving. Ontbreekt hij,
    // dan is de bestandsnaam het eerlijkste alternatief — en géén verzonnen
    // woord, want dan zou hier vertaalde interfacetekst in de lopende zin van
    // de gebruiker staan.
    final label = image.alt.trim().isNotEmpty
        ? image.alt.trim()
        : _fileName(image.source);
    return Semantics(
      image: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppTheme.inlineCodeBackground(ink),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: (style.fontSize ?? 15) + 1,
              color: ink,
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(label, style: style),
            ],
          ],
        ),
      ),
    );
  }

  /// `assets/beelden/plaatje.png` → `plaatje.png`. Werkt op beide scheidings-
  /// tekens, want een pad uit een Windows-document draagt backslashes.
  static String _fileName(String source) {
    final cut = source.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? source : source.substring(cut + 1);
  }
}

/// De vangnet-bouwer: tekent een embed waar geen bouwer voor bestaat als zijn
/// eigen inhoud, in plaats van het schrijfvlak te laten omvallen.
///
/// Quill werpt bij een onbekend embed-type een `UnimplementedError` **tijdens
/// het bouwen van de regel**, en dat is niet één stukgelopen alinea: het
/// document is weg en er staat een foutscherm. Precies dat overkwam een
/// afbeelding ([ImageEmbedBuilder] draagt het verhaal). Een type dat hier langs
/// komt is een gat — maar een gat hoort een zichtbaar rafeltje te zijn, geen
/// dichtgeslagen deur.
class FallbackEmbedBuilder extends EmbedBuilder {
  const FallbackEmbedBuilder();

  /// Niet gebruikt: Quill kiest deze bouwer juist wanneer geen enkele sleutel
  /// past. Hij moet alleen niet met een echte sleutel botsen.
  @override
  String get key => 'x-embed-onbekend';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final value = embedContext.node.value;
    final text = (value.data ?? '').toString().trim();
    final style = DefaultTextStyle.of(context).style;
    final ink = style.color ?? AppTheme.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.inlineCodeBackground(ink),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text.isEmpty ? value.type : text, style: style),
    );
  }
}
