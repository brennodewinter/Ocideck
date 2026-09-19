// Wat een Word- of LibreOffice-document aan huisstijl draagt, zoals de
// importeur het aantreft — nog vóór er een stijlprofiel van gemaakt is.
//
// Bewust een tussenmodel en geen `ThemeProfile`: hier staan de *gevraagde*
// letters (`Aptos`) en de ruwe kleuren uit het bestand. Pas de profielbouwer
// (`imported_document_profile.dart`) kiest er een plaatsvervanger bij en laat
// alles door de hardende `ThemeProfile.fromJson`-poort gaan. Zo kan de dialoog
// tonen wat er in de bron stond én wat OciDeck ervan maakt.

import 'dart:typed_data';

/// De rand van het blad waar een herhaald beeld stond.
enum DocumentLogoEdge { top, bottom }

/// De kant van het blad waar een herhaald beeld stond.
enum DocumentLogoSide { left, right }

/// Uit welk deel van het brondocument een logokandidaat komt.
enum DocumentLogoOrigin {
  /// De standaardkoptekst: structureel op elke bladzijde.
  header,

  /// De standaardvoettekst: structureel op elke bladzijde.
  footer,

  /// Een beeld dat in de lopende tekst zelf per bladzijde herhaald is.
  body,
}

/// Eén beeld dat op (nagenoeg) elke bladzijde van het brondocument staat.
class DocumentLogoCandidate {
  const DocumentLogoCandidate({
    required this.bytes,
    required this.ext,
    required this.sha256,
    required this.edge,
    required this.side,
    required this.widthMm,
    required this.origin,
    this.centred = false,
    this.name,
    this.occurrences,
  });

  final Uint8List bytes;

  /// Bestandsextensie zonder punt (`png`, `jpeg`).
  final String ext;

  /// Inhoudshash, om een bekend logo in een bestaand profiel te herkennen.
  final String sha256;
  final DocumentLogoEdge edge;
  final DocumentLogoSide side;

  /// Of het beeld in de bron gecentreerd stond. Het profiel kent alleen links
  /// en rechts; [side] is dan links en de dialoog zegt het erbij.
  final bool centred;

  /// De breedte waarop het beeld in de bron getekend werd.
  final double widthMm;
  final DocumentLogoOrigin origin;
  final String? name;

  /// Hoe vaak het beeld in de tekst zelf voorkomt; `null` voor een kop- of
  /// voettekstbeeld, dat niet per bladzijde geteld wordt.
  final int? occurrences;

  /// De waarde voor `ThemeProfile.documentLogoPosition`.
  String get position => '${edge.name}-${side.name}';
}

/// Wat een documentstijl níét kon overnemen — de dialoog vertaalt deze naar
/// een zin, zodat er geen tekst in deze headless laag staat.
enum DocumentStyleLossKind {
  /// Een kopniveau onder 1 had een eigen kleur; het profiel kent één kopkleur.
  perLevelHeadingColor,

  /// Een beeld in de kop- of voettekst van alleen het titelblad.
  titlePageImage,

  /// Een gecentreerd logo; het profiel kent alleen links en rechts.
  centredLogo,

  /// Een kop- of voettekstbeeld dat geen rasterbeeld is (SVG zonder terugval).
  vectorOnlyLogo,
}

/// Eén verlies, met het detail dat de zin nodig heeft (een kopniveau, een
/// kleur).
class DocumentStyleLoss {
  const DocumentStyleLoss(this.kind, {this.detail});

  final DocumentStyleLossKind kind;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is DocumentStyleLoss &&
      other.kind == kind &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);

  @override
  String toString() => 'DocumentStyleLoss(${kind.name}, $detail)';
}

/// De huisstijl zoals het brondocument haar draagt.
///
/// Elk veld is optioneel: een document zonder thema, zonder kopstijl of
/// zonder voettekst levert `null`, en een stijl waar niets in zit ([isEmpty])
/// hoeft de gebruiker niet eens te zien.
class SourceDocumentStyle {
  const SourceDocumentStyle({
    this.bodyFontFamily,
    this.headingFontFamily,
    this.textColor,
    this.headingColor,
    this.accentColor,
    this.headerText,
    this.footerText,
    this.showPageNumbers = false,
    this.logoCandidates = const [],
    this.losses = const [],
  });

  static const empty = SourceDocumentStyle();

  /// De letter van de lopende tekst, zoals de bron haar noemt.
  final String? bodyFontFamily;

  /// De letter van de koppen (Heading 1), zoals de bron haar noemt.
  final String? headingFontFamily;

  /// `#RRGGBB`, of `null` als de bron niets zet.
  final String? textColor;
  final String? headingColor;
  final String? accentColor;

  /// Tekst van de standaardkop- en -voettekst, zonder velden en tekstkaders.
  final String? headerText;
  final String? footerText;

  /// Of de standaardvoettekst (of -koptekst) een paginanummerveld bevat.
  final bool showPageNumbers;

  final List<DocumentLogoCandidate> logoCandidates;
  final List<DocumentStyleLoss> losses;

  /// Of er iets is om over te nemen. Een verlies alléén telt niet: dat is een
  /// melding over iets dat er niet komt, niet iets dat er wel komt.
  bool get isEmpty =>
      bodyFontFamily == null &&
      headingFontFamily == null &&
      textColor == null &&
      headingColor == null &&
      accentColor == null &&
      headerText == null &&
      footerText == null &&
      !showPageNumbers &&
      logoCandidates.isEmpty;

  bool get isNotEmpty => !isEmpty;
}
