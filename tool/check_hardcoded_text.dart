// Bewaakt de regel die geen compiler kan bewaken: er staat geen zichtbare
// tekst hardgecodeerd in OciDeck. Alles wat een gebruiker leest, loopt door
// `l10n.d('…')` — dat is de enige plek waar een Nederlandse bronstring hoort.
//
// Waarom een aparte poort. `test/app_localizations_test.dart` controleert al
// dat elke `d('…')`-literal in alle talen vertaald is. Dat is de tweede helft
// van de belofte; de eerste helft — dat élke zichtbare string ook dóór `d()`
// gaat — werd door niets gecontroleerd. Het gat zat vooral in de INDIRECTE
// doorgeefluiken: `EditorField` roept `l10n.d(widget.label)` aan, dus
// `EditorField(label: 'Titel (H1)')` op de aanroepplaats is onzichtbaar voor
// een scanner die alleen naar `d('…')` zoekt. Van de 57 aanroepen droegen er 50
// een onvertaald label, terwijl de README beweerde dat tests dit afdwongen.
//
// ── Hoe de poort dat wél ziet ────────────────────────────────────────────────
//
// De analyse is AST-gebaseerd (net als tool/check_method_length.dart) en werkt
// met een DATASTROOM naar achteren, in drie stappen:
//
//   1. Zaaien. Een vaste tabel van Flutter-parameters die tekst op het scherm
//      zetten ([_flutterSinks]) plus de eerste parameter van `d()`/`t()`.
//   2. Terugpropageren tot een dekpunt. Wordt een parameter van een klasse of
//      functie doorgegeven aan een bestaande put, dan is die parameter zelf ook
//      een put. Zo bereikt `EditorField.label` de lijst via `d(widget.label)`,
//      en `showErrorSnackBar.message` via `Text(message)` — zonder dat iemand
//      ze met de hand hoeft op te schrijven.
//   3. Melden. Elke tekst-literal die op een putpositie staat.
//
// ── Twee soorten vondst: bronsleutel of écht hardgecodeerd ───────────────────
//
// Stap 2 loopt twee keer, vanaf twee gescheiden zaadverzamelingen, en dát
// verschil is de hele indeling:
//
//   * Vanaf `d()` → de posities waarvan vaststaat dat wat erin stroomt vertaald
//     wordt.
//   * Vanaf de RAUWE putten (`Text`, `Tooltip`, `InputDecoration`, …) → de
//     posities die tekst ongewijzigd op het scherm zetten.
//
// Zit een positie alleen in de eerste verzameling, dan is de literal erop een
// BRONSLEUTEL. Zit hij (ook) in de tweede, dan is het een overtreding: er is
// een weg waarlangs de Nederlandse tekst onvertaald op het scherm belandt. Bij
// `EditorField(label: 'Titel')` staat `'Titel'` precies waar hij hoort: het
// veld doet intern `l10n.d(widget.label)`, dus de literal ís het argument van
// `d()`, alleen een aanroep verderop. Dat is geen overtreding en mag niet naar
// `context.l10n.d('Titel')` herschreven worden — de eigenaar heeft daar bewust
// tegen gekozen. Wat wél moet: de string bestaat in alle 31 talen, net als een
// letterlijke `d('…')`. Dat dwingt `test/app_localizations_test.dart` af, dat
// hier `sourceKeysIn('lib')` voor gebruikt; het deelt de whitelist
// `unchangedInAllLanguages` met de letterlijke variant, zodat een identifier
// die in elke taal gelijk blijft (CWE, F-03) op één plek staat.
//
// Alleen de echte overtredingen tellen mee voor [hardcodedTextBaseline], en dat
// getal moet naar nul.
//
// Daardoor stuurt het TYPE de beslissing, niet de parameternaam. Dat is precies
// het verschil dat een naamgebaseerde grep niet kan maken: `title:` op een
// `MastgTest` of een `SlideSpec` is referentiedata en deck-inhoud, geen
// interfacetekst — en die duizend regels catalogus blijven dus stil.
//
// ── Wat de poort bewust NIET meldt ───────────────────────────────────────────
//
//   * De Nederlandse bronstring ín `d('…')`/`t('…')` — dat is de gesanctioneerde
//     vorm en het aangrijpingspunt van de vertaaltest.
//   * Commentaar en logregels (`logError`/`logWarning`): geen putten, dus ze
//     komen niet in de meting voor. Een technische boodschap hoort in het log.
//   * `throw SomeException('…')`: de projectafspraak is dat een uitzondering
//     technisch en Engelstalig is en in het logboek eindigt; de gebruiker ziet
//     de vertaalde tekst uit `userFacingError()` (lib/utils/user_facing_error.dart),
//     die per fouttype een `d('…')` kiest. Zou een dialoog ooit `e.toString()`
//     tonen, dan is dát de fout — niet de tekst van de uitzondering.
//   * Deck-inhoud: `lib/models/deck_template*.dart` vult een NIEUWE presentatie
//     met voorbeeldslides. Dat is documenttekst die de auteur meteen overtypt,
//     geen interface, en vertalen zou de opgeslagen presentatie veranderen.
//     Zie [_contentHomes].
//   * Referentiedata: de MASTG/MASWE/WSTG/MIAUW-catalogi dragen de officiële
//     Engelse titels van standaarden. Vertalen zou ze onvindbaar maken. Ze
//     vallen vanzelf buiten de meting (geen put), en dat is de bedoeling.
//   * Strings zonder letter (`''`, `'•'`, `'—'`, `'%'`) en losse tekens: geen
//     tekst om te vertalen.
//   * Zoektermen die niet op het scherm staan, zoals
//     `SettingsSearchEntry.keywords` — synoniemen waarop iemand zoekt, geen
//     interface. Ze vallen buiten beeld omdat dat veld nergens getoond wordt.
//
// ── Wat de poort (nog) NIET ziet ─────────────────────────────────────────────
//
// Eerlijk over de blinde vlekken, want een poort die je overschat is erger dan
// geen poort:
//
//   * RETOURWAARDEN. De analyse volgt ARGUMENTEN, niet wat een functie
//     teruggeeft. `String get dutchLabel => switch (this) { done => 'Klaar' }`
//     ontsnapt dus. Dat is hier geen open gat: die labels zijn de erkende
//     indirecte vorm (`l10n.d(status.dutchLabel)`) en hebben hun eigen
//     dekkingstests (slide_quality_localization_coverage_test,
//     privacy_rule_label_coverage_test). Een tweede poort zou ze dubbel
//     bewaken; deze poort dekt wat die tests NIET zagen.
//   * Aanroepen op een variabele van een methode die meer dan één klasse
//     declareert. Zonder opgeloste types is `x.show(…)` niet te plaatsen, dus
//     dan telt hij niet mee. Een unieke methodenaam wél.
//   * Cascades (`messenger..showSnackBar(…)`). De inhoud ervan bereikt de poort
//     meestal alsnog via de `Text(…)` erbinnen.
//   * Strings die via een lijst, een veld of een `Map` reizen waar geen
//     [_mapValueSinks]-ingang voor is.
//
// ── De ratchet ───────────────────────────────────────────────────────────────
//
// De poort kan niet op nul beginnen; er staan honderden overtredingen. Dus één
// getal als plafond, dat alleen omlaag mag — geen lijst van toegestane
// bestanden. Een lijst groeit stilletjes mee met elke uitzondering; een getal
// niet. Zakt het werkelijke aantal onder het plafond zonder dat het plafond
// meegaat, dan faalt de poort óók: de winst wordt meteen vastgezet in plaats
// van later weer opgesoupeerd. Dat is dezelfde omgekeerde ratchet als bij de
// dekkingsvloer.
//
// Het plafond MOET nul zijn vóór de eerste release (0.1.0). Zolang het boven
// nul staat, is de belofte "alles is vertaald" niet waar.
//
// Gebruik:
//   dart run tool/check_hardcoded_text.dart            # de poort
//   dart run tool/check_hardcoded_text.dart --list     # de volledige lijst
//                                                      # per gebied, voor de
//                                                      # opruimbatches

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// Het aantal ECHT hardgecodeerde zichtbare strings dat `lib/` nog mag
/// bevatten — literals die het scherm bereiken zonder ooit door `d()` te gaan.
///
/// Bronsleutels tellen hier NIET in mee: die staan op hun plek en worden op
/// vertaaldekking bewaakt in plaats van op aantal (zie de kop).
///
/// RATCHET: dit getal mag ALLEEN omlaag. Ruim je er tien op, verlaag het dan
/// met tien — de run drukt een tip met het nieuwe getal af, en weigert een
/// stille daling. Verhogen betekent dat er nieuwe onvertaalde tekst bij is
/// gekomen; dat is geen reden om het plafond op te rekken maar om de string
/// door `l10n.d('…')` te halen (`make add-l10n SPEC=…` doet de 31 vertalingen).
///
/// Waarom het getal er staat: de opruiming zelf is honderden strings groot en
/// gaat in batches. Wat NIET mag wachten is dat er nieuwe bij komen. Dit getal
/// is de dichte deur; de opruiming loopt erachter door.
///
/// **Dit moet 0 zijn vóór release 0.1.0.**
const int hardcodedTextBaseline = 15;

