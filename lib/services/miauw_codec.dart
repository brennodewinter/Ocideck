import 'dart:convert';

import '../utils/log.dart';
import 'sidecar_format.dart';

/// De MIAUW-dispositie van een deck als sidecar naast de `.md`.
///
/// Twee kaarten, allebei op EIS-nummer: [MiauwDisposition.waivers] zijn eisen
/// die de klant heeft uitgesloten (met reden), [MiauwDisposition.confirmations]
/// zijn eisen die de klant zelf heeft bevestigd. Zie
/// `miauw_compliance_analyzer.dart` voor wat ze betekenen.
///
/// **Waarom ernaast en niet erin.** Tot 0.1.0 stonden ze als base64-JSON in de
/// front matter van de `.md`. Dat is twee keer verkeerd: het is ondoorzichtig
/// in een bestand dat met een teksteditor te lezen hoort te zijn, en het gaat
/// *over* het document (wie wat heeft afgesproken) in plaats van dat het het
/// document ís. Precies de scheiding die `.ink.json` en `.user-notes.json` al
/// maakten.
///
/// Een bestand met de oude sleutels blijft gewoon te openen — zie
/// [legacyFrontMatterMap] — en verhuist bij het eerstvolgende opslaan.
class MiauwCodec {
  /// De formaatversie van de sidecar. Zie [sidecarIsFromNewerBuild] voor wat er
  /// met een hoger nummer gebeurt: niets laden, en niets overschrijven.
  static const int version = 1;

  static const String waiversKey = 'waivers';
  static const String confirmationsKey = 'confirmations';

  /// De JSON voor deze dispositie, of null wanneer er niets te bewaren is —
  /// dan hoort er ook geen sidecar te liggen.
  static String? encode(
    Map<String, String> waivers,
    Map<String, String> confirmations,
  ) {
    if (waivers.isEmpty && confirmations.isEmpty) return null;
    return jsonEncode({
      kSidecarVersionKey: version,
      if (waivers.isNotEmpty) waiversKey: waivers,
      if (confirmations.isNotEmpty) confirmationsKey: confirmations,
    });
  }

  /// Leest [json] terug. Een kapotte of te nieuwe sidecar levert een lege
  /// dispositie op: het openen van het deck mag er nooit op stuklopen.
  static MiauwDisposition decode(String json) {
    try {
      final data = jsonDecode(json);
      final fileVersion = declaredSidecarVersion(data);
      if (fileVersion > version) {
        logWarning(
          'MiauwCodec.decode: MIAUW sidecar is version $fileVersion, this '
          'build reads $version — not loading it',
        );
        return const MiauwDisposition();
      }
      if (data is! Map) return const MiauwDisposition();
      return MiauwDisposition(
        waivers: _stringMap(data[waiversKey]),
        confirmations: _stringMap(data[confirmationsKey]),
      );
    } catch (e, s) {
      logError('MiauwCodec.decode: decode MIAUW sidecar JSON', e, s);
      return const MiauwDisposition();
    }
  }

  /// De oude, base64-JSON-vorm uit de front matter van een `.md` van vóór
  /// 0.1.0 (`ocideck_miauw_waivers` / `ocideck_miauw_confirmations`).
  ///
  /// Alleen om te lezen: OciDeck schrijft deze sleutels niet meer en haalt ze
  /// bij het opslaan uit het bestand weg (zie [kRetiredFrontMatterKeys] in
  /// `front_matter_merge.dart`). Een onleesbare waarde levert een lege kaart
  /// op — een verhaspelde afspraak mag het hele deck niet onopenbaar maken.
  static Map<String, String> legacyFrontMatterMap(String value, String key) {
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(value.trim())));
      return _stringMap(decoded);
    } catch (e, s) {
      logError('MiauwCodec.legacyFrontMatterMap: decode $key', e, s);
      return const {};
    }
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {for (final e in raw.entries) '${e.key}': '${e.value}'};
  }
}

/// Wat de MIAUW-sidecar draagt. Eén waarde in plaats van twee losse kaarten,
/// zodat "er is geen dispositie" één ding is om te controleren.
class MiauwDisposition {
  final Map<String, String> waivers;
  final Map<String, String> confirmations;

  const MiauwDisposition({
    this.waivers = const {},
    this.confirmations = const {},
  });

  bool get isEmpty => waivers.isEmpty && confirmations.isEmpty;
}
