// De privacyprojectie: de enige grens waarlangs een bron-Deck een ontvangend
// oppervlak bereikt.
//
// Het uitgangspunt is "niet beschikbaar is niet beschikbaar". Redactie is daarom
// GEEN renderingvlag maar een waarde-transformatie: de gevoelige tekens worden
// hier vervangen, vóór de splitsing naar preview, rasterizer, HTML,
// PPTX-notities en documentmetadata. Wat een widget of een exportbouwer in
// handen krijgt, bevat de oorspronkelijke tekens niet meer — er is dus geen
// tekstlaag onder een zwarte rechthoek, geen leesbare notitie in de PPTX-zip, en
// niets in de semantics-tree van een schermlezer.
//
// De grens wordt afgedwongen door het typesysteem: AudienceDeck heeft een
// private constructor en is alleen in deze library te maken. Een ontvangend
// oppervlak dat een AudienceDeck eist, kan de ongeredigeerde bron dus niet eens
// ontvangen — ook niet als een toekomstig exportformaat het zou proberen. Zie
// docs/design/PRIVACY_SHIELD.md §6.
//
// De bron blijft ongemoeid: wat de gebruiker opslaat is en blijft de
// oorspronkelijke markdown. Redactie geldt voor wat je *toont en exporteert*.

import '../../models/deck.dart';
import '../../models/slide.dart';

/// Het teken waarmee geredigeerde tekst wordt vervangen (U+2588 FULL BLOCK).
const String kRedactionBlock = '█';

/// Hoeveel blokken één redactie oplevert.
///
/// Bewust een **vaste** breedte en niet de lengte van het origineel: negen
/// blokjes waar een BSN stond en elf waar een IBAN stond, vertelt de ontvanger
/// welk soort gegeven er is weggehaald en hoe lang het was. Bij korte,
/// gestructureerde waarden komt dat gevaarlijk dicht bij reconstrueerbaar.
const int kRedactionBlockCount = 8;

/// De vervanging zoals die in de uitvoer verschijnt.
final String kRedactionToken = kRedactionBlock * kRedactionBlockCount;

/// De handmatige redactiemarkering in de bron: `[[tekst]]`.
///
/// Detectie is per definitie best-effort — wat de scanner niet ziet, redigeert
/// hij niet. Deze markering geeft de auteur het laatste woord, onafhankelijk van
/// welke detectieregel wel of niet vuurt. Geen geneste blokhaken, zodat een
/// gewone markdown-link (`[tekst](url)`) er niet in loopt.
final RegExp _manualRedaction = RegExp(r'\[\[([^\[\]]*)\]\]');

/// Een deck dat de privacyprojectie is gepasseerd.
///
/// Dit is het **enige** type dat de ontvangende oppervlakken accepteren
/// (preview, thumbnails, presentatie, publieksvenster, rasterizer, HTML-export,
/// PPTX-notities, documentmetadata). De constructor is private: alleen
/// [PrivacyProjection] kan er een maken, en dus kan geen enkel exportpad — ook
/// geen toekomstig — per ongeluk de ongeredigeerde bron in handen krijgen.
class AudienceDeck {
  /// Het geprojecteerde deck. De tekstvelden zijn hier al geredigeerd; dit is
  /// niet de bron.
  final Deck deck;

  /// Hoeveel redacties de projectie heeft toegepast. Voert de exportbanner en
  /// straks het redactiemanifest.
  final int redactionCount;

  const AudienceDeck._(this.deck, this.redactionCount);

  bool get hasRedactions => redactionCount > 0;

  List<Slide> get slides => deck.slides;
}

/// Tekst plus het aantal redacties dat erin is toegepast.
typedef RedactedText = ({String text, int count});

/// Bouwt een [AudienceDeck] uit een bron-[Deck].
class PrivacyProjection {
  const PrivacyProjection._();

  /// De projectie voor een menselijke ontvanger: publiek, lezer van de export.
  ///
  /// Redigeert wat de auteur met `[[…]]` heeft gemarkeerd. Zodra de scanner er
  /// is, respecteert deze projectie de per-slide dispositie: `accept` en
  /// `shield` laten gedetecteerde gegevens staan, `redact` haalt ze weg.
  static AudienceDeck forAudience(Deck deck) => _project(deck);