/// Bestanden die deck-INHOUD dragen in plaats van interfacetekst: de sjablonen
/// die een nieuwe presentatie met voorbeeldslides vullen. Die tekst is vanaf
/// het eerste moment eigendom van de auteur — hij staat in het opgeslagen
/// bestand en wordt overtypt. Vertalen zou de inhoud van een document
/// veranderen afhankelijk van de menutaal, en dat is niet hetzelfde probleem.
const Set<String> _contentHomes = {
  'lib/models/deck_template.dart',
  'lib/models/deck_template_briefings.dart',
  'lib/models/deck_template_general.dart',
  'lib/models/deck_template_info_safety.dart',
  'lib/models/deck_template_sessions.dart',
  'lib/models/deck_template_work_a.dart',
  'lib/models/deck_template_work_b.dart',
};

/// Flutter-constructors en hun parameters die tekst op het scherm zetten.
///
/// Dit is de zaadlijst: alles wat de app zelf doorgeeft aan deze posities wordt
/// er automatisch bij gevonden (zie de propagatie in [_solveSinks]). `#0` is de
/// eerste positionele parameter.
const Map<String, List<String>> _flutterSinks = {
  'Text': ['#0', 'semanticsLabel'],
  'SelectableText': ['#0', 'semanticsLabel'],
  'TextSpan': ['text', 'semanticsLabel'],
  'Tooltip': ['message'],
  'Semantics': [
    'label',
    'hint',
    'value',
    'tooltip',
    'onTapHint',
    'onLongPressHint',
    'increasedValue',
    'decreasedValue',
  ],
  'InputDecoration': [
    'labelText',
    'hintText',
    'helperText',
    'errorText',
    'prefixText',
    'suffixText',
    'counterText',
    'semanticCounterText',
  ],
  'IconButton': ['tooltip'],
  'FloatingActionButton': ['tooltip'],
  'PopupMenuButton': ['tooltip'],
  'SnackBarAction': ['label'],
  'Tab': ['text', 'semanticLabel'],
  'Slider': ['label'],
  'Icon': ['semanticLabel'],
  'Image': ['semanticLabel'],
  'Image.asset': ['semanticLabel'],
  'Image.file': ['semanticLabel'],
  'Image.memory': ['semanticLabel'],
  'Image.network': ['semanticLabel'],
  'BottomNavigationBarItem': ['label', 'tooltip'],
  'NavigationDestination': ['label', 'tooltip'],
  'NavigationRailDestination': ['label'],
  'DropdownMenuEntry': ['label'],
  'MenuAcceleratorLabel': ['#0'],
  'PlatformMenu': ['label'],
  'PlatformMenuItem': ['label'],
  'PlatformMenuItemGroup': ['label'],
  'CircularProgressIndicator': ['semanticsLabel'],
  'LinearProgressIndicator': ['semanticsLabel'],
  'RefreshIndicator': ['semanticsLabel'],
  'SearchBar': ['hintText'],
  'CupertinoTextField': ['placeholder'],
  'AboutDialog': ['applicationName', 'applicationLegalese'],
  'LicensePage': ['applicationName', 'applicationLegalese'],
  // Het label van een bestandsfilter staat in de dialoog van het besturings-
  // systeem — de gebruiker leest het.
  'XTypeGroup': ['label'],
};

