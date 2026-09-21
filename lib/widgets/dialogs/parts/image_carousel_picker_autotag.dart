// Part of the image_carousel_picker library — see ../image_carousel_picker.dart.
// Split out for navigability (AI auto-tag run); all imports live in the main library
// file. Instance methods relocate verbatim into an extension on
// _ImageCarouselPickerState — same library, same members, no behaviour change.
part of '../image_carousel_picker.dart';

/// Waarom een afbeelding in de auto-tagronde is overgeslagen. De eerste twee
/// redenen betekenen dat er níets de deur uit is gegaan; bij [emptyResponse]
/// ging het beeld wél naar het model maar kwam er niets bruikbaars terug. Dat
/// verschil is voor de gebruiker het onderscheid tussen een formaatprobleem en
/// een instellingen- of modelprobleem (#2148).
enum AutoTagSkip {
  /// De bytes waren lokaal niet leesbaar (weg, onleesbaar, buiten de grens).
  unreadable,

  /// Niet decodeerbaar of boven de decodegrens. HEIC telt in de bibliotheek
  /// als afbeelding maar heeft geen decoder in het `image`-pakket — die
  /// categorie belandde hiervoor stilzwijgend in deze tak.
  notDecodable,

  /// Het beeld ging uit, het model gaf niets bruikbaars terug (o.a. een
  /// tekst-only model of een weigering die de opschoning niet overleeft).
  emptyResponse,

  /// De aanroep gooide (netwerk, weigering, tijdslimiet — al gelogd).
  failed,
}

/// Uitkomst van [runAutoTag]: welke paden getagd zijn (voor ongedaan maken)
/// en per reden hoeveel er zijn overgeslagen.
class AutoTagRunResult {
  final tagged = <String>[];
  final skipped = <AutoTagSkip, int>{};

  int get skippedTotal => skipped.values.fold(0, (sum, n) => sum + n);

  void _skip(AutoTagSkip reason) =>
      skipped[reason] = (skipped[reason] ?? 0) + 1;
}

/// De tagronde zelf: lees elke afbeelding, vraag tags, sla ze op en tel de
/// overgeslagenen per reden. Los van de widget, zodat het bewijs in een gewone
/// test kan: de melding erna zegt niet alleen hoeveel het lukte maar ook wat er
/// overbleef en waarom (#2148). Logt per overslág de reden — zónder het pad,
/// want een bestandsnaam kan een persoonsnaam dragen.
Future<AutoTagRunResult> runAutoTag(
  List<String> paths, {
  required Future<Uint8List?> Function(String path) readBytes,
  required Future<TagSuggestion> Function(Uint8List bytes) tag,
  required Future<void> Function(String path, String tags) save,
  void Function(int current, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final result = AutoTagRunResult();
  for (var i = 0; i < paths.length; i++) {
    if (isCancelled?.call() ?? false) break;
    onProgress?.call(i + 1, paths.length);
    final path = paths[i];
    try {
      final bytes = await readBytes(path);
      if (bytes == null) {
        result._skip(AutoTagSkip.unreadable);
        logWarning(
          'ImageCarouselPicker.autoTag: afbeelding ${i + 1}/${paths.length} '
          'overgeslagen — niet leesbaar',
        );
        continue;
      }
      final suggestion = await tag(bytes);
      if (suggestion.tags.isEmpty) {
        final reason = suggestion.imageSent
            ? AutoTagSkip.emptyResponse
            : AutoTagSkip.notDecodable;
        result._skip(reason);
        logWarning(
          'ImageCarouselPicker.autoTag: afbeelding ${i + 1}/${paths.length} '
          'overgeslagen — '
          '${suggestion.imageSent ? 'het model gaf niets bruikbaars terug' : 'niet decodeerbaar (bv. HEIC of boven de decodegrens)'}',
        );
        continue;
      }
      await save(path, suggestion.tags);
      result.tagged.add(path);
    } catch (e, s) {
      result._skip(AutoTagSkip.failed);
      logError('ImageCarouselPicker.autoTag', e, s);
    }
  }
  return result;
}

/// De meldtekst na de tagronde: aantal getagd, plus aantal overgeslagen met de
/// redenen erbij. [d] is de vertaalfunctie, losgehaald zodat de tekst in een
/// test met de identiteitsvertaler toetsbaar is.
String autoTagSummary(
  String Function(String dutch) d,
  AutoTagRunResult result,
) {
  final text = '${result.tagged.length} ${d('afbeeldingen getagd door AI.')}';
  if (result.skippedTotal == 0) return text;
  String label(AutoTagSkip reason) => switch (reason) {
    AutoTagSkip.unreadable => d('niet leesbaar'),
    AutoTagSkip.notDecodable => d('niet decodeerbaar'),
    AutoTagSkip.emptyResponse => d('model gaf niets bruikbaars terug'),
    AutoTagSkip.failed => d('mislukt'),
  };
  final reasons = [
    for (final reason in AutoTagSkip.values)
      if ((result.skipped[reason] ?? 0) > 0)
        '${result.skipped[reason]} ${label(reason)}',
  ];
  return '$text ${result.skippedTotal} ${d('overgeslagen')} '
      '(${reasons.join(', ')})';
}
