// Het redactiemanifest: hoe een derde partij een geredigeerd rapport controleert.
//
// Dit bestand lost een botsing op die anders stil zou blijven. OciDeck legt een
// SHA-512-zegel over de gecanoniseerde markdown (`document_integrity.dart`), en
// het auditdossier reist mee in het pakket "zodat een auditor die alleen het
// pakket heeft, kan zien wat er geleverd is en hoe het te verifiëren". Een
// geredigeerd exportartefact heeft per definitie andere inhoud dan de bron. De
// auditor rekent de hash na, krijgt een mismatch, en concludeert: GEMANIPULEERD.
//
// Een vals tamper-alarm op een echt rapport is erger dan geen integriteits-
// controle hebben: het maakt het mechanisme onbetrouwbaar precies wanneer het
// ertoe doet.
//
// De oplossing: het zegel blijft over de BRON — dat is de identiteit van het
// rapport, niet van één rendering. Elk afgeleid artefact draagt een bewijsbare
// relatie tot dat zegel mee, in plaats van te doen alsof het de bron ís.
//
// ── Waarom er een salt in zit ────────────────────────────────────────────────
//
// Per redactie gaat er een commitment mee: SHA-256(salt ‖ waarde). Dat de salt
// er is, is geen detail maar de kern. Een BSN heeft 10⁹ kandidaten, een
// telefoonnummer minder, een geboortedatum ~40.000. Een kále SHA-256 van een
// geredigeerde waarde is in seconden terug te rekenen — dan publiceer je precies
// wat je zojuist hebt weggelakt. Dit is de klassieke blunder in deze hoek.
//
// De salts staan daarom ALLEEN in het manifest dat bij de volledige versie
// hoort. Het manifest bij de geredigeerde versie draagt de commitments zonder
// salts, en is dus niet terug te rekenen.

import 'dart:convert';

/// Eén redactie, met een bewijsbare verwijzing naar wat er verborgen werd.
class RedactionEntry {
  /// Korte, stabiele referentie (`a3f1`). Zodat een verificateur kan zeggen: "ik
  /// betwist redactie a3f1". Staande praktijk in juridische redactie.
  final String id;

  /// SHA-256(salt ‖ waarde), hex.
  final String commitment;

  /// De salt. **Alleen aanwezig in het manifest bij de volledige versie**; in de
  /// geredigeerde versie is dit leeg (zie [withoutSalts]).
  final String salt;

  /// Welke regel de treffer vond (`nl.bsn`), en waar hij stond.
  final String rule;
  final int slideIndex;
  final String field;

  const RedactionEntry({
    required this.id,
    required this.commitment,
    required this.rule,
    required this.slideIndex,
    required this.field,
    this.salt = '',
  });

  RedactionEntry get withoutSalt => RedactionEntry(
    id: id,
    commitment: commitment,
    rule: rule,
    slideIndex: slideIndex,
    field: field,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'commitment': commitment,
    if (salt.isNotEmpty) 'salt': salt,
    'rule': rule,
    'slide': slideIndex,
    'field': field,
  };

  factory RedactionEntry.fromJson(Map<String, dynamic> json) => RedactionEntry(
    id: '${json['id']}',
    commitment: '${json['commitment']}',
    salt: json['salt'] == null ? '' : '${json['salt']}',
    rule: '${json['rule']}',
    slideIndex: json['slide'] is int ? json['slide'] as int : -1,
    field: '${json['field']}',
  );
}

/// Alle redacties van één export, plus de herkomst.
class RedactionManifest {
  /// De zegelhash van het bron-deck waaruit dit artefact is afgeleid. Leeg
  /// wanneer het deck niet verzegeld is; het manifest blijft dan bruikbaar om de
  /// redacties te controleren, alleen niet om de herkomst vast te pinnen.
  final String derivedFrom;

  final List<RedactionEntry> entries;

  const RedactionManifest({required this.derivedFrom, required this.entries});

  static const empty = RedactionManifest(derivedFrom: '', entries: []);

  bool get isEmpty => entries.isEmpty;

  /// Het manifest zoals het bij de **geredigeerde** versie hoort: commitments,
  /// géén salts. Zonder salt is een commitment niet terug te rekenen, ook niet
  /// voor een waarde uit een kleine ruimte zoals een BSN.
  RedactionManifest get withoutSalts => RedactionManifest(
    derivedFrom: derivedFrom,
    entries: [for (final e in entries) e.withoutSalt],
  );

  bool get carriesSalts => entries.any((e) => e.salt.isNotEmpty);

  Map<String, dynamic> toJson() => {
    'format': 'ocideck-redaction-manifest/1',
    'derived_from': derivedFrom,
    'algorithm': 'sha-256(salt || value)',
    'redactions': [for (final e in entries) e.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory RedactionManifest.fromJson(Map<String, dynamic> json) {
    final raw = json['redactions'];
    return RedactionManifest(
      derivedFrom: '${json['derived_from'] ?? ''}',
      entries: raw is List
          ? [
              for (final e in raw)
                if (e is Map<String, dynamic>) RedactionEntry.fromJson(e),
            ]
          : const [],
    );
  }
}