/// Vrije functies uit Flutter/plug-ins met zichtbare tekstparameters.
const Map<String, List<String>> _flutterFunctionSinks = {
  'showAboutDialog': ['applicationName', 'applicationLegalese'],
  'showDatePicker': [
    'helpText',
    'cancelText',
    'confirmText',
    'errorFormatText',
    'errorInvalidText',
    'errorInvalidRangeText',
    'fieldStartLabelText',
    'fieldEndLabelText',
    'fieldLabelText',
    'fieldHintText',
  ],
  'showTimePicker': [
    'helpText',
    'cancelText',
    'confirmText',
    'errorInvalidText',
  ],
};

/// De vertaalfunctie zelf. Een parameter die híer in stroomt is een bronstring
/// en dus een put; een literal die er rechtstreeks in staat is juist de goede
/// vorm en wordt niet gemeld (zie [_sanctionedSinks]).
const String _translateCallee = 'm|AppLocalizations.d';
const String _translateSink = '$_translateCallee|#0';

/// Putten waar een letterlijke string de BEDOELING is.
const Set<String> _sanctionedSinks = {
  _translateSink,
  // `formatSlideQualityIssue` heeft een lokale helper
  // `String label(String key) => l10n.d(issue.args[key] ?? key);`. De vier
  // aanroepen `label('label')` geven daar de SLEUTEL in `issue.args` door, niet
  // iets wat iemand leest. De `?? key`-tak is een noodrem voor een melding die
  // vergeten is haar eigen argument te vullen; die tekst hoort de gebruiker
  // nooit te zien, en 31 vertalingen voor het woord "label" zouden dat ook niet
  // veranderen. De WAARDEN in die map worden wél bewaakt — via
  // [_mapValueSinks], aan de schrijfkant in lib/services.
  'l|lib/l10n/slide_quality_localization.dart|label|#0',
};

/// Eigen sleutel-waardekanalen: posities waar een MAP wordt doorgegeven en de
/// WAARDEN daarin zichtbare tekst zijn.
///
/// `SlideQualityIssue.args` is er zo een. De analyse in `lib/services/` stopt er
/// Nederlandse brontekst in ("Thema bodytekst", "Achtergrondafbeelding") en
/// `SlideQualityLocalization.label()` haalt die er weer uit met
/// `l10n.d(issue.args[key] ?? key)`. Dat is precies het soort doorgeefluik
/// waar deze poort voor bestaat — een servicetekst die in een paneel belandt —
/// maar een sleutel in een map is geen parameter, dus de propagatie kan er niet
/// vanzelf doorheen. Vandaar deze korte, met naam genoemde lijst — per positie
/// precies de sleutels die getoond worden, want in dezelfde map zitten ook
/// getallen en vlaggen (`'ratio'`, `'largeText'`) die niemand leest als taal.
///
/// [_MapChannel.localizes] zegt of de LEZER de waarde door `d()` haalt. Dat is
/// per kanaal met de hand vastgesteld en moet dat blijven: de propagatie kan
/// hier niet doorheen kijken, dus als niemand het opschrijft weet de poort het
/// niet. Staat hij op `true`, dan zijn de literals aan de schrijfkant
/// bronsleutels; op `false` zijn het echte overtredingen.
const Map<String, _MapChannel> _mapValueSinks = {
  // `l10n.d(issue.args[key] ?? key)` in slide_quality_localization.dart — de
  // servicetekst wordt aan de leeskant vertaald.
  'c|SlideQualityIssue|args': _MapChannel({'label'}, localizes: true),
};

/// Eén sleutel-waardekanaal: welke sleutels getoond worden, en of de leeskant
/// ze vertaalt.
class _MapChannel {
  const _MapChannel(this.shownKeys, {required this.localizes});

  final Set<String> shownKeys;
  final bool localizes;
}

