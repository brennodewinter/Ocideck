/// De terzijdegelegde privacybevindingen van een deck, als sidecar naast de
/// `.md` (`<naam>.dismissals.json`). Ontworpen in FILE_FORMAT §6.7 (#651).
///
/// Vóór dit bestand bood een bevinding één handeling: *meld deze regel nooit
/// meer*. Dat is een globale schakelaar voor een plaatselijk oordeel. Wie één
/// treffer heeft bekeken en goed bevonden — de naam van een collega die op de
/// dia hóórt, een adres dat van de klant zelf is — moest kiezen tussen de
/// waarschuwing voor altijd houden of de regel uitzetten voor élk deck. Dat
/// laatste faalt bovendien de verkeerde kant op: de eerstvolgende échte treffer
/// van die soort komt er dan nooit meer.
///
/// **Per deck.** Een terzijdelegging is een oordeel over dít document, dus
/// hoort ze bij het document en niet bij de gebruiker. Verhuist het deck naar
/// een tweede reviewer, dan reist het oordeel mee.
///
/// **Verbergen is geen wegscannen.** De ongefilterde scan blijft het volle
/// aantal zien; alleen het paneel filtert. Zie [DeckDismissals.hides].
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../utils/log.dart';
import '../sidecar_format.dart';

/// Eén terzijdelegging: welke regel, en over welke waarde.
class PrivacyDismissal {
  /// De regel die vuurde, bijvoorbeeld `nl.bsn` — dezelfde stabiele id die
  /// `PrivacyFinding.ruleId` draagt.
  final String ruleId;

  /// `SHA-256(salt ‖ waarde)`, hex. Zie [commitmentFor] voor waarom hier een
  /// commitment staat en niet de waarde zelf.
  final String commitment;

  /// Wanneer dit oordeel geveld is. UTC, ISO 8601. Voert het samenvoegen: bij
  /// dezelfde sleutel wint de latere.
  final DateTime at;

  /// Waar de bevinding stond toen erover geoordeeld werd. **Uitsluitend om te
  /// tonen** in de ongedaan-lijst; nadrukkelijk geen onderdeel van de
  /// identiteit — elke positie schuift zodra iemand er een woord boven typt.
  final int? seenAtSlide;
  final String? seenAtField;
  final int? seenAtFragment;

  const PrivacyDismissal({
    required this.ruleId,
    required this.commitment,
    required this.at,
    this.seenAtSlide,
    this.seenAtField,
    this.seenAtFragment,
  });

  /// De sleutel waarop terzijdeleggingen en herroepingen elkaar vinden.
  ///
  /// De regel-id draagt geen spaties (`nl.bsn`) en het commitment is
  /// hex, dus een spatie scheidt de twee zonder dat er twee paren
  /// bestaan die dezelfde sleutel opleveren.
  String get key => '$ruleId $commitment';
}

/// Wat de sidecar draagt. Eén waarde, zodat "er is niets terzijdegelegd" één
/// ding is om te controleren.
class DeckDismissals {
  /// Het zout van dít deck, hex. Per deck, zodat dezelfde naam in twee decks
  /// twee onvergelijkbare commitments oplevert en niemand een stapel sidecars
  /// naast elkaar kan leggen om te zien welke decks over dezelfde persoon gaan.
  ///
  /// **Geen geheim.** Het staat in ditzelfde bestand, dus wie de sidecar heeft
  /// kan een gok toetsen. Tegen iemand die het deck heeft kost dat niets — die
  /// leest de dia gewoon. Dat staat hier zodat niemand een bescherming
  /// veronderstelt die er niet is.
  final String salt;

  final List<PrivacyDismissal> dismissals;

  /// Grafstenen: ongedaan gemaakte terzijdeleggingen.
  ///
  /// Ze staan er niet voor de sier. Zonder grafsteen zou een ongedaan-making
  /// bij de eerstvolgende samenvoeging verdwijnen — de andere kant draagt de
  /// terzijdelegging immers nog — en bleef de bevinding verborgen. Dat is de
  /// stille faalrichting, en juist die willen we hier niet.
  final List<PrivacyDismissal> revocations;

  const DeckDismissals({
    required this.salt,
    this.dismissals = const [],
    this.revocations = const [],
  });

  bool get isEmpty => dismissals.isEmpty && revocations.isEmpty;

