// Wat de invulpagina nodig heeft om met foto's te werken, zonder zelf bestanden te
// kennen. Het tabblad geeft het mee (map van het document, bestandskiezer); in een
// test is het een nepje, en een document zonder map — nog niet opgeslagen, of het
// web — geeft het niet mee, waarna de pagina zegt dat het document eerst moet
// worden opgeslagen.

import 'package:flutter/painting.dart' show ImageProvider;
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../services/form/form_image_service.dart';

class FormImageSupport {
  const FormImageSupport({
    required this.add,
    required this.probe,
    required this.preview,
  });

  /// Laat de invuller foto's voor [fieldId] kiezen en verwerkt ze (zuiveren,
  /// controleren, opslaan). `null` als hij annuleert. [taken] zijn de paden die in
  /// het antwoord al staan.
  final Future<FormImageBatch?> Function(String fieldId, Set<String> taken) add;

  /// Meet foto's die al in het document staan.
  final Future<Map<String, FormImageFact>> Function(Iterable<String> paths)
  probe;

  /// Een klein voorbeeld van de foto op [path], of `null`.
  final ImageProvider? Function(String path) preview;
}