/// Minstens één letter — anders valt er niets te vertalen (`'•'`, `'—'`, `'%'`,
/// `''`, `'12'`). Latijn plus de diakrieten die het Nederlands en de andere
/// brontalen gebruiken.
///
/// Het blok À-ɏ is niet louter letters: er staan twee rekenkundige tekens in,
/// `×` (U+00D7) en `÷` (U+00F7). Die uitgezonderd, want anders telt een
/// scheidingsteken als tekst. Concreet gebeurde dat bij
/// `'$title  ·  ${paths.length} × ${l10n.d('Identieke kopieën')}'`: elk woord
/// erin loopt al door `d()`, alleen de scheidingstekens zijn letterlijk, en
/// toch stond die regel als overtreding in de lijst. Er viel niets te
/// vertalen, dus er viel niets op te lossen — een melding die alleen maar kan
/// worden weggekeken, en dat is precies wat een poort onbetrouwbaar maakt.
final _hasLetter = RegExp(r'[A-Za-zÀ-ɏͰ-ϿЀ-ӿ]');
final _notALetter = RegExp('[×÷]');

/// Of [text] iets is dat een gebruiker als taal leest.
///
/// Bewust ruim: minstens twee tekens en minstens één letter, verder niets. Een
/// filter op "ziet eruit als een interne sleutel" (één woord in kleine letters)
/// lag voor de hand, maar kostte meer dan het opleverde — het gooide `' min'`
/// en `'esc'` weg, en dat zijn wél teksten die iemand leest. Liever een handvol
/// sleutels te veel in de lijst dan één zichtbare string die stil wegvalt.
bool isVisibleText(String text) {
  final trimmed = text.trim().replaceAll(_notALetter, '');
  return trimmed.length >= 2 && _hasLetter.hasMatch(trimmed);
}

