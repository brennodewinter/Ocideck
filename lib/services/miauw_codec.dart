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
/// **Waarom versie 2 tijd en grafstenen draagt.** Sinds de dispositie naar een
/// git-repository meereist (#756) kunnen twee reviewers hem onafhankelijk
/// bewerken. De merge is een unie per EIS-id waarin het laatste besluit wint —
/// en intrekken is óók een besluit, dus dat krijgt een grafsteen in plaats van
/// dat de sleutel stil verdwijnt en bij de eerstvolgende samenvoeging van de
/// andere kant herrijst. Besluit en afwegingen: GIT_STORAGE §9.7,
/// FILE_FORMAT §6.5.
///
/// Een bestand met de oude front-matter-sleutels blijft gewoon te openen — zie
/// [legacyFrontMatterMap] — en verhuist bij het eerstvolgende opslaan.
class MiauwCodec {
  /// De formaatversie van de sidecar. Zie [sidecarIsFromNewerBuild] voor wat er
  /// met een hoger nummer gebeurt: niets laden, en niets overschrijven.
  static const int version = 2;

  static const String waiversKey = 'waivers';
  static const String confirmationsKey = 'confirmations';
  static const String revokedKey = 'revoked';
  static const String textKey = 'text';
  static const String atKey = 'at';

  /// De JSON voor [d], of null wanneer er niets te bewaren is — dan hoort er
  /// ook geen sidecar te liggen. Grafstenen tellen als inhoud: een dispositie
  /// met alléén intrekkingen schrijft wél een bestand, want weggooien laat de
  /// waiver bij de eerstvolgende samenvoeging terugkeren van de andere kant.
  ///
  /// [forTextMerge] schrijft ingesprongen (één veld per regel), zodat git's
  /// tekstmerge in een repository iets zinnigs kan — zelfde afspraak als de
  /// notities en de terzijdeleggingen.
  static String? encodeDisposition(
    MiauwDisposition d, {
    bool forTextMerge = false,
  }) {
    if (d.isEmpty) return null;
    Map<String, Object> entryMap(Map<String, MiauwEntry> entries) => {
      for (final e in (entries.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))))
        e.key: {textKey: e.value.text, atKey: e.value.at},
    };
    Map<String, String> sorted(Map<String, String> m) => {
      for (final k in m.keys.toList()..sort()) k: m[k]!,
    };
    final data = {
      kSidecarVersionKey: version,
      if (d.waivers.isNotEmpty) waiversKey: entryMap(d.waivers),
      if (d.confirmations.isNotEmpty)
        confirmationsKey: entryMap(d.confirmations),
      if (d.revokedWaivers.isNotEmpty || d.revokedConfirmations.isNotEmpty)
        revokedKey: {
          if (d.revokedWaivers.isNotEmpty)
            waiversKey: sorted(d.revokedWaivers),
          if (d.revokedConfirmations.isNotEmpty)
            confirmationsKey: sorted(d.revokedConfirmations),
        },
    };
    return forTextMerge
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  /// Leest [json] terug. Een kapotte of te nieuwe sidecar levert een lege
  /// dispositie op: het openen van het deck mag er nooit op stuklopen. Een
  /// versie-1-bestand (platte `{id: tekst}`-kaarten, geen `revoked`) blijft
  /// leesbaar; zijn items dragen geen tijd en gelden bij een merge als ouder
  /// dan elk versie-2-besluit.
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
      final revoked = data[revokedKey];
      return MiauwDisposition(
        waivers: _entryMap(data[waiversKey]),
        confirmations: _entryMap(data[confirmationsKey]),
        revokedWaivers: revoked is Map
            ? _stringMap(revoked[waiversKey])
            : const {},
        revokedConfirmations: revoked is Map
            ? _stringMap(revoked[confirmationsKey])
            : const {},
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

  /// Leest zowel de v2-vorm (`{id: {text, at}}`) als de v1-vorm
  /// (`{id: tekst}`); v1-items krijgen een lege tijd en verliezen daarmee van
  /// elk gedateerd besluit.
  static Map<String, MiauwEntry> _entryMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, MiauwEntry>{};
    for (final e in raw.entries) {
      final value = e.value;
      out['${e.key}'] = value is Map
          ? MiauwEntry(text: '${value[textKey] ?? ''}', at: '${value[atKey] ?? ''}')
          : MiauwEntry(text: '$value');
    }
    return out;
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {for (final e in raw.entries) '${e.key}': '${e.value}'};
  }
}

/// Eén besluit in de dispositie: de verplichte motivering en wanneer hij is
/// genomen ([at], ISO-8601 UTC). Een lege [at] is een besluit uit een
/// versie-1-bestand: tijd onbekend, en dus ouder dan alles wat wél gedateerd
/// is.
class MiauwEntry {
  final String text;
  final String at;

  const MiauwEntry({required this.text, this.at = ''});
}

/// Wat de MIAUW-sidecar draagt. Eén waarde in plaats van losse kaarten, zodat
/// "er is geen dispositie" één ding is om te controleren.
///
/// **Invariant:** een EIS-id leeft in hoogstens één van {kaart, grafstenen} —
/// zetten ruimt de grafsteen op, intrekken de kaartwaarde, en [mergeMiauw]
/// dwingt hem na een unie opnieuw af. De leeskant hoeft daardoor nooit zelf
/// kaart tegen grafsteen te wegen.
class MiauwDisposition {
  final Map<String, MiauwEntry> waivers;
  final Map<String, MiauwEntry> confirmations;

