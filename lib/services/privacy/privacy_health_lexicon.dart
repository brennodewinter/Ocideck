// Het gebundelde gezondheidslexicon: 62.490 aandoeningsnamen uit Orphanet.
//
// Dezelfde vorm als `CweCatalog`, en om dezelfde reden: een **vloer** die altijd
// werkt plus een **bulkasset** die daaroverheen komt. De vloer
// (`privacy_lexicon_data.dart`) is in Dart gecompileerd en dus synchroon
// beschikbaar; deze bulk komt uit een asset en laadt één keer. Ontbreekt of
// breekt het asset, dan blijft de vloer gewoon draaien — de scanner valt nooit
// om op een bestand dat er niet is.
//
// ── Waarom niet gewoon 62.490 entries in de vloer ───────────────────────────
//
// Twee harde grenzen. De conventiecheck kapt `lib/`-bestanden af op duizend
// regels, en de scanner loopt zijn lexicon lineair langs met `indexOf`. Dat
// tweede is het echte probleem: bij tweehonderd termen is dat gratis, bij
// tweeënzestigduizend haalt het het prestatiebudget van 5 ms per slide nooit.
//
// Vandaar de **starttoken-index**. Een aandoeningsnaam begint bijna altijd met
// een woord dat je kunt opzoeken, dus in plaats van elke term langs de tekst te
// halen, halen we elk woord uit de tekst langs een hashmap. Dat maakt het werk
// evenredig met de lengte van de slide in plaats van met de omvang van het
// lexicon — precies andersom, en dat is het verschil tussen onbruikbaar en
// gratis.
//
// ── Waarom `possible` en niet `certain` ─────────────────────────────────────
//
// Deze namen zijn onmiskenbaar: de vals-positievenmeting vond op de volledige
// repodocumentatie één treffer op 59.564 kandidaten. Toch blijft de melding
// informatief, want onmiskenbaar-een-ziektenaam is iets anders dan
// onmiskenbaar-een-persoonsgegeven. Een slide "onze afdeling behandelt cystinose
// en fucosidose" is een dienstbeschrijving, geen dossier. Pas met iemand erbij
// is het een gezondheidsgegeven van een persoon, en dan tilt de
// persoonskoppelingspoort (§13.2) hem vanzelf omhoog — inclusief het verbreden
// van het bereik tot de hele mededeling.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../utils/log.dart';

/// Waar een gevonden bulkterm staat.
typedef HealthTermHit = ({int start, int end});

/// De aandoeningsnamen uit Orphanet, met een index om ze snel te vinden.
class PrivacyHealthLexicon {
  PrivacyHealthLexicon._();

  static final PrivacyHealthLexicon instance = PrivacyHealthLexicon._();

  static const assetKey = 'assets/privacy/health_lexicon.json';

  /// Eerste token (kleine letters) → de volledige termen die ermee beginnen.
  ///
  /// Bewust op het eerste token en niet op het zeldzaamste: "Ziekte van Crohn"
  /// belandt zo in een grote emmer onder `ziekte`, maar die emmer wordt alleen
  /// aangeraakt als het woord "ziekte" werkelijk in de tekst staat — en dan is
  /// een paar honderd vergelijkingen niets.
  Map<String, List<String>> _index = const {};

  /// De talen waarvoor er bulktermen geladen zijn. Voedt de dekkingsmeter.
  Set<String> _languages = const {};

  int _termCount = 0;

  bool get isLoaded => _index.isNotEmpty;
  Set<String> get languages => _languages;
  int get termCount => _termCount;

  /// De bronvermelding die de licentie eist (CC BY 4.0).
  String attribution = '';

  /// De versie van de gebundelde uitgave, zoals de bron hem zelf datumt.
  String version = '';