bool _isTranslationData(String path) =>
    path.replaceAll(r'\', '/').contains('lib/l10n/translations/');

/// Eén gemelde tekst-literal op een putpositie.
class Violation {
  Violation(
    this.path,
    this.line,
    this.text,
    this.sink, {
    required this.isSourceKey,
  });

  final String path;
  final int line;
  final String text;
  final String sink;

  /// Of de literal onderweg gegarandeerd door `l10n.d('…')` gaat.
  ///
  /// `true` betekent BRONSLEUTEL: geen overtreding, maar hij moet wel in alle
  /// 31 talen bestaan. `false` betekent een echte overtreding: zichtbare tekst
  /// die niemand vertaalt.
  final bool isSourceKey;

  String get location => '$path:$line';
}

/// Eén argumentpositie in één aanroep: waar hij heen kán gaan ([sinks]), welke
/// literals erin staan, en welke putten hij zelf zou worden als een van die
/// bestemmingen er een blijkt te zijn ([origins]).
///
/// Meerdere bestemmingen omdat de AST hier niet opgelost is: `Foo.bar(…)` kan
/// een benoemde constructor of een statische methode zijn, en de parser kan dat
/// verschil niet zien. Beide sleutels tellen mee; wat niet bestaat, matcht toch
/// nooit.
class _Use {
  _Use(this.sinks, this.origins, this.literals, this.path, this.line);

  final List<String> sinks;
  final List<String> origins;
  final List<String> literals;
  final String path;
  final int line;

  bool reaches(Set<String> solved) => sinks.any(solved.contains);
}

/// Scant [root] en levert elke hardgecodeerde zichtbare string op, gesorteerd
/// op locatie.
///
/// Los van [main] zodat een test hem op een kleine fixture-map kan loslaten en
/// kan vaststellen dát het doorgeefluik gevonden wordt — de reden dat deze
/// poort bestaat. Zonder zo'n test kan de analyse stilvallen bij een
/// analyzer-upgrade (een AST-accessor die verschuift) en dan meldt hij nul.
List<Violation> scanForHardcodedText(String root) {
  final index = _Index();
  final uses = <_Use>[];
  final units = <({String path, CompilationUnit unit, LineInfo lineInfo})>[];

  for (final file in _dartFiles(Directory(root))) {
    final path = file.path.replaceAll(r'\', '/');
    if (_isTranslationData(path)) continue;
    if (_contentHomes.contains(path)) continue;
    final result = parseFile(
      // De analyzer weigert een relatief pad; `scanForHardcodedText('lib')`
      // vanuit een test gaf daar een harde fout op. Het GEMELDE pad blijft
      // relatief — dat is wat een mens in de lijst wil lezen.
      path: file.absolute.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    units.add((path: path, unit: result.unit, lineInfo: result.lineInfo));
    result.unit.visitChildren(_IndexVisitor(index, path));
  }

  for (final u in units) {
    u.unit.visitChildren(_UseVisitor(index, uses, u.path, u.lineInfo));
  }

  return _collect(uses, _solveLocalizedSinks(uses), _solveRawSinks(uses))
    ..sort((a, b) => a.location.compareTo(b.location));
}

/// De Nederlandse bronstrings die via een doorgeefluik in `l10n.d('…')` landen.
///
/// `test/app_localizations_test.dart` gebruikt dit om af te dwingen dat ze in
/// alle 31 talen bestaan — dezelfde eis die daar al voor een letterlijke
/// `d('…')` geldt. De literals die er rechtstreeks in staan zitten er níet in
/// (die vindt de test zelf met haar eigen scan op de bron).
Set<String> sourceKeysIn(String root) => {
  for (final v in scanForHardcodedText(root))
    if (v.isSourceKey) v.text,
};

void main(List<String> args) {
  final listOnly = args.contains('--list');
  final found = scanForHardcodedText('lib');
  final violations = [
    for (final v in found)
      if (!v.isSourceKey) v,
  ];

  if (listOnly) {
    stdout.write(renderList(found));
    exit(0);
  }
  _report(violations, found.length - violations.length);
}

/// Dekpunt vanaf `d()`: de posities waarvan vaststaat dat wat erin stroomt
/// vertaald wordt.
///
/// Samen met [_solveRawSinks] is dit de hele indeling van deze poort. Zit een
/// positie hier ín en in [_solveRawSinks] níet, dan is een literal erop een
/// bronsleutel; anders is het een echte overtreding.
Set<String> _solveLocalizedSinks(List<_Use> uses) => _propagate(uses, {
  _translateSink,
  for (final e in _mapValueSinks.entries)
    if (e.value.localizes) e.key,
});

/// Dekpunt vanaf de RAUWE putten: de Flutter-parameters die tekst rechtstreeks
/// op het scherm zetten, plus de sleutel-waardekanalen waarvan de leeskant niet
/// vertaalt.
///
/// Waarom dit een eigen dekpunt is en niet "alles min de vertaalde": een
/// parameter kan langs twee wegen tegelijk naar buiten. `HalfField.label` die
/// in één tak `d(label)` doet en in de andere `Tooltip(message: label)` staat
/// in béide dekpunten — en dan wint de rauwe tak, want die toont de
/// Nederlandse tekst ook aan wie Grieks leest.
///
/// Dat de twee dekpunten samen precies het oude, gezamenlijke dekpunt zijn is
/// geen toeval: elke propagatiestap heeft één premisse (`use.reaches`), dus de
/// afsluiting verdeelt zich over de vereniging van de zaadverzamelingen.
Set<String> _solveRawSinks(List<_Use> uses) {
  final seeds = <String>{};
  _flutterSinks.forEach((type, selectors) {
    for (final s in selectors) {
      seeds.add('c|$type|$s');
    }
  });
  _flutterFunctionSinks.forEach((fn, selectors) {
    for (final s in selectors) {
      seeds.add('f|$fn|$s');
    }
  });
  _mapValueSinks.forEach((sink, channel) {
    if (!channel.localizes) seeds.add(sink);
  });
  return _propagate(uses, seeds);
}

Set<String> _propagate(List<_Use> uses, Set<String> seeds) {
  final sinks = <String>{...seeds};
  var changed = true;
  while (changed) {
    changed = false;
    for (final use in uses) {
      if (!use.reaches(sinks)) continue;
      for (final origin in use.origins) {
        if (sinks.add(origin)) changed = true;
      }
    }
  }
  return sinks;
}

List<Violation> _collect(
  List<_Use> uses,
  Set<String> localized,
  Set<String> raw,
) {
  final out = <Violation>[];
  final seen = <String>{};
  for (final use in uses) {
    final reached = use.sinks
        .where((s) => localized.contains(s) || raw.contains(s))
        .toList();
    if (reached.isEmpty) continue;
    if (reached.every(_sanctionedSinks.contains)) continue;
    // Eén weg die niet localiseert is genoeg om het een overtreding te maken:
    // die weg toont de rauwe Nederlandse tekst.
    final isSourceKey = reached.every(
      (s) => localized.contains(s) && !raw.contains(s),
    );
    for (final text in use.literals) {
      if (!isVisibleText(text)) continue;
      // Dezelfde literal kan via twee mogelijke bestemmingen binnenkomen; hij
      // staat maar één keer in de code, dus telt hij één keer.
      if (!seen.add('${use.path}:${use.line}:$text')) continue;
      out.add(
        Violation(
          use.path,
          use.line,
          text,
          reached.first,
          isSourceKey: isSourceKey,
        ),
      );
    }
  }
  return out;
}

/// Het gebied waar een bestand bij hoort — de indeling waarin de opruiming in
/// batches gaat.
String areaOf(String path) {
  if (path.startsWith('lib/widgets/editors/')) return 'editors';
  if (path.startsWith('lib/widgets/dialogs/')) return 'dialogen';
  if (path.startsWith('lib/widgets/panels/')) return 'panelen';
  if (path.startsWith('lib/widgets/presentation/')) return 'presentatie';
  if (path.startsWith('lib/widgets/slides/')) return 'slides';
  if (path.startsWith('lib/widgets/reader/')) return 'lezer';
  if (path.startsWith('lib/widgets/shell/') ||
      path.startsWith('lib/widgets/markdown_editor/') ||
      path.startsWith('lib/widgets/')) {
    return 'schil';
  }
  if (path.startsWith('lib/services/')) return 'services';
  if (path.startsWith('lib/state/')) return 'state';
  if (path.startsWith('lib/models/')) return 'models';
  if (path.startsWith('lib/utils/')) return 'utils';
  return 'overig';
}

/// De volledige lijst, in twee delen (echte overtredingen, dan bronsleutels) en
/// per deel gegroepeerd per gebied: `bestand:regel  "string"`.
String renderList(List<Violation> found) {
  final buffer = StringBuffer()
    ..writeln('# Zichtbare tekst-literals in lib/')
    ..writeln('#')
    ..writeln(
      '# Gegenereerd met: dart run tool/check_hardcoded_text.dart --list',
    )
    ..writeln('#')
    ..writeln(
      '# Per regel: bestand:regel  "de string"  → de put die hem toont.',
    )
    ..writeln();
  _renderSection(
    buffer,
    'ECHTE OVERTREDINGEN — bereiken het scherm zonder d()',
    [
      for (final v in found)
        if (!v.isSourceKey) v,
    ],
  );
  _renderSection(
    buffer,
    'BRONSLEUTELS — gaan door d(), moeten in alle 31 talen bestaan',
    [
      for (final v in found)
        if (v.isSourceKey) v,
    ],
  );
  return buffer.toString();
}

void _renderSection(StringBuffer buffer, String title, List<Violation> items) {
  final byArea = <String, List<Violation>>{};
  for (final v in items) {
    byArea.putIfAbsent(areaOf(v.path), () => []).add(v);
  }
  final areas = byArea.keys.toList()
    ..sort((a, b) => byArea[b]!.length.compareTo(byArea[a]!.length));

  buffer
    ..writeln('#' * 78)
    ..writeln(
      '# $title: ${items.length} string(s) in '
      '${items.map((v) => v.path).toSet().length} bestand(en).',
    )
    ..writeln('#' * 78)
    ..writeln();
  for (final area in areas) {
    final entries = byArea[area]!;
    final files = entries.map((v) => v.path).toSet().length;
    buffer
      ..writeln('=' * 78)
      ..writeln('## $area — ${entries.length} string(s), $files bestand(en)')
      ..writeln('=' * 78);
    var current = '';
    for (final v in entries) {
      if (v.path != current) {
        current = v.path;
        buffer.writeln('\n--- $current');
      }
      buffer.writeln('${v.line}: "${_oneLine(v.text)}"   [${v.sink}]');
    }
    buffer.writeln();
  }
}

String _oneLine(String text) {
  final flat = text.replaceAll('\n', '\\n').replaceAll('\r', '\\r');
  return flat.length <= 120 ? flat : '${flat.substring(0, 117)}…';
}

void _report(List<Violation> violations, int sourceKeys) {
  final count = violations.length;
  final byArea = <String, int>{};
  for (final v in violations) {
    byArea.update(areaOf(v.path), (n) => n + 1, ifAbsent: () => 1);
  }
  final spread =
      (byArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => '${e.key} ${e.value}')
          .join(', ');

  if (count > hardcodedTextBaseline) {
    final fresh = violations.take(40).toList();
    stderr
      ..writeln('Hardcoded text check FAILED:')
      ..writeln(
        '  Hardgecodeerde zichtbare strings gestegen naar $count (plafond '
        '$hardcodedTextBaseline). Elke zichtbare tekst hoort door '
        "l10n.d('…') te lopen; `make add-l10n SPEC=…` zet de 31 vertalingen "
        'erbij. Verdeling: $spread.',
      )
      ..writeln('  Eerste ${fresh.length} van $count:');
    for (final v in fresh) {
      stderr.writeln('    ${v.location}: "${_oneLine(v.text)}"');
    }
    stderr.writeln(
      '  Volledige lijst: dart run tool/check_hardcoded_text.dart --list',
    );
    exit(1);
  }

  if (count < hardcodedTextBaseline) {
    stderr
      ..writeln('Hardcoded text check FAILED:')
      ..writeln(
        '  Goed nieuws, maar zet het vast: het aantal hardgecodeerde zichtbare '
        'strings is gedaald naar $count terwijl hardcodedTextBaseline nog op '
        '$hardcodedTextBaseline staat. Zet hardcodedTextBaseline in '
        'tool/check_hardcoded_text.dart op $count, anders sijpelt de winst er '
        'ongemerkt weer uit. Het doel is 0 vóór release 0.1.0.',
      );
    exit(1);
  }

  stdout
    ..writeln(
      'Hardcoded text OK: $count zichtbare string(en) nog niet door '
      "l10n.d('…') (plafond $hardcodedTextBaseline, doel 0 vóór 0.1.0).",
    )
    ..writeln('  Verdeling: ${count == 0 ? '—' : spread}.')
    ..writeln(
      '  Daarnaast $sourceKeys bronsleutel(s) via een doorgeefluik naar d(); '
      'die horen daar en worden op vertaaldekking bewaakt in '
      'test/app_localizations_test.dart.',
    );
  exit(0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Index: klassen, velden, constructors en methodes, zodat een naam in stap 2
// aan een declaratie te knopen is.
// ─────────────────────────────────────────────────────────────────────────────

class _Index {
  /// Klasse → veldnamen.
  final fields = <String, Set<String>>{};

  /// Klasse → veld → de constructor-selectors die dat veld vullen.
  final fieldSelectors = <String, Map<String, Set<String>>>{};

  /// State-klasse → de widget-klasse waar `widget.x` naar wijst.
  final stateWidget = <String, String>{};

  /// Declaratiesleutel (`c|Type`, `f|naam`, `m|Klasse.naam`) → parameternaam →
  /// selector zoals de aanroeper hem schrijft.
  final paramSelectors = <String, Map<String, String>>{};

  /// Methodenaam → de klassen die hem declareren. Is dat er precies één, dan
  /// mag een aanroep op een variabele (`helper.foo(...)`) daaraan geknoopt
  /// worden; anders blijft die aanroep buiten beeld.
  final methodOwners = <String, Set<String>>{};
}

class _IndexVisitor extends RecursiveAstVisitor<void> {
  _IndexVisitor(this.index, this.path);

  final _Index index;
  final String path;
  String _class = '';

  /// Een enum draagt zijn UI-tekst in de argumenten van zijn constanten
  /// (`done('Klaar')`), dus de constructor ervan moet net zo goed geïndexeerd
  /// worden als die van een klasse.
  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final previous = _class;
    _class = node.namePart.typeName.lexeme;
    index.fields.putIfAbsent(_class, () => <String>{});
    super.visitEnumDeclaration(node);
    _class = previous;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previous = _class;
    _class = node.namePart.typeName.lexeme;
    index.fields.putIfAbsent(_class, () => <String>{});
    final superclass = node.extendsClause?.superclass;
    final args = superclass?.typeArguments?.arguments;
    final superName = superclass?.name.lexeme ?? '';
    // `class _XState extends State<X>` / `ConsumerState<X>`: `widget.foo` in
    // deze klasse wijst naar een veld van X.
    if (superName.endsWith('State') && args != null && args.isNotEmpty) {
      final first = args.first;
      if (first is NamedType) index.stateWidget[_class] = first.name.lexeme;
    }
    super.visitClassDeclaration(node);
    _class = previous;
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (final v in node.fields.variables) {
      index.fields.putIfAbsent(_class, () => <String>{}).add(v.name.lexeme);
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final named = node.name?.lexeme;
    final key = named == null ? 'c|$_class' : 'c|$_class.$named';
    _recordParams(key, node.parameters);
    // `this.label` in de parameterlijst: het veld en de parameter zijn één.
    _recordFieldFormals(_class, key, node.parameters);
    // `: label = someParam` in de initialisatielijst telt net zo goed.
    for (final initializer in node.initializers) {
      if (initializer is! ConstructorFieldInitializer) continue;
      final value = initializer.expression;
      if (value is! SimpleIdentifier) continue;
      final selector = index.paramSelectors[key]?[value.name];
      if (selector == null) continue;
      index.fieldSelectors
          .putIfAbsent(_class, () => {})
          .putIfAbsent(initializer.fieldName.name, () => {})
          .add('$key|$selector');
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    index.methodOwners.putIfAbsent(name, () => <String>{}).add(_class);
    _recordParams('m|$_class.$name', node.parameters);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    // Lokale functies tellen mee, en juist zij dragen de servicetekst: de
    // kwaliteitsanalyse bouwt haar meldingen met een `addIssue(...)`-helper
    // binnen één methode. Ze krijgen een sleutel met het pad erin, want ze zijn
    // alleen in hun eigen bestand aan te roepen — zo botst `addIssue` in het
    // ene bestand niet met `addIssue` in het andere.
    final key = node.parent is CompilationUnit ? 'f|$name' : 'l|$path|$name';
    _recordParams(key, node.functionExpression.parameters);
    super.visitFunctionDeclaration(node);
  }

  void _recordParams(String key, FormalParameterList? parameters) {
    if (parameters == null) return;
    final map = index.paramSelectors.putIfAbsent(key, () => {});
    var positional = 0;
    for (final p in parameters.parameters) {
      final name = p.name?.lexeme;
      final selector = p.isNamed ? name : '#${positional++}';
      if (name == null || selector == null) continue;
      map[name] = selector;
    }
  }

  void _recordFieldFormals(
    String owner,
    String key,
    FormalParameterList? parameters,
  ) {
    if (parameters == null) return;
    var positional = 0;
    for (final p in parameters.parameters) {
      final inner = p is DefaultFormalParameter ? p.parameter : p;
      final name = inner.name?.lexeme;
      final selector = p.isNamed ? name : '#${positional++}';
      if (inner is! FieldFormalParameter || name == null || selector == null) {
        continue;
      }
      index.fieldSelectors
          .putIfAbsent(owner, () => {})
          .putIfAbsent(name, () => {})
          .add('$key|$selector');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gebruik: elke aanroep, elk argument, en waar dat argument vandaan komt.
// ─────────────────────────────────────────────────────────────────────────────

class _UseVisitor extends RecursiveAstVisitor<void> {
  _UseVisitor(this.index, this.uses, this.path, this.lineInfo);

  final _Index index;
  final List<_Use> uses;
  final String path;
  final LineInfo lineInfo;

  String _class = '';
  String _executable = '';

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previous = _class;
    _class = node.namePart.typeName.lexeme;
    super.visitClassDeclaration(node);
    _class = previous;
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final previous = _class;
    _class = node.namePart.typeName.lexeme;
    super.visitEnumDeclaration(node);
    _class = previous;
  }

  /// `done('Klaar')` in een enum is een constructoraanroep met een eigen
  /// AST-knoop — de gewone bezoeker ziet hem niet.
  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    final arguments = node.arguments;
    if (arguments != null) {
      final named = arguments.constructorSelector?.name.name;
      _record([
        'c|${named == null ? _class : '$_class.$named'}',
      ], arguments.argumentList);
    }
    super.visitEnumConstantDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final named = node.name?.lexeme;
    _executable = named == null ? 'c|$_class' : 'c|$_class.$named';
    super.visitConstructorDeclaration(node);
    _executable = '';
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _executable = 'm|$_class.${node.name.lexeme}';
    super.visitMethodDeclaration(node);
    _executable = '';
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final previous = _executable;
    final name = node.name.lexeme;
    _executable = node.parent is CompilationUnit ? 'f|$name' : 'l|$path|$name';
    super.visitFunctionDeclaration(node);
    _executable = previous;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    final named = node.constructorName.name?.name;
    _record(['c|${named == null ? type : '$type.$named'}'], node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(_calleesOf(node), node.argumentList);
    super.visitMethodInvocation(node);
  }

  /// De declaratiesleutels waar deze aanroep heen kán gaan.
  ///
  /// De AST is niet opgelost — dat is bewust, want een `AnalysisContext` over
  /// de hele boom kost minuten en deze poort moet in seconden draaien. De prijs
  /// is dat de parser `Text('x')` niet van een functieaanroep kan
  /// onderscheiden: zonder `const`/`new` is elke constructoraanroep gewoon een
  /// [MethodInvocation]. De naamconventie doet de rest — begint de naam met een
  /// hoofdletter (eventueel na underscores), dan is het een type.
  List<String> _calleesOf(MethodInvocation node) {
    final name = node.methodName.name;
    // `l10n.d(…)` / `context.l10n.d(…)` / `AppLocalizations.of(c).d(…)`: altijd
    // de vertaalfunctie, hoe de aanroeper er ook bij komt.
    if (name == 'd' || name == 't') return const [_translateCallee];
    final target = node.target;
    if (target == null || target is ThisExpression) {
      if (_isTypeName(name)) return ['c|$name'];
      // Een lokale helper, een methode van deze klasse, of een vrije functie.
      return [
        'l|$path|$name',
        if (_class.isNotEmpty) 'm|$_class.$name',
        'f|$name',
      ];
    }
    if (target is SimpleIdentifier && _isTypeName(target.name)) {
      // Benoemde constructor of statische methode — niet te onderscheiden.
      return ['c|${target.name}.$name', 'm|${target.name}.$name'];
    }
    // Aanroep op een variabele: alleen te plaatsen als precies één klasse deze
    // methodenaam declareert.
    final owners = index.methodOwners[name];
    if (owners != null && owners.length == 1) {
      return ['m|${owners.single}.$name'];
    }
    return const [];
  }

  /// Of [name] een typenaam is: een hoofdletter, eventueel achter underscores
  /// (`_PrivateRow`). Een private helper heet `_buildRow` en valt dus af.
  bool _isTypeName(String name) {
    final bare = name.replaceFirst(RegExp(r'^_+'), '');
    if (bare.isEmpty) return false;
    final first = bare[0];
    return first.toUpperCase() == first && first.toLowerCase() != first;
  }

  void _record(List<String> callees, ArgumentList arguments) {
    if (callees.isEmpty) return;
    var positional = 0;
    for (final argument in arguments.arguments) {
      final String selector;
      final Expression value;
      if (argument is NamedExpression) {
        selector = argument.name.label.name;
        value = argument.expression;
      } else {
        selector = '#${positional++}';
        value = argument;
      }
      final sinks = [for (final callee in callees) '$callee|$selector'];
      final shown = <String>{
        for (final sink in sinks) ...?_mapValueSinks[sink]?.shownKeys,
      };
      if (value is SetOrMapLiteral && shown.isNotEmpty) {
        _recordMapValues(sinks, shown, value);
        continue;
      }
      final literals = <String>[];
      final origins = <String>[];
      _flatten(value, literals, origins);
      if (literals.isEmpty && origins.isEmpty) continue;
      uses.add(
        _Use(
          sinks,
          origins,
          literals,
          path,
          lineInfo.getLocation(value.offset).lineNumber,
        ),
      );
    }
  }

  /// De waarden onder [shown] in een `_mapValueSinks`-map zijn zichtbare tekst;
  /// de sleutels zelf zijn interne identifiers en blijven buiten schot.
  void _recordMapValues(
    List<String> sinks,
    Set<String> shown,
    SetOrMapLiteral map,
  ) {
    for (final element in map.elements) {
      if (element is! MapLiteralEntry) continue;
      final key = element.key;
      if (key is! SimpleStringLiteral || !shown.contains(key.value)) continue;
      final literals = <String>[];
      final origins = <String>[];
      _flatten(element.value, literals, origins);
      if (literals.isEmpty && origins.isEmpty) continue;
      uses.add(
        _Use(
          sinks,
          origins,
          literals,
          path,
          lineInfo.getLocation(element.value.offset).lineNumber,
        ),
      );
    }
  }

  /// Splitst een argument in de letterlijke teksten die erin staan en de
  /// parameters/velden waar hij vandaan komt. Doorloopt `?:`, `??`, `+` en
  /// haakjes, zodat `Text(kort ? 'Ja' : 'Nee')` beide takken meldt.
  void _flatten(Expression node, List<String> literals, List<String> origins) {
    if (node is ParenthesizedExpression) {
      _flatten(node.expression, literals, origins);
      return;
    }
    if (node is ConditionalExpression) {
      _flatten(node.thenExpression, literals, origins);
      _flatten(node.elseExpression, literals, origins);
      return;
    }
    if (node is BinaryExpression &&
        (node.operator.lexeme == '??' || node.operator.lexeme == '+')) {
      _flatten(node.leftOperand, literals, origins);
      _flatten(node.rightOperand, literals, origins);
      return;
    }
    if (node is SimpleStringLiteral) {
      literals.add(node.value);
      return;
    }
    if (node is AdjacentStrings) {
      final joined = StringBuffer();
      for (final part in node.strings) {
        if (part is SimpleStringLiteral) joined.write(part.value);
      }
      if (joined.isNotEmpty) literals.add(joined.toString());
      return;
    }
    if (node is StringInterpolation) {
      // Alleen de vaste stukken tellen: `'Regel ${n}'` draagt het woord
      // "Regel", en dat woord moet vertaald worden.
      final joined = StringBuffer();
      for (final element in node.elements) {
        if (element is InterpolationString) joined.write(element.value);
      }
      final text = joined.toString();
      if (_hasLetter.hasMatch(text)) literals.add(text);
      return;
    }
    origins.addAll(_originsOf(node));
  }

  /// De putsleutels die deze uitdrukking zou opleveren als hij op een
  /// putpositie staat: de parameter van de omsluitende declaratie, of het veld
  /// van de omsluitende klasse (en dus de constructor-parameters die dat veld
  /// vullen).
  List<String> _originsOf(Expression node) {
    if (node is SimpleIdentifier) {
      final selector = index.paramSelectors[_executable]?[node.name];
      if (selector != null) return ['$_executable|$selector'];
      return _fieldOrigins(_class, node.name);
    }
    if (node is PrefixedIdentifier && node.prefix.name == 'widget') {
      final owner = index.stateWidget[_class];
      if (owner != null) return _fieldOrigins(owner, node.identifier.name);
    }
    if (node is PropertyAccess && node.target is ThisExpression) {
      return _fieldOrigins(_class, node.propertyName.name);
    }
    return const [];
  }

  List<String> _fieldOrigins(String owner, String field) {
    final selectors = index.fieldSelectors[owner]?[field];
    if (selectors == null) return const [];
    return selectors.toList();
  }
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
