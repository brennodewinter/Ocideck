// De gebundelde lexicons: aandoeningsnamen (Orphanet) en overtuigingen (EuroVoc).
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

/// Waar een gevonden bulkterm staat, en onder welke regel hij valt.
typedef BulkTermHit = ({int start, int end, String category});

/// Eén term met de regel waaronder hij meldt.
typedef BulkTerm = ({String term, String category});

/// De gebundelde termen uit beide bronnen, met één index om ze snel te vinden.
class PrivacyBulkLexicon {
  PrivacyBulkLexicon._();

  static final PrivacyBulkLexicon instance = PrivacyBulkLexicon._();

  /// De assets, elk met zijn eigen categorie in de kop.
  ///
  /// Twee bronnen met heel verschillende vorm: Orphanet levert 62.490 namen in
  /// één categorie, EuroVoc 1.536 termen verdeeld over vier. Vandaar dat de
  /// categorie per asset uit de payload komt en niet hier hardgecodeerd staat.
  static const assetKeys = <String>[
    'assets/privacy/health_lexicon.json',
    'assets/privacy/belief_lexicon.json',
  ];

  /// Eerste token (kleine letters) → de volledige termen die ermee beginnen.
  ///
  /// Bewust op het eerste token en niet op het zeldzaamste: "Ziekte van Crohn"
  /// belandt zo in een grote emmer onder `ziekte`, maar die emmer wordt alleen
  /// aangeraakt als het woord "ziekte" werkelijk in de tekst staat — en dan is
  /// een paar honderd vergelijkingen niets.
  Map<String, List<BulkTerm>> _index = const {};

  /// De talen waarvoor er bulktermen geladen zijn. Voedt de dekkingsmeter.
  Set<String> _languages = const {};

  int _termCount = 0;

  bool get isLoaded => _index.isNotEmpty;
  Set<String> get languages => _languages;
  int get termCount => _termCount;

  /// De bronvermeldingen die de licenties eisen — één per geladen asset.
  List<String> attributions = const [];

  /// De versie van de gebundelde uitgave, zoals de bron hem zelf datumt.
  String version = '';

  /// Laadt alle assets en bouwt één index. Idempotent; bij elke fout blijft de
  /// vloer in gebruik en blijven de mislukte assets buiten de index.
  ///
  /// Bewust per asset afgevangen: gaat het gezondheidsbestand stuk, dan hoort
  /// het overtuigingslexicon nog gewoon te laden. Alles-of-niets zou van één
  /// kapot bestand een totale uitval maken.
  Future<void> ensureLoaded({AssetBundle? bundle}) async {
    if (isLoaded) return;
    final index = <String, List<BulkTerm>>{};
    final languages = <String>{};
    final attributions = <String>[];
    var count = 0;

    for (final key in assetKeys) {
      try {
        final raw = await (bundle ?? rootBundle).loadString(key);
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final payload = (map['terms'] as Map).cast<String, dynamic>();
        // Twee vormen: één categorie met talen eronder (Orphanet), of
        // categorieën met elk hun eigen talen (EuroVoc). De kop zegt welke.
        final fallback = map['category'] as String?;
        final blocks = fallback != null
            ? {fallback: payload}
            : payload.map(
                (k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()),
              );

        for (final block in blocks.entries) {
          for (final byLang in (block.value as Map).entries) {
            languages.add(byLang.key as String);
            for (final label in (byLang.value as List).cast<String>()) {
              final term = label.toLowerCase();
              final head = _firstToken(term);
              if (head.isEmpty) continue;
              (index[head] ??= <BulkTerm>[]).add((
                term: term,
                category: block.key,
              ));
              count++;
            }
          }
        }
        final attribution = map['attribution'] as String?;
        if (attribution != null && attribution.isNotEmpty) {
          attributions.add(attribution);
        }
        final v = map['version'] as String?;
        if (v != null && v.isNotEmpty) version = v;
      } catch (e) {
        // Ontbrekend of stuk asset: de vloer blijft staan, en de dekkingsmeter
        // meldt dan gewoon wat de vloer dekt. Stil doorgaan mag hier, zwijgen
        // niet — vandaar de log.
        logError('PrivacyBulkLexicon.ensureLoaded($key)', e);
      }
    }

    // Langste eerst, zodat "ziekte van crohn" wint van een kortere term die
    // toevallig hetzelfde begint. Anders meldt de scanner het deel in plaats
    // van het geheel, en redigeert hij dus te krap.
    for (final bucket in index.values) {
      bucket.sort((a, b) => b.term.length.compareTo(a.term.length));
    }

    _index = index;
    _languages = languages;
    _termCount = count;
    this.attributions = attributions;
  }

  /// Zoekt aandoeningsnamen in [lowerText] (moet al in kleine letters staan).
  ///
  /// Werkt vanuit de tekst en niet vanuit het lexicon: loop de woorden langs,
  /// sla elk woord op in de index, en probeer alleen de kandidaten die daar
  /// hangen. Zie de kop voor waarom dat de enige haalbare volgorde is.
  Iterable<BulkTermHit> findIn(String lowerText) sync* {
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
        for (final candidate in bucket) {
          final stop = i + candidate.term.length;
          if (stop > n) continue;
          if (!lowerText.startsWith(candidate.term, i)) continue;
          // Hele woorden: een naam mag niet halverwege een langer woord eindigen.
          if (stop < n && _isWordChar(lowerText.codeUnitAt(stop))) continue;
          yield (start: i, end: stop, category: candidate.category);
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
    attributions = const [];
    version = '';
  }

  /// Alleen voor tests: een index vullen zonder asset.
  @visibleForTesting
  void loadForTest(
    Map<String, List<String>> terms, {
    String category = 'special.health',
  }) {
    final index = <String, List<BulkTerm>>{};
    var count = 0;
    for (final entry in terms.entries) {
      for (final raw in entry.value) {
        final term = raw.toLowerCase();
        final head = _firstToken(term);
        if (head.isEmpty) continue;
        (index[head] ??= <BulkTerm>[]).add((term: term, category: category));
        count++;
      }
    }
    for (final bucket in index.values) {
      bucket.sort((a, b) => b.term.length.compareTo(a.term.length));
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