  /// Ingetrokken besluiten: EIS-id → wanneer (ISO-8601 UTC). Grafstenen, met
  /// dezelfde reden als bij de terzijdeleggingen en de ink: een intrekking die
  /// een merge niet overleeft is erger dan een die niet werkt, want de
  /// reviewer geloofde dat hij weg was.
  final Map<String, String> revokedWaivers;
  final Map<String, String> revokedConfirmations;

  const MiauwDisposition({
    this.waivers = const {},
    this.confirmations = const {},
    this.revokedWaivers = const {},
    this.revokedConfirmations = const {},
  });

  bool get isEmpty =>
      waivers.isEmpty &&
      confirmations.isEmpty &&
      revokedWaivers.isEmpty &&
      revokedConfirmations.isEmpty;

  /// De platte tekstweergaven waar de rest van de app op leest (analyzer,
  /// privacyscanner, projectie): EIS-id → motivering.
  Map<String, String> get waiverTexts => {
    for (final e in waivers.entries) e.key: e.value.text,
  };
  Map<String, String> get confirmationTexts => {
    for (final e in confirmations.entries) e.key: e.value.text,
  };

  /// Kaartinhoud uit platte tekstkaarten, zonder tijd — voor het inlezen van
  /// v1-bronnen (oude front matter, oude pakketten). De items gelden als
  /// ongedateerd.
  factory MiauwDisposition.fromTexts(
    Map<String, String> waivers,
    Map<String, String> confirmations,
  ) => MiauwDisposition(
    waivers: {for (final e in waivers.entries) e.key: MiauwEntry(text: e.value)},
    confirmations: {
      for (final e in confirmations.entries) e.key: MiauwEntry(text: e.value),
    },
  );

  /// Zet of verwijdert één besluit; [at] is het moment van dit besluit. Zetten
  /// ruimt een eerdere grafsteen voor dit id op, verwijderen laat er juist een
  /// achter — zie de klasse-invariant.
  MiauwDisposition withEntry({
    required bool isWaiver,
    required String eisId,
    required String? text,
    required String at,
  }) {
    final entries = Map<String, MiauwEntry>.from(
      isWaiver ? waivers : confirmations,
    );
    final revoked = Map<String, String>.from(
      isWaiver ? revokedWaivers : revokedConfirmations,
    );
    if (text == null) {
      if (entries.remove(eisId) != null) revoked[eisId] = at;
    } else {
      entries[eisId] = MiauwEntry(text: text, at: at);
      revoked.remove(eisId);
    }
    return MiauwDisposition(
      waivers: isWaiver ? entries : waivers,
      confirmations: isWaiver ? confirmations : entries,
      revokedWaivers: isWaiver ? revoked : revokedWaivers,
      revokedConfirmations: isWaiver ? revokedConfirmations : revoked,
    );
  }
}

/// De unie van twee kanten van dezelfde dispositie: per EIS-id wint het
/// laatste besluit, en een grafsteen wint een gelijkspel — de strikte lezing
/// (geen waiver zonder staand besluit) is de veilige. Besluit: GIT_STORAGE
/// §9.7. Geen heranker-stap: de identiteit is het EIS-nummer, geen
/// dia-positie.
MiauwDisposition mergeMiauw(MiauwDisposition ours, MiauwDisposition theirs) {
  DateTime tijd(String at) =>
      DateTime.tryParse(at)?.toUtc() ?? DateTime.utc(1970);

  (Map<String, MiauwEntry>, Map<String, String>) verenig(
    Map<String, MiauwEntry> ourEntries,
    Map<String, String> ourRevoked,
    Map<String, MiauwEntry> theirEntries,
    Map<String, String> theirRevoked,
  ) {
    // Eerst per kaart de unie (laatste wint; bij gelijk houden we onze kant,
    // dezelfde asymmetrie als de rest van de merge)...
    final entries = Map<String, MiauwEntry>.from(theirEntries);
    for (final e in ourEntries.entries) {
      final other = entries[e.key];
      if (other == null || !tijd(other.at).isAfter(tijd(e.value.at))) {
        entries[e.key] = e.value;
      }
    }
    final revoked = Map<String, String>.from(theirRevoked);
    for (final e in ourRevoked.entries) {
      final other = revoked[e.key];
      if (other == null || !tijd(other).isAfter(tijd(e.value))) {
        revoked[e.key] = e.value;
      }
    }
    // ...dan de invariant terug: een id leeft in hoogstens één van de twee.
    // De grafsteen wint het gelijkspel.
    for (final id in entries.keys.toList()) {
      final tombstone = revoked[id];
      if (tombstone == null) continue;
      if (tijd(entries[id]!.at).isAfter(tijd(tombstone))) {
        revoked.remove(id);
      } else {
        entries.remove(id);
      }
    }
    return (entries, revoked);
  }

  final (waivers, revokedWaivers) = verenig(
    ours.waivers,
    ours.revokedWaivers,
    theirs.waivers,
    theirs.revokedWaivers,
  );
  final (confirmations, revokedConfirmations) = verenig(
    ours.confirmations,
    ours.revokedConfirmations,
    theirs.confirmations,
    theirs.revokedConfirmations,
  );
  return MiauwDisposition(
    waivers: waivers,
    confirmations: confirmations,
    revokedWaivers: revokedWaivers,
    revokedConfirmations: revokedConfirmations,
  );
}