  /// De projectie voor verwerking buiten dit apparaat (AI-backends).
  ///
  /// Bewust **strenger** dan [forAudience], en straks ook feitelijk: dat de
  /// auteur besluit dat een zaal de namen mag zien, is geen toestemming om ze
  /// naar een extern model te sturen. Zodra de scanner er is, negeert deze
  /// projectie de dispositie en verwijdert álles wat gedetecteerd is. Nu doen
  /// beide projecties hetzelfde, omdat er nog alleen handmatige markeringen
  /// zijn — die gelden voor iedere ontvanger.
  static AudienceDeck forExternalProcessing(Deck deck) => _project(deck);

  static AudienceDeck _project(Deck deck) {
    var count = 0;

    String take(String source) {
      final result = redactText(source);
      count += result.count;
      return result.text;
    }

    final slides = <Slide>[];
    for (final slide in deck.slides) {
      final projected = _projectSlide(slide);
      count += projected.count;
      slides.add(projected.slide);
    }

    // De deckvelden die de documentmetadata voeden (titel, auteur, organisatie,
    // trefwoorden) reizen mee in PDF-properties en PPTX-docProps — leesbaar,
    // ook al staat er op de slide zelf niets van te zien.
    final projected = deck.copyWith(
      slides: slides,
      title: take(deck.title),
      author: take(deck.author),
      organization: take(deck.organization),
      description: take(deck.description),
      keywords: take(deck.keywords),
      userNotes: {
        for (final entry in deck.userNotes.entries)
          entry.key: take(entry.value),
      },
    );

    return AudienceDeck._(projected, count);
  }

  /// Projecteert elk tekstdragend veld van een slide.
  ///
  /// Sprekersnotities staan er nadrukkelijk bij: die zijn onzichtbaar in de
  /// preview, maar gaan als platte tekst mee in de PPTX-notitiepagina's.
  ///
  /// Een slide waarin iets is geredigeerd, verliest [Slide.tableEditable]. Dat
  /// is geen bijkomstigheid maar de kern van de grens: de presenter schrijft een
  /// live tabelbewerking als *hele slide* terug naar het deck
  /// (`presenter_table.dart`). Zou de presenter een geprojecteerde slide mogen
  /// terugschrijven, dan overschreef één bewerking de bron met blokken. Een
  /// oppervlak dat de gegevens niet kán zien, mag ze ook niet terugschrijven.
  static ({Slide slide, int count}) _projectSlide(Slide slide) {
    var count = 0;

    String take(String source) {
      final result = redactText(source);
      count += result.count;
      return result.text;
    }

    final projected = slide.copyWith(
      title: take(slide.title),
      subtitle: take(slide.subtitle),
      bullets: [for (final b in slide.bullets) take(b)],
      bullets2: [for (final b in slide.bullets2) take(b)],
      columnTitle1: take(slide.columnTitle1),
      columnTitle2: take(slide.columnTitle2),
      imageCaption: take(slide.imageCaption),
      imageCaption2: take(slide.imageCaption2),
      imageAltText: take(slide.imageAltText),
      imageAltText2: take(slide.imageAltText2),
      quote: take(slide.quote),
      quoteAuthor: take(slide.quoteAuthor),
      customMarkdown: take(slide.customMarkdown),
      notes: take(slide.notes),
      tableRows: [
        for (final row in slide.tableRows) [for (final cell in row) take(cell)],
      ],
    );

    return (
      slide: count > 0 ? projected.copyWith(tableEditable: false) : projected,
      count: count,
    );
  }

  /// Vervangt elke `[[…]]`-markering door de blokken en telt hoeveel het er
  /// waren. Puur: dezelfde invoer geeft altijd dezelfde uitvoer.
  static RedactedText redactText(String source) {
    if (!source.contains('[[')) return (text: source, count: 0);
    var count = 0;
    final text = source.replaceAllMapped(_manualRedaction, (_) {
      count++;
      return kRedactionToken;
    });
    return (text: text, count: count);
  }
}
