import 'package:flutter/foundation.dart';

import '../../utils/text_search.dart';
import 'markdown_source_controller.dart';

/// De zoek-/vervangstand van een broneditor: de vraag, de gevonden plekken, en
/// wat er gebeurt bij volgende, vorige, vervangen en alles-vervangen.
///
/// **Waarom een eigen klasse en niet in het scherm.** Deze stand stond twee keer
/// in de boom — één keer in de documenteditor en één keer in de
/// presentatie-broneditor — met dezelfde zeven velden en dezelfde acht methoden,
/// tot op de klemregels na gelijk. Twee kopieën van dezelfde logica lopen uit
/// elkaar zodra iemand er één repareert, en ze telden bovendien allebei mee in
/// het regel- en klasseplafond van een scherm dat al aan zijn grens zat.
///
/// De sessie kent de editor alleen via [controller]: daar leest ze de tekst,
/// schrijft ze een vervanging, en zet ze de zoekmarkering. Waar de cursor
/// naartoe moet is bewust *niet* van haar — dat verschilt per gastheer (de
/// documenteditor heeft een visuele stand waarin de cursor in Quill leeft) en
/// gaat via [onReveal]. Elke wijziging van de stand meldt zich via [onChanged],
/// zodat de gastheer zijn `setState` houdt en de sessie zelf geen widget hoeft
/// te zijn.
class FindReplaceSession {
  FindReplaceSession({
    required this.controller,
    required this.onChanged,
    required this.onReveal,
  });

  /// De broneditor waarop gezocht wordt. De sessie leest `text`, schrijft hem
  /// bij een vervanging, en zet de markering met `showSearchMatches`.
  final MarkdownSourceController controller;

  /// De gastheer vragen zichzelf opnieuw op te bouwen. Wordt aangeroepen ná de
  /// mutatie, zodat de opbouw de nieuwe stand ziet.
  final VoidCallback onChanged;

  /// De gevonden plek in beeld brengen. De gastheer bepaalt hoe: selectie op de
  /// controller in de bronstand, of een signaal naar de rijke-tekstlaag.
  final void Function(TextMatchRange match) onReveal;

  bool _visible = false;
  bool _showReplace = false;
  String _query = '';
  String _replacement = '';
  bool _caseSensitive = false;
  int _matchIndex = -1;
  List<TextMatchRange> _matches = const [];

  /// Of de zoekbalk getoond wordt.
  bool get visible => _visible;

  /// Of de balk ook het vervangveld toont.
  bool get showReplace => _showReplace;

  /// De huidige zoekvraag.
  String get query => _query;

  /// De tekst die bij vervangen in de plaats komt.
  String get replacement => _replacement;

  /// Of hoofdletters meetellen bij het zoeken.
  bool get caseSensitive => _caseSensitive;

  /// Het aantal gevonden plekken.
  int get matchCount => _matches.length;

  /// De gevonden plek waar de cursor nu op staat, of -1 als er geen is.
  int get matchIndex => _matchIndex;

  /// Open de balk. [showReplace] bepaalt of het vervangveld meekomt; de eerste
  /// treffer wordt meteen aangewezen, zodat je niet nog een keer hoeft te
  /// drukken om te zien wat er gevonden is.
  void open({required bool showReplace}) {
    _visible = true;
    _showReplace = showReplace;
    recount(selectFirst: true);
  }

  /// Sluit de balk en haal de markering weg. De vraag zelf blijft staan: wie
  /// hem per ongeluk sluit, vindt hem bij heropenen terug.
  void close() {
    _visible = false;
    _matchIndex = -1;
    _matches = const [];
    onChanged();
    syncHighlights();
  }

  /// Vergeet de gevonden plekken zonder de balk te sluiten.
  ///
  /// Voor de gastheer die zijn tekst van buitenaf vervangt: de oude posities
  /// slaan dan nergens meer op. Opnieuw tellen doet dit bewust níet — dat zou de
  /// weergave naar een treffer trekken in tekst die de lezer nog moet zien.
  void clearMatches() {
    _matches = const [];
    _matchIndex = -1;
    onChanged();
    syncHighlights();
  }

  /// Een nieuwe zoekvraag: opnieuw tellen en meteen naar de eerste treffer.
  void setQuery(String value) {
    _query = value;
    recount(selectFirst: true);
  }

