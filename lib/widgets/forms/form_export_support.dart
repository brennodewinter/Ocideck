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
    this.seal,
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

  /// Wat het verzegeld opslaan nodig heeft, of `null` waar dat niet kan (het web: de
  /// age-bibliotheek draait daar nog niet) — dan is er alleen de gewone zip.
  final FormSealSupport? seal;
}

/// Wat de invulpagina nodig heeft om een inzending **verzegeld** op te slaan (FORM_INTAKE.md
/// §5.1, §5.6): het bundelbestand van de organisator, wat de invuller al van zijn bundels zag
/// (de pins tegen terugval), en wat hij al intikte voor dit formulier. De vingerafdruk zelf
/// vraagt de pagina in een venster; die komt nooit uit het bundelbestand.
class FormSealSupport {
  const FormSealSupport({
    required this.pickBundle,
    required this.readPins,
    required this.writePins,
    required this.recall,
    required this.remember,
    required this.forget,
  });

  /// Laat de invuller het bundelbestand kiezen; geeft de hele tekst, of `null` als hij
  /// annuleert of het niet te lezen is.
  final Future<String?> Function() pickBundle;

  /// Het hoogste volgnummer dat de invuller per formulier en organisator al zag.
  final Future<FormBundlePins> Function() readPins;

  /// Bewaart de pins na een bundel die is geloofd.
  final Future<void> Function(FormBundlePins pins) writePins;

  /// De bundel en vingerafdruk die bij [spec] eerder werkten, of `null`: wat de invuller bij
  /// een volgende keer niet opnieuw hoeft te kiezen en in te typen.
  final ({String bundle, String fingerprint})? Function(FormSpec spec) recall;

  /// Onthoudt de bundel en vingerafdruk die tot een verzegelde inzending leidden.
  final void Function(FormSpec spec, String bundle, String fingerprint)
  remember;

  /// Vergeet wat bij [spec] onthouden was: het werkte niet meer.
  final void Function(FormSpec spec) forget;
}