  /// Of de bevinding met [ruleId] over [text] verborgen hoort te worden.
  ///
  /// Een herroeping die later is dan de terzijdelegging wint. Gelijke
  /// tijdstempels laten de bevinding zien: bij twijfel liever een melding te
  /// veel dan een verborgen persoonsgegeven.
  bool hides(String ruleId, String text) {
    final k = '$ruleId ${commitmentFor(salt, text)}';
    final set = _latest(dismissals, k);
    if (set == null) return false;
    final rev = _latest(revocations, k);
    return rev == null || set.at.isAfter(rev.at);
  }

  static PrivacyDismissal? _latest(List<PrivacyDismissal> list, String key) {
    PrivacyDismissal? best;
    for (final d in list) {
      if (d.key != key) continue;
      if (best == null || d.at.isAfter(best.at)) best = d;
    }
    return best;
  }
}

/// Het commitment over [text] onder [salt].
///
/// **Waarom geen ruwe waarde**, terwijl die gewoon in de `.md` staat en wie de
/// sidecar heeft het deck ook heeft. Het commitment koopt tegen die lezer
/// niets, en dit bestand doet ook niet alsof. Twee andere redenen dragen het:
///
///  1. Een privacygereedschap hoort geen tweede kopie van een persoonsgegeven
///     te maken. De `.md` beheert de auteur — die maakt er een back-up van en
///     ruimt hem ooit op. Deze sidecar is machinerie, met een eigen levensduur:
///     mee de git-historie in, mee de synchronisatiemap in, mee het pakket in.
///     `Jan Jansen` hierin schrijven laat die naam staan **nadat de auteur hem
///     van de dia heeft gehaald**. Een waarde die haar eigen verwijdering
///     overleeft is precies wat dit product wil voorkomen.
///  2. Het zout is per deck, dus dezelfde naam in twee decks geeft twee
///     onvergelijkbare uitkomsten.
String commitmentFor(String salt, String text) =>
    sha256.convert(utf8.encode('$salt$text')).toString();

/// Een vers zout voor een deck dat er nog geen heeft.
///
/// Zestien bytes uit [Random.secure], hex. Niet omdat het zout geheim moet
/// zijn — dat is het niet, het staat in dezelfde sidecar — maar omdat het
/// onvoorspelbaar en uniek moet zijn: dat is wat correlatie tussen decks
/// tegenhoudt. Een teller of een tijdstempel zou dat niet doen.
String newDismissalSalt() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Leest en schrijft `<naam>.dismissals.json`.
class DismissalCodec {
  /// De formaatversie. Zie [sidecarIsFromNewerBuild]: een hoger nummer wordt
  /// niet geladen én niet overschreven.
  static const int version = 1;

  static const String saltKey = 'salt';
  static const String dismissalsKey = 'dismissals';
  static const String revocationsKey = 'revocations';

  /// De JSON, of null wanneer er niets te bewaren valt — dan hoort er ook geen
  /// sidecar te liggen. Grafstenen tellen als inhoud: "alles herroepen" levert
  /// dus géén null op, want de herroeping zelf moet de volgende samenvoeging
  /// overleven.
  ///
  /// Met [forTextMerge] ingesprongen geschreven — dezelfde ruil als bij de
  /// notities en de ink: alleen de kopie die een repository in gaat betaalt
  /// ervoor, en dáár verdient hij zich terug. De echte merge is
  /// [mergeDismissals] in de app; in een kloon van een ander werktuig valt git
  /// terug op de tekst-merge, en op één regel botst daar élk oordeel met élk
  /// ander.
  static String? encode(DeckDismissals value, {bool forTextMerge = false}) {
    if (value.isEmpty) return null;
    final payload = {
      kSidecarVersionKey: version,
      saltKey: value.salt,
      if (value.dismissals.isNotEmpty)
        dismissalsKey: value.dismissals.map(_entry).toList(),
      if (value.revocations.isNotEmpty)
        revocationsKey: value.revocations.map(_entry).toList(),
    };
    return forTextMerge
        ? '${const JsonEncoder.withIndent('  ').convert(payload)}\n'
        : jsonEncode(payload);
  }