  /// Laadt het asset en bouwt de index. Idempotent; bij elke fout blijft de
  /// vloer in gebruik en blijft [isLoaded] onwaar.
  Future<void> ensureLoaded({AssetBundle? bundle}) async {
    if (isLoaded) return;
    try {
      final raw = await (bundle ?? rootBundle).loadString(assetKey);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final terms = (map['terms'] as Map).cast<String, dynamic>();

      final index = <String, List<String>>{};
      var count = 0;
      for (final entry in terms.entries) {
        for (final raw in (entry.value as List).cast<String>()) {
          final term = raw.toLowerCase();
          final head = _firstToken(term);
          if (head.isEmpty) continue;
          (index[head] ??= <String>[]).add(term);
          count++;
        }
      }
      // Langste eerst, zodat "ziekte van crohn" wint van een kortere term die
      // toevallig hetzelfde begint. Anders meldt de scanner het deel in plaats
      // van het geheel, en redigeert hij dus te krap.
      for (final bucket in index.values) {
        bucket.sort((a, b) => b.length.compareTo(a.length));
      }

      _index = index;
      _languages = terms.keys.toSet();
      _termCount = count;
      attribution = (map['attribution'] as String?) ?? '';
      version = (map['version'] as String?) ?? '';
    } catch (e) {
      // Ontbrekend of stuk asset: de vloer blijft staan, en de dekkingsmeter
      // meldt dan gewoon wat de vloer dekt. Stil doorgaan mag hier, zwijgen
      // niet — vandaar de log.
      logError('PrivacyHealthLexicon.ensureLoaded', e);
    }
  }

  /// Zoekt aandoeningsnamen in [lowerText] (moet al in kleine letters staan).
  ///
  /// Werkt vanuit de tekst en niet vanuit het lexicon: loop de woorden langs,
  /// sla elk woord op in de index, en probeer alleen de kandidaten die daar
  /// hangen. Zie de kop voor waarom dat de enige haalbare volgorde is.
  Iterable<HealthTermHit> findIn(String lowerText) sync* {
    if (_index.isEmpty || lowerText.isEmpty) return;
    var i = 0;
    final n = lowerText.length;
    while (i < n) {
      if (!_isWordChar(lowerText.codeUnitAt(i))) {
        i++;
        continue;
      }
      // Begin van een woord: lees het uit en zoek het op.
      var end = i;
      while (end < n && _isWordChar(lowerText.codeUnitAt(end))) {
        end++;
      }
      final bucket = _index[lowerText.substring(i, end)];
      if (bucket != null) {
        for (final term in bucket) {
          final stop = i + term.length;
          if (stop > n) continue;
          if (!lowerText.startsWith(term, i)) continue;
          // Hele woorden: een naam mag niet halverwege een langer woord eindigen.
          if (stop < n && _isWordChar(lowerText.codeUnitAt(stop))) continue;
          yield (start: i, end: stop);
          // Eén treffer per positie; de bucket staat op lengte gesorteerd, dus
          // dit is meteen de langste.
          break;
        }
      }
      i = end;
    }
  }

  /// Alleen voor tests: de index leegmaken zodat de volgende [ensureLoaded]
  /// opnieuw parseert.
  @visibleForTesting
  void resetForTest() {
    _index = const {};
    _languages = const {};
    _termCount = 0;
    attribution = '';
    version = '';
  }

  /// Alleen voor tests: een index vullen zonder asset.
  @visibleForTesting
  void loadForTest(Map<String, List<String>> terms) {
    final index = <String, List<String>>{};
    var count = 0;
    for (final entry in terms.entries) {
      for (final raw in entry.value) {
        final term = raw.toLowerCase();
        final head = _firstToken(term);
        if (head.isEmpty) continue;
        (index[head] ??= <String>[]).add(term);
        count++;
      }
    }
    for (final bucket in index.values) {
      bucket.sort((a, b) => b.length.compareTo(a.length));
    }
    _index = index;
    _languages = terms.keys.toSet();
    _termCount = count;
  }
}

/// Het eerste woord van een term, in kleine letters.
String _firstToken(String term) {
  var i = 0;
  while (i < term.length && !_isWordChar(term.codeUnitAt(i))) {
    i++;
  }
  var end = i;
  while (end < term.length && _isWordChar(term.codeUnitAt(end))) {
    end++;
  }
  return term.substring(i, end);
}

/// Of dit teken bij een woord hoort. Gelijk aan de matcher in
/// `privacy_special_rules.dart`: Latijnse accenttekens tellen mee, zodat
/// `patiënt` één woord is.
bool _isWordChar(int c) =>
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0xC0 && c <= 0x24F);
