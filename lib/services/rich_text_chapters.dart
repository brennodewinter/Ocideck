/// Hoofdstukken in een vrije-tekstdia: een `#`-kop midden in de body opknippen
/// tot echte dia's.
///
/// In Marp ís `#` de titel van een dia. Een `#` halverwege een body is dus geen
/// opmaak maar een dia die niet is afgesloten: de lezer ziet een kop die zich
/// als titel voordoet zonder er een te zijn, en de auteur kan het hoofdstuk niet
/// verplaatsen, overslaan of apart presenteren. Opknippen maakt het bestand
/// standaarder, niet eigenzinniger — elke dia krijgt zijn eigen `# Titel`.
///
/// Wat hier NIET gebeurt: dit knippen bij het inlezen. Een deck dat vandaag
/// koppen in de body heeft, moet morgen ongewijzigd terugkomen; herstructureren
/// tijdens het parsen is stil dataverlies. Dit is een handeling die de auteur
/// aanzet, niet iets dat het bestand overkomt.
library;

import '../models/slide.dart';

/// Een `#`-kop op een eigen regel. Alleen niveau 1: `##` blijft een kop bínnen
/// de dia (en bovenaan de ondertitel), zoals de parser hem ook leest.
final _chapterHeading = RegExp(r'^#\s+(.*)$');

/// Een `##`-kop, voor de ondertitel direct onder een hoofdstukkop.
final _subHeading = RegExp(r'^##\s+(.*)$');

/// Een code-afbakening (```): een `#` daarbinnen is broncode, geen hoofdstuk.
final _codeFence = RegExp(r'^\s*```');

/// Of [slide] een dia is waarvan de vrije tekst in hoofdstukken te knippen valt.
///
/// Bewust niet `bulletsImage`: daar hoort de afbeelding bij déze tekst, en of
/// hij bij het eerste hoofdstuk blijft, meeverhuist of verdwijnt is een keuze
/// die alleen de auteur kan maken. Iets aanbieden dat die keuze stilzwijgend
/// voor hem invult, is erger dan het niet aanbieden.
bool slideSplitsIntoChapters(Slide slide) =>
    slide.type == SlideType.bullets && slide.listStyle == ListStyle.richText;

/// De hoofdstukkoppen in [markdown], in leesvolgorde. Leeg wanneer er niets te
/// knippen valt.
///
/// Een kop op de eerste regel telt niet mee als hoofdstuk: die is de titel van
/// deze dia en levert geen tweede dia op — precies wat de parser er bij het
/// inlezen ook van maakt.
List<String> richTextChapterHeadings(String markdown) {
  final headings = <String>[];
  var inFence = false;
  var seenContent = false;
  for (final line in markdown.split('\n')) {
    if (_codeFence.hasMatch(line)) {
      inFence = !inFence;
      seenContent = true;
      continue;
    }
    if (inFence) continue;
    final heading = _chapterHeading.firstMatch(line);
    // `## ` matcht `_chapterHeading` niet (die eist witruimte na de ene `#`),
    // dus een subkop komt hier niet langs.
    if (heading != null) {
      if (seenContent) headings.add((heading.group(1) ?? '').trim());
      seenContent = true;
      continue;
    }
    if (line.trim().isNotEmpty) seenContent = true;
  }
  return headings;
}

/// Hoeveel dia's [slide] oplevert als je hem op zijn hoofdstukken knipt. 1 als
/// er niets te knippen valt.
int richTextChapterCount(Slide slide) {
  if (!slideSplitsIntoChapters(slide)) return 1;
  return richTextChapterHeadings(slide.customMarkdown).length + 1;
}

/// [slide] opgeknipt op zijn `#`-koppen: één dia per hoofdstuk, met de kop als
/// titel. Levert `[slide]` terug als er niets te knippen valt.
///
/// De tekst vóór het eerste hoofdstuk blijft bij de huidige dia, die zijn titel
/// en ondertitel houdt. Begint de body juist mét een kop en heeft de dia nog
/// geen titel, dan wordt die kop de titel van déze dia — geen lege eerste dia,
/// en hetzelfde resultaat als opslaan en heropenen zou geven.
///
/// Een `##` direct onder een hoofdstukkop wordt de ondertitel van die dia. Niet
/// uit netheid: de parser tilt hem er bij het volgende inlezen tóch uit, en dan
/// zou de dia na één keer opslaan anders ogen dan direct na het knippen.
List<Slide> splitRichTextIntoChapters(Slide slide) {
  if (!slideSplitsIntoChapters(slide)) return [slide];
  final lines = slide.customMarkdown.split('\n');

  // Elk stuk: (titel, ondertitel, regels). Het eerste stuk heeft nog geen eigen
  // kop — dat is de tekst waar de dia al mee begon.
  final chunks = <({String? title, String? subtitle, List<String> lines})>[
    (title: null, subtitle: null, lines: <String>[]),
  ];
  var inFence = false;
  var seenContent = false;
  for (final line in lines) {
    if (_codeFence.hasMatch(line)) {
      inFence = !inFence;
      seenContent = true;
      chunks.last.lines.add(line);
      continue;
    }
    if (!inFence) {
      final heading = _chapterHeading.firstMatch(line);
      if (heading != null) {
        final title = (heading.group(1) ?? '').trim();
        if (!seenContent) {
          // Een kop op de eerste regel: de titel van deze dia, geen nieuwe dia.
          chunks[0] = (title: title, subtitle: null, lines: <String>[]);
        } else {
          chunks.add((title: title, subtitle: null, lines: <String>[]));
        }
        seenContent = true;
        continue;
      }
      // De eerste `##` onder een verse hoofdstukkop is de ondertitel.
      final sub = _subHeading.firstMatch(line);
      if (sub != null &&
          chunks.last.title != null &&
          chunks.last.subtitle == null &&
          chunks.last.lines.every((l) => l.trim().isEmpty)) {
        chunks[chunks.length - 1] = (
          title: chunks.last.title,
          subtitle: (sub.group(1) ?? '').trim(),
          lines: chunks.last.lines,
        );
        continue;
      }
    }
    if (line.trim().isNotEmpty) seenContent = true;
    chunks.last.lines.add(line);
  }

  if (chunks.length == 1 && chunks.first.title == null) return [slide];

  final out = <Slide>[];
  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    final body = chunk.lines.join('\n').trim();
    // Een leeg eerste stuk (de body begon meteen met een hoofdstuk, terwijl de
    // dia al een titel had) levert geen lege dia op.
    if (i == 0 && body.isEmpty && chunk.title == null) continue;
    // De eerste dia is de bestaande dia — zelfde id, zodat annotaties en
    // notities die eraan hangen niet losraken. De rest zijn nieuwe dia's.
    final base = out.isEmpty ? slide : Slide.duplicate(slide);
    out.add(
      base.copyWith(
        title: chunk.title ?? (out.isEmpty ? slide.title : ''),
        subtitle: chunk.subtitle ?? (out.isEmpty ? slide.subtitle : ''),
        customMarkdown: body,
      ),
    );
  }
  return out.isEmpty ? [slide] : out;
}
