import '../../../utils/log.dart';
import '../models/conversion_issue.dart';

/// De naad waarlangs [guardParse] logt: de bewerking en het foutobject.
///
/// Standaard [logError]. Een test injecteert een eigen sink om te bewijzen dat
/// de guard alléén het fouttype doorgeeft en nooit de broninhoud (#877) — de
/// enige plek waar dat contract te toetsen valt.
typedef ParseLogSink = void Function(String op, Object error);

/// Isoleert een parse-fout tot het kleinste zinvolle onderdeel (#877).
///
/// De importers parsten hun dia's in één brede `try/catch`: één misvormde
/// relatie, grafiek, tabel of media-part liet daardoor de héle import mislukken.
/// [guardParse] draait één onderdeel-parse ([body]) en, als die worp:
///
///  - registreert het één [ConversionIssue] in [sink] met de vaste, vertaalbare
///    [feature]/[description] én de diagnostische [component]/[cause], zodat het
///    verlies op de notitiedia komt te staan — niets verdwijnt stil;
///  - logt **alleen** de bewerking, het onderdeel, de oorzaak en het *type* van
///    de fout, nooit het foutobject zelf. Een XML-/formaatfout draagt in zijn
///    boodschap een stuk van de ontlede brón mee, en dat kan bijzondere
///    persoonsgegevens zijn (acceptatiecriterium van #877);
///  - geeft [fallback] terug (standaard `null`) zodat de aanroeper doorgaat.
///
/// De aanroeper houdt zo per dia een lijst parse-issues bij die als
/// [SourceSlide.parseIssues] meereist; een fout in één onderdeel laat de rest
/// van de dia en alle volgende dia's intact.
T? guardParse<T>({
  required List<ConversionIssue> sink,
  required int slideIndex,
  required IssueComponent component,
  required String feature,
  required String description,
  required String logOp,
  required T? Function() body,
  T? fallback,
  ParseLogSink log = logError,
}) {
  try {
    return body();
  } on Object catch (error) {
    final cause = classifyParseCause(error);
    sink.add(
      ConversionIssue(
        slideIndex: slideIndex,
        feature: feature,
        description: description,
        component: component,
        cause: cause,
      ),
    );
    // Bewust het *type* en niet het foutobject: zie de klassenbeschrijving. Ook
    // de opgebouwde melding draagt alleen categorieën, geen brontekst.
    log(
      '$logOp — onderdeel ${component.name} overgeslagen '
      '(oorzaak: ${cause.name}, fouttype: ${error.runtimeType})',
      error.runtimeType,
    );
    return fallback;
  }
}

/// Zoals [guardParse], maar voor een onderdeel-parse zónder resultaat: de body
/// werkt puur via neveneffecten (velden vullen) en stopt vroegtijdig met een
/// kale `return;`. Scheelt het `return null` dat een `void`-body zou afkeuren.
void guardParseVoid({
  required List<ConversionIssue> sink,
  required int slideIndex,
  required IssueComponent component,
  required String feature,
  required String description,
  required String logOp,
  required void Function() body,
}) {
  guardParse<Object?>(
    sink: sink,
    slideIndex: slideIndex,
    component: component,
    feature: feature,
    description: description,
    logOp: logOp,
    body: () {
      body();
      return null;
    },
  );
}

/// Kies de oorzaakcategorie bij een [error] uit een onderdeel-parse.
///
/// Een [FormatException] (waaronder `XmlParserException`, die hem implementeert)
/// betekent onleesbare structuur; al het andere is een onverwachte fout. Een
/// ontbrekend onderdeel ([IssueCause.missingPart]) komt niet als worp binnen —
/// dat stelt de aanroeper zelf vast bij een `null`-part — en wordt daar
/// rechtstreeks genoteerd, niet via deze functie.
IssueCause classifyParseCause(Object error) =>
    error is FormatException ? IssueCause.malformedXml : IssueCause.unexpected;
