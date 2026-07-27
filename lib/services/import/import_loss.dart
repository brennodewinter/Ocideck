import '../../models/slide.dart';
import 'models/body_block.dart';
import 'models/conversion_issue.dart';
import 'models/source_slide.dart';
import 'pipeline/problem_slide.dart';
import 'pipeline/slide_classifier.dart';
import 'slide_factory.dart';

/// The conversion issues to note after slide [c]: the importer's own
/// parse-time losses (a chart/table/media/notes part or the whole slide that
/// could not be read — #877), the classifier's per-slide issues, and the
/// builder's structural salvage losses (audio, a table beside a chart).
List<ConversionIssue> conversionIssuesFor(ClassifiedSlide c) => [
  ...c.source.parseIssues,
  ...c.issues,
  ...salvageIssues(c.source),
  ...droppedContentIssues(c),
  ...neutralisedLinkIssues(c.source),
];

/// Inhoud die de veldafbeelding van het gekozen dia-type laat vallen.
///
/// Dit is de tweede helft van de belofte "niets verdwijnt stil". De
/// classifier meldt wat híj niet kwijt kan, maar daarna gooit de bouwer zélf
/// nog dingen weg — een inleidende alinea boven een bullet-lijst, de derde
/// afbeelding, bullets naast een tabel — en dat gebeurde zonder één woord.
/// Een gebruiker die zijn dia terugziet zonder die alinea heeft geen enkele
/// aanwijzing dat de import hem heeft laten vallen.
///
/// De regel is: meld alleen wat dit type werkelijk niet leest. Verlies
/// mélden dat er niet is, is even schadelijk als het verzwijgen — dan gaat
/// de gebruiker zoeken naar iets wat gewoon op zijn dia staat.
List<ConversionIssue> droppedContentIssues(ClassifiedSlide c) {
  final s = c.source;
  final issues = <ConversionIssue>[];

  int countOf(BodyBlockKind kind) =>
      s.bodyBlocks.where((b) => b.kind == kind).length;

  // Alinea's. Alleen `section` (in de ondertitel) en `freeMarkdown` (in de
  // body) nemen ze mee; `quote` leest uitsluitend het quote-blok.
  const readsParagraphs = {SlideType.section, SlideType.freeMarkdown};
  final paragraphs = countOf(BodyBlockKind.paragraph);
  if (paragraphs > 0 && !readsParagraphs.contains(c.type)) {
    issues.add(
      ConversionIssue(
        slideIndex: s.index,
        feature: paragraphs == 1 ? 'Alinea' : '{n} alinea’s',
        description:
            'niet overgenomen (een {type}-dia toont geen losse '
            'alineatekst)',
        args: {'n': '$paragraphs', 'type': c.type.name},
      ),
    );
  }

  // Bullets. Alles wat op een bullet-lijst uitkomt leest ze; de rest niet.
  const readsBullets = {
    SlideType.bullets,
    SlideType.twoBullets,
    SlideType.bulletsImage,
    SlideType.timeline,
    SlideType.freeMarkdown,
  };
  final bullets = countOf(BodyBlockKind.bullet);
  if (bullets > 0 && !readsBullets.contains(c.type)) {
    issues.add(
      ConversionIssue(
        slideIndex: s.index,
        feature: bullets == 1 ? '{n} opsommingspunt' : '{n} opsommingspunten',
        description:
            'niet overgenomen (deze dia werd een {type}, en die '
            'draagt geen opsomming)',
        args: {'n': '$bullets', 'type': c.type.name},
      ),
    );
  }

  // Afbeeldingen voorbij wat het type toont.
  final shown = switch (c.type) {
    SlideType.twoImages => 2,
    SlideType.image || SlideType.bulletsImage || SlideType.title => 1,
    // freeMarkdown lijkt alles te dragen, maar `_freeMarkdownBody` schrijft
    // alleen tekst, koppen en links — geen afbeeldingen. Dus: nul.
    _ => 0,
  };
  if (s.images.length > shown) {
    final extra = s.images.length - shown;
    issues.add(
      ConversionIssue(
        slideIndex: s.index,
        feature: extra == 1 ? '{n} afbeelding' : '{n} afbeeldingen',
        description: shown == 0
            ? 'niet overgenomen (deze dia werd een {type})'
            : 'niet overgenomen (een {type}-dia toont er {aantal})',
        args: {'n': '$extra', 'type': c.type.name, 'aantal': '$shown'},
      ),
    );
  }

  return issues;
}

/// Losses that OciDeck's model cannot represent, so the note slide can name
/// them. Ported from Keiko's pipeline salvage checks.
List<ConversionIssue> salvageIssues(SourceSlide s) {
  final issues = <ConversionIssue>[];
  if (s.audioFileName != null) {
    issues.add(
      ConversionIssue(
        slideIndex: s.index,
        feature: 'Audio "{bestand}"',
        description: 'niet overgenomen (OciDeck heeft geen audio-slides)',
        args: {'bestand': s.audioFileName!},
      ),
    );
  }
  if (s.chart != null && s.table != null) {
    issues.add(
      ConversionIssue(
        slideIndex: s.index,
        feature: 'Tabel naast grafiek',
        description: 'niet overgenomen (één grafiek of tabel per slide)',
      ),
    );
  }
  return issues;
}

/// Links waarvan het doel is weggehaald, zodat de notitiedia ze kan noemen.
///
/// Het schema neutraliseren is niet onderhandelbaar — een `javascript:`-link
/// uit een vreemd bestand hoort niet in het deck van de gebruiker. Maar het
/// doel spoorloos vervangen door `https://invalid` is dat wél: de linktekst
/// blijft staan, en de gebruiker kan niet eens zien wát er stond. Voor een
/// `file:`-verwijzing in een interne presentatie is dat gewone inhoud.
/// Daarom: neutraliseren én opschrijven.
List<ConversionIssue> neutralisedLinkIssues(SourceSlide s) => [
  for (final link in s.hyperlinks)
    if (isUnsafeUrl(link.url))
      ConversionIssue(
        slideIndex: s.index,
        feature: 'Koppeling “{tekst}”',
        description: 'doel onschadelijk gemaakt; het wees naar {url}',
        salvagedAs: 'de tekst blijft staan, de verwijzing niet',
        // De linktekst en het doel belanden in de notitiedia; die wordt door
        // `UnconvertedTracker._escMarkdown` al geneutraliseerd (HTML, de
        // Markdown-metatekens en regeleinden), dus hier géén tweede escaping —
        // dat leverde alleen `&amp;amp;lt;` op (#876).
        args: {'tekst': link.text, 'url': link.url.trim()},
      ),
];

ProblemSlide problemSlide(SourceSlide s, List<ConversionIssue> realLoss) =>
    ProblemSlide(
      sourceSlideNumber: s.index + 1,
      title: s.title.isNotEmpty ? s.title : null,
      issueDescriptions: [
        for (final i in realLoss) '${i.feature}: ${i.description}',
      ],
      hadImage: s.images.isNotEmpty,
    );
