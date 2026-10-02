// Wat de invulpagina nodig heeft om de inzending als pakket op te slaan
// (FORM_INTAKE.md §5.2), zonder zelf bestanden of vensters te kennen. Het tabblad
// geeft het mee; in een test is het een nepje.
//
// Het pakket moet weten wat het gepubliceerde formulier was: de tekst buiten de
// antwoorden en de hash in het manifest horen daarbij. Het document zelf is dat
// niet meer zodra er een antwoord in staat. Daarom onthoudt de ondersteuning het
// formulier zoals het geopend werd zolang het nog leeg was ([remember]), en vraagt
// de invuller anders om het bestand dat hij van de organisator kreeg ([pickPublished]).

import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

class FormExportSupport {
  const FormExportSupport({
    required this.frontMatter,
    required this.readImage,
    required this.pickPublished,
    required this.save,
    required this.recall,
    required this.remember,
    this.clientVersion,
  });

  /// De front matter van het document; de pagina zelf werkt alleen met de tekst
  /// eronder, het pakket bevat het hele bestand.
  final String frontMatter;

  /// De bytes van een foto op zijn pad in het antwoord, of `null`.
  final Future<Uint8List?> Function(String path) readImage;

  /// Laat de invuller het formulier kiezen zoals hij het kreeg; geeft de hele
  /// tekst van het bestand, of `null` als hij annuleert of het niet te lezen is.
  final Future<String?> Function() pickPublished;

  /// Bewaart het pakket. Geeft de naam waaronder het is opgeslagen, `null` als de
  /// invuller annuleert; een mislukte schrijfactie is een uitzondering.
  final Future<String?> Function(String fileName, Uint8List bytes) save;

  /// Het gepubliceerde formulier (hele tekst) dat bij [spec] hoort, zoals eerder
  /// onthouden, of `null`.
  final String? Function(FormSpec spec) recall;

  /// Onthoudt [published] (hele tekst) als het gepubliceerde formulier van [spec].
  final void Function(FormSpec spec, String published) remember;

  /// Het versienummer van OciDeck voor het manifest; `null` laat het weg.
  final String? clientVersion;
}
