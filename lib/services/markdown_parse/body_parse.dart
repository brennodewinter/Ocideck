import '../../models/slide.dart';

/// Parseerstaat voor één slide-body: alle losse velden die [_parseBodyLines]
/// verzamelt vóór de type-inferentie ze tot een [Slide] bouwt. Eigen library
/// (verplaatst uit markdown_service_parse.dart voor het klasseplafond), dus
/// de naam is publiek.
class BodyParse {
  BodyParse(this.listStyle)
    : richTextHeaderPhase = listStyle == ListStyle.richText;

  String h1 = '';
  String h2 = '';
  String paragraph = '';
  String imagePath = '';
  String imagePath2 = '';
  String imageCaption = '';
  String imageCaption2 = '';

  /// De alt-tekst uit `![alt](pad)` — de Marp-vorm. Het
  /// `ocideck_image_alt`-commentaar wint als het er óók staat.
  String imageAlt = '';
  String imageAlt2 = '';
  int imageSize = 0;
  // Title-column side detection (#1405).
  bool sawBgLeft = false;
  bool sawBgRight = false;
  int bgLeftWidth = 0;
  int bgRightWidth = 0;

  String videoPath = '';
  bool videoAutoplay = false;
  int videoStartMs = 0;
  int videoEndMs = 0;
  String videoCaptions = '';
  String audioPath = '';
  bool audioAutoplay = false;
  String quote = '';

  /// Of er al een `>`-regel is gezien. Zonder dit is een citaat dat met een lege
  /// regel begint niet te onderscheiden van "nog geen citaat".
  bool quoteStarted = false;
  String quoteAuthor = '';
  final tableLines = <String>[];
  final richTextLines = <String>[];
  ListStyle listStyle;
  bool richTextHeaderPhase;

  /// Of er een item met een vinkje (`[x]`) of een nummer is gezien, en of er
  /// een gewoon item zonder allebei was. Samen laten ze de zichtbare opmaak de
  /// lijststijl ook naar bénéden bijstellen; zie [_MarkdownParse._parseBodyLines].
  bool sawMarkedItem = false;
  bool sawPlainItem = false;

  /// Of het blok de `split`-class draagt; één keer bepaald in
  /// [_MarkdownParse._parseBodyLines] zodat de per-regel handlers niet elke
  /// regel opnieuw de cssClass hoeven te splitsen.
  bool isSplit = false;

  /// Of we op dit moment binnen `<div class="split-image">` lezen — de stellage
  /// waar de serialiser de zij-afbeelding van een split-slide in zet.
  ///
  /// Nodig sinds de vrije tekst zélf afbeeldingen mag bevatten. Daarvóór gold
  /// "de eerste `![…]` op een split-slide is de zij-afbeelding", en dat is niet
  /// langer waar: een `![…]` in de `split-text`-helft is een afbeelding in de
  /// lopende tekst en hoort in de body te blijven staan.
  ///
  /// Veilig om op de stellage te leunen: deze tak geldt alleen voor een body met
  /// `<!-- ocideck_list_style: richText -->`, en die aanwijzing schrijft alleen
  /// OciDeck zelf — dus staat de `split-image`-div er ook. Een handgeschreven
  /// Marp-split-slide heeft geen richText-body en loopt langs de bullet-tak.
  bool inSplitImageDiv = false;
}
