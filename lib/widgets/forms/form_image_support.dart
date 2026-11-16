// Wat de invulpagina nodig heeft om met foto's te werken, zonder zelf bestanden te
// kennen. Het tabblad geeft het mee (map van het document, bestandskiezer); in een
// test is het een nepje, en een document zonder map — nog niet opgeslagen, of het
// web — geeft het niet mee, waarna de pagina zegt dat het document eerst moet
// worden opgeslagen.

import 'dart:typed_data';

import 'package:flutter/painting.dart' show ImageProvider;
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../services/form/form_image_service.dart';

class FormImageSupport {
  const FormImageSupport({
    required this.add,
    required this.probe,
    required this.preview,
    this.addReaders,
    this.presets = const {},
  });

  /// Laat de invuller foto's voor [fieldId] kiezen en verwerkt ze (zuiveren,
  /// controleren, opslaan). `null` als hij annuleert. [taken] zijn de paden die in
  /// het antwoord al staan.
  final Future<FormImageBatch?> Function(String fieldId, Set<String> taken) add;

  /// Hetzelfde als [add], maar dan voor bytes die al binnen zijn — klembord,
  /// tekening, stijllogo. `null` waar de map ontbreekt.
  final Future<FormImageBatch?> Function(
    String fieldId,
    Set<String> taken,
    List<Future<Uint8List> Function()> readers,
  )?
  addReaders;

  /// Klaargezette bronnen per veld: het logo-veld van een PE-bewijs toont de
  /// logo's van de stijlprofielen. Sleutel is het veld-id.
  final Map<String, List<FormImagePreset>> presets;

  /// Meet foto's die al in het document staan.
  final Future<Map<String, FormImageFact>> Function(Iterable<String> paths)
  probe;

  /// Een klein voorbeeld van de foto op [path], of `null`.
  final ImageProvider? Function(String path) preview;
}

/// Een klaargezette afbeeldingsbron: een label voor in het menu en een lezer
/// voor de bytes — die gaan door dezelfde zuivering en controle als een
/// gekozen bestand.
typedef FormImagePreset = ({String label, Future<Uint8List> Function() read});

/// Wat een beeldveld kan toevoegen: uit de kiezer, van losse bytes (klembord,
/// tekening, stijllogo), of uit de [presets] die bij het veld horen. De veldkaart
/// krijgt dit als geheel mee, zodat nieuwe bronnen niet telkens nieuwe parameters
/// door de keten vragen.
typedef FormImageAdders = ({
  Future<List<FormImageRef>> Function() pick,
  Future<List<FormImageRef>> Function(List<Future<Uint8List> Function()>)? read,
  List<FormImagePreset> presets,
});