  static Map<String, Object?> _entry(PrivacyDismissal d) => {
    'rule': d.ruleId,
    'commitment': d.commitment,
    'at': d.at.toUtc().toIso8601String(),
    if (d.seenAtSlide != null)
      'seen_at': {
        'slide': d.seenAtSlide,
        if (d.seenAtField != null) 'field': d.seenAtField,
        if (d.seenAtFragment != null) 'fragment': d.seenAtFragment,
      },
  };

  /// Leest [json] terug onder [fallbackSalt] — het zout dat gebruikt wordt
  /// wanneer het bestand er geen draagt, zodat de aanroeper altijd een bruikbare
  /// waarde terugkrijgt.
  ///
  /// Een kapotte of te nieuwe sidecar levert "niets terzijdegelegd" op. Dat is
  /// de veilige kant: het deck opent gewoon, en de bevindingen zijn zichtbaar
  /// in plaats van stilletjes onderdrukt door een bestand dat we niet begrijpen.
  static DeckDismissals decode(String json, {required String fallbackSalt}) {
    try {
      final data = jsonDecode(json);
      final fileVersion = declaredSidecarVersion(data);
      if (fileVersion > version) {
        logWarning(
          'DismissalCodec.decode: sidecar is version $fileVersion, this build '
          'reads $version — not loading it',
        );
        return DeckDismissals(salt: fallbackSalt);
      }
      if (data is! Map) return DeckDismissals(salt: fallbackSalt);
      final salt = data[saltKey];
      return DeckDismissals(
        salt: salt is String && salt.isNotEmpty ? salt : fallbackSalt,
        dismissals: _entries(data[dismissalsKey]),
        revocations: _entries(data[revocationsKey]),
      );
    } catch (e, s) {
      logError('DismissalCodec.decode: decode dismissals sidecar JSON', e, s);
      return DeckDismissals(salt: fallbackSalt);
    }
  }

  /// Overslaan wat niet compleet is, in plaats van de hele lijst weggooien:
  /// één verhaspelde regel mag de andere oordelen niet meenemen.
  static List<PrivacyDismissal> _entries(Object? raw) {
    if (raw is! List) return const [];
    final out = <PrivacyDismissal>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final rule = item['rule'];
      final commitment = item['commitment'];
      final at = DateTime.tryParse('${item['at']}');
      if (rule is! String || commitment is! String || at == null) continue;
      final seen = item['seen_at'];
      out.add(
        PrivacyDismissal(
          ruleId: rule,
          commitment: commitment,
          at: at.toUtc(),
          seenAtSlide: seen is Map && seen['slide'] is int
              ? seen['slide'] as int
              : null,
          seenAtField: seen is Map && seen['field'] is String
              ? seen['field'] as String
              : null,
          seenAtFragment: seen is Map && seen['fragment'] is int
              ? seen['fragment'] as int
              : null,
        ),
      );
    }
    return out;
  }
}

/// Voegt twee kanten van hetzelfde deck samen: een unie op regel + commitment,
/// waarbij bij dezelfde sleutel de latere `at` wint.
///
/// Eén regel voor elk geval. Twee reviewers die verschillende bevindingen
/// terzijdeleggen houden allebei hun oordeel; legt de een terzijde wat de ander
/// herroept, dan beslist de klok, en opnieuw herroepen kan altijd.
///
/// Het zout van [ours] wint. Het is per deck, en twee kanten van hetzelfde deck
/// horen er hetzelfde te dragen; wijkt het af, dan is de andere kant een ánder
/// deck en zijn zijn commitments hier toch betekenisloos.
DeckDismissals mergeDismissals(DeckDismissals ours, DeckDismissals theirs) {
  if (theirs.salt != ours.salt) return ours;
  List<PrivacyDismissal> union(
    List<PrivacyDismissal> a,
    List<PrivacyDismissal> b,
  ) {
    final byKey = <String, PrivacyDismissal>{};
    for (final d in [...a, ...b]) {
      final seen = byKey[d.key];
      if (seen == null || d.at.isAfter(seen.at)) byKey[d.key] = d;
    }
    final out = byKey.values.toList()..sort((x, y) => x.key.compareTo(y.key));
    return out;
  }

  return DeckDismissals(
    salt: ours.salt,
    dismissals: union(ours.dismissals, theirs.dismissals),
    revocations: union(ours.revocations, theirs.revocations),
  );
}