  /// De zoekvraag zoals die in het zoekveld wordt getypt: telt de treffers
  /// bij, maar springt niet naar de eerste treffer — anders trekt elke
  /// toetsaanslag de focus naar het document en kan de gebruiker zijn
  /// zoekterm niet invullen (#1760).
  void onQueryFieldChanged(String value) {
    _query = value;
    _matches = findAllMatches(
      controller.text,
      _query,
      caseSensitive: _caseSensitive,
    );
    _matchIndex = _matches.isEmpty ? -1 : 0;
    onChanged();
    syncHighlights();
  }

  /// De vervangtekst. Verandert niets aan de treffers, dus alleen opnieuw
  /// opbouwen.
  void setReplacement(String value) {
    _replacement = value;
    onChanged();
  }

  /// Hoofdlettergevoeligheid aan of uit: opnieuw tellen, maar blijf staan waar
  /// je stond in plaats van terug naar de eerste treffer te springen.
  void setCaseSensitive(bool value) {
    _caseSensitive = value;
    recount(selectFirst: false);
  }

  /// Zet de zoekmarkering op de editor. Is de balk dicht, dan staat er niets
  /// gemarkeerd — de treffers blijven wel bewaard voor het heropenen.
  void syncHighlights() {
    controller.showSearchMatches(_visible ? _matches : const [], _matchIndex);
  }

  /// Tel de treffers opnieuw op de huidige tekst.
  ///
  /// [selectFirst] springt naar de eerste treffer; anders blijft de cursor op
  /// de treffer waar hij stond, tenzij die door de nieuwe telling niet meer
  /// bestaat.
  void recount({bool selectFirst = false}) {
    final matches = findAllMatches(
      controller.text,
      _query,
      caseSensitive: _caseSensitive,
    );
    _matches = matches;
    int? jumpIndex;
    if (matches.isEmpty) {
      _matchIndex = -1;
    } else if (selectFirst ||
        _matchIndex < 0 ||
        _matchIndex >= matches.length) {
      _matchIndex = 0;
      jumpIndex = 0;
    } else {
      jumpIndex = _matchIndex;
    }
    onChanged();
    syncHighlights();
    // Alleen springen zolang de balk openstaat. Een dichte balk heeft geen
    // treffer om naartoe te gaan, en de weergave verslepen zonder dat er iets
    // te zien is, leest als een editor die uit zichzelf wegloopt.
    final index = jumpIndex;
    if (_visible && index != null) onReveal(matches[index]);
  }

  /// Bijwerken terwijl er getypt wordt: de teller loopt mee, maar de cursor
  /// springt niet — anders zou de editor je tijdens het typen wegtrekken van
  /// waar je bezig bent.
  void refreshWhileTyping() {
    if (!_visible || _query.isEmpty) return;
    final matches = findAllMatches(
      controller.text,
      _query,
      caseSensitive: _caseSensitive,
    );
    _matches = matches;
    _matchIndex = matches.isEmpty
        ? -1
        : _matchIndex.clamp(0, matches.length - 1);
    syncHighlights();
  }

  /// Naar de volgende treffer, rondlopend aan het eind.
  void next() {
    if (_matches.isEmpty) return;
    _matchIndex = nextMatchIndex(_matchIndex, _matches.length);
    onChanged();
    syncHighlights();
    onReveal(_matches[_matchIndex]);
  }

  /// Naar de vorige treffer, rondlopend aan het begin.
  void previous() {
    if (_matches.isEmpty) return;
    _matchIndex = previousMatchIndex(_matchIndex, _matches.length);
    onChanged();
    syncHighlights();
    onReveal(_matches[_matchIndex]);
  }

  /// Vervang de treffer waar de cursor op staat en tel opnieuw. De cursor
  /// blijft op dezelfde plek in de rij staan, zodat herhaald vervangen door de
  /// tekst heen loopt in plaats van steeds terug naar het begin te gaan.
  void replaceCurrent() {
    if (_matchIndex < 0 || _matchIndex >= _matches.length) return;
    final match = _matches[_matchIndex];
    controller.text = replaceRange(controller.text, match, _replacement);
    recount(selectFirst: false);
    if (_matches.isEmpty) return;
    _matchIndex = _matchIndex.clamp(0, _matches.length - 1);
    onChanged();
    onReveal(_matches[_matchIndex]);
  }

  /// Vervang alle treffers in één keer. Daarna staat er niets meer gemarkeerd:
  /// de oude posities slaan nergens meer op en een nieuwe telling zou de cursor
  /// door het hele document laten springen.
  void replaceAll() {
    if (_query.isEmpty) return;
    final result = replaceAllInText(
      controller.text,
      _query,
      _replacement,
      caseSensitive: _caseSensitive,
    );
    controller.text = result.text;
    _matches = const [];
    _matchIndex = -1;
    onChanged();
    syncHighlights();
  }
}
