import '../models/slide.dart';
import '../services/bullet_pagination.dart';
import '../services/slide_layout_metrics.dart'
    show bulletsImageTextColumnFraction;
import '../services/slide_quality_analyzer.dart'
    show
        kChecklistBulletWarningCount,
        kSingleColumnBulletWarningCount,
        kTwoColumnBulletWarningCount;

/// Deterministische quick-fix voor de kwaliteitsmelding "bullet met meerdere
/// zinnen": knip elke meerzinnige bullet op zinsgrenzen in losse bullets op
/// hetzelfde inspring-niveau. Checklist-items behouden hun aangevinkt-status.
///
/// De zinsgrens-definitie spiegelt de detectie in de kwaliteitsanalyse
/// (interpunctie gevolgd door witruimte of einde), zodat de fix precies
/// oplost wat de melding signaleert.
final _sentenceEnd = RegExp(r'[.!?](?:\s+|$)');
final _checklistPrefix = RegExp(r'^\[[ xX]\]\s*');

/// Een naar de sprekersnotities verplaatste bulletregel: op zijn inspring-
/// niveau en met een streepje ervoor (#913), zodat de spreker in de notities
/// een opsomming ziet in plaats van een vlakke tekstregel. Tussenkoppen krijgen
/// géén streepje — die zijn de context waaronder de punten vallen, geen punt.
String _movedNoteLine(int level, String text) => '${'\t' * level}- $text';

/// Of [slide] bullets heeft die [splitSentencesInBullets] daadwerkelijk zou
/// opknippen — zodat de UI de actie alleen aanbiedt als die iets doet — én de
/// slide daar niet te vol van wordt.
///
/// Die tweede eis maakt het verschil tussen een hulpmiddel en een rommeltje:
/// opknippen levert méér bullets op, dus op een slide die de leesbaarheids-
/// drempel al raakt maakt deze fix het probleem groter. Daar hoort maar één
/// vervolgstap te staan — "Splits slide" — zodat de auteur per melding één
/// scenario voor zich heeft in plaats van twee acties die elkaar tegenwerken.
bool canSplitSentenceBullets(Slide slide) {
  if (!slide.bullets.any(_isMultiSentence) &&
      !slide.bullets2.any(_isMultiSentence)) {
    return false;
  }
  final after =
      _visibleBulletCount(splitSentencesInBullets(slide.bullets)) +
      _visibleBulletCount(splitSentencesInBullets(slide.bullets2));
  return after <= _bulletWarningCount(slide);
}

/// De drempel die de kwaliteitsanalyse voor deze slide aanhoudt; hier
/// gespiegeld zodat de actie precies verdwijnt wanneer de dichtheidsmelding
/// die het probleem al beschrijft de leiding neemt.
int _bulletWarningCount(Slide slide) => slide.type == SlideType.twoBullets
    ? kTwoColumnBulletWarningCount
    : (slide.listStyle == ListStyle.checklist
          ? kChecklistBulletWarningCount
          : kSingleColumnBulletWarningCount);

/// Tussenkoppen zijn secties, geen inhoudelijke bullets: ze tellen bij de
/// analyse niet mee en hier dus ook niet.
int _visibleBulletCount(List<String> bullets) =>
    bullets.where((b) => b.trimLeft().isNotEmpty && !isGroupHeading(b)).length;

/// De bovengrens waaronder 'Uitleg naar notities' als vervolgstap verschijnt
/// (#912). Bóven deze grens telt de dia als 'te veel bullets', en dan is
/// splitsen de enige aangeboden remedie: uitleg naar de notities halen verandert
/// het aantal bullets niet, dus lost 'te vol' niet op. Gelijk aan de enkelkoloms
/// waarschuwingsdrempel — precies de grens waarboven 'te veel bullets' geldt.
const int kMoveToNotesMaxBulletCount = kSingleColumnBulletWarningCount;

/// Het aantal zichtbare inhouds-bullets op [slide], over beide kolommen en
/// zonder de tussenkoppen (die zijn secties, geen punten). Dezelfde telling die
/// de gate van 'Uitleg naar notities' tegen [kMoveToNotesMaxBulletCount] legt.
int visibleContentBulletCount(Slide slide) =>
    _visibleBulletCount(slide.bullets) + _visibleBulletCount(slide.bullets2);

/// Of [slide] genoeg zichtbare bullets heeft om te splitsen in twee volwaardige
/// pagina's — samen minstens tweemaal [kMinPageBullets], zodat elke helft een
/// echte pagina blijft in plaats van een flinter van één of twee bullets.
///
/// Bedoeld voor een dia die te klein *rendert* doordat zijn bullets lang zijn:
/// dan ligt het bulletaantal onder de leesbaarheidsdrempel (het zijn er weinig,
/// maar wél lange), en toch vergroot splitsen de tekst omdat elke pagina minder
/// bullets draagt. De aantal-drempel is daar de verkeerde maat; deze grens —
/// "is er genoeg om over pagina's te verdelen" — is de juiste.
bool hasBulletsForFontEnlargingSplit(Slide slide) =>
    visibleContentBulletCount(slide) >= 2 * kMinPageBullets;

/// De pagina's waarin "Splits slide" [slide] verdeelt — pagina's van hooguit de
/// leesbaarheidsdrempel (acht bullets, twaalf voor een checklist, zeven per
/// kolom; naast een afbeelding naar rato van de smallere tekstkolom), met de
/// rest op een laatste, kortere pagina. `null` als splitsen niet kan (geen
/// bullettype, of te weinig bullets).
///
/// De eerste pagina erft type/afbeelding en de continuesSplit-vlag van [slide]
/// (want [Slide.duplicate] kopieert imagePath/-caption/-size); elke vervolgpagina
/// is een continuation die de fontgrootte deelt.
///
/// Gedeeld door [DeckNotifier.splitSlide], de fix-alles-motor en de live-fix in
/// de presenter, zodat "splitsen" overal exact hetzelfde doet. Het aantal
/// bulletkolommen komt uit de registry naast de enum ([SlideTypeMeta.bulletColumns]),
/// zodat een nieuw bullettype hier vanzelf splitsbaar wordt.
List<Slide>? splitBulletSlidePages(Slide slide) {
  List<Slide> build(List<(List<String>, List<String>)> pages) => [
    for (var i = 0; i < pages.length; i++)
      (i == 0 ? slide : Slide.duplicate(slide)).copyWith(
        bullets: pages[i].$1,
        bullets2: pages[i].$2,
        continuesSplit: i == 0 ? slide.continuesSplit : true,
      ),
  ];
  switch (slide.type.bulletColumns) {
    case BulletColumns.none:
      return null;
    case BulletColumns.one:
      if (slide.bullets.length < 2) return null;
      // Checklists houden hun ruimere optimum aan (consistent met de
      // waarschuwingsdrempel), zodat een lijst van 12 niet onnodig krimpt.
      final base = slide.listStyle == ListStyle.checklist
          ? kChecklistBulletWarningCount
          : kSingleColumnBulletWarningCount;
      // Naast een afbeelding is de tekstkolom smal: hetzelfde aantal bullets
      // dat op volle breedte comfortabel leest, drukt daar de gedeelde
      // run-schaal omlaag en laat de deel-slides klein renderen (#1279).
      // Schaal het paginadoel mee met de kolombreedte, zodat de splitsing
      // pagina's oplevert die de vrijgekomen ruimte ook werkelijk vullen.
      final size = slide.type == SlideType.bulletsImage
          ? (base * bulletsImageTextColumnFraction(slide)).round().clamp(
              kMinPageBullets,
              base,
            )
          : base;
      return build([
        for (final p in splitBulletsIntoPages(slide.bullets, size))
          (p, const <String>[]),
      ]);
    case BulletColumns.two:
      if (slide.bullets.length < 2 && slide.bullets2.length < 2) return null;
      const perColumn = kTwoColumnBulletWarningCount ~/ 2;
      return build(
        splitTwoColumnsIntoPages(slide.bullets, slide.bullets2, perColumn),
      );
  }
}

bool _isMultiSentence(String bullet) =>
    _splitSentences(_plainText(bullet)).length > 1;

String _plainText(String bullet) =>
    bulletText(bullet).replaceFirst(_checklistPrefix, '');

/// Nieuwe slide waarin elke meerzinnige bullet is opgeknipt in één bullet per
/// zin. Bullets met hooguit één zin blijven ongemoeid.
///
/// De regel zoals hij was gaat naar de sprekersnotities. Op de slide staan
/// straks losse zinnen — prima om te lezen, maar het verband tussen die zinnen
/// zat juist in de volzin die je zojuist uit elkaar trok. Zonder die kopie
/// bewaart de slide de woorden en verliest de spreker het verhaal.
Slide splitSentenceBullets(Slide slide) {
  final moved = <String>[];
  final bullets = _splitColumn(slide.bullets, moved);
  final bullets2 = _splitColumn(slide.bullets2, moved);
  if (moved.isEmpty) return slide;

  final existing = slide.notes.trimRight();
  final notes = [if (existing.isNotEmpty) existing, ...moved].join('\n');
  return slide.copyWith(bullets: bullets, bullets2: bullets2, notes: notes);
}

/// Knip elke meerzinnige bullet in [bullets] op in losse bullets; volgorde en
/// inspring-niveau blijven behouden.
List<String> splitSentencesInBullets(List<String> bullets) =>
    _splitColumn(bullets, <String>[]);

/// Verwerkt één kolom en legt van elke opgeknipte regel de oorspronkelijke,
/// hele tekst in [moved] — met dezelfde context als [trimBulletExplanations]
/// meegeeft: de tussenkop waaronder de regel stond (eenmaal, boven de eerste
/// regel die eronder valt) en het inspring-niveau.
List<String> _splitColumn(List<String> bullets, List<String> moved) {
  final result = <String>[];
  String? heading; // de tussenkop waaronder we nu lopen
  var headingMoved = false;
  for (final bullet in bullets) {
    // A group heading is a section label, never a multi-sentence bullet to
    // split — keep it verbatim.
    if (isGroupHeading(bullet)) {
      heading = groupHeadingText(bullet);
      headingMoved = false;
      result.add(bullet);
      continue;
    }
    if (!_isMultiSentence(bullet)) {
      result.add(bullet);
      continue;
    }
    final level = bulletLevel(bullet);
    final isChecklist = _checklistPrefix.hasMatch(bulletText(bullet));
    final checked = isChecklist && checklistItemChecked(bullet);
    final plain = _plainText(bullet);
    for (final sentence in _splitSentences(plain)) {
      result.add(
        isChecklist
            ? checklistBullet(level: level, text: sentence, checked: checked)
            : '${'\t' * level}$sentence',
      );
    }
    // Een naamloze kop is een scheidingsstreep, geen context om te melden.
    if (heading != null && heading.isNotEmpty && !headingMoved) {
      moved.add(heading);
      headingMoved = true;
    }
    moved.add(_movedNoteLine(level, plain));
  }
  return result;
}

List<String> _splitSentences(String text) {
  final parts = <String>[];
  var start = 0;
  for (final match in _sentenceEnd.allMatches(text)) {
    // Inclusief het leesteken zelf, exclusief de witruimte erna.
    parts.add(text.substring(start, match.start + 1).trim());
    start = match.end;
  }
  if (start < text.length) {
    final rest = text.substring(start).trim();
    if (rest.isNotEmpty) parts.add(rest);
  }
  return [
    for (final part in parts)
      if (part.isNotEmpty) part,
  ];
}

/// Quick-fix voor een overvolle bullet: haal de uitleg van de slide en laat
/// alleen het label staan. De uitleg verdwijnt niet — ze verhuist naar de
/// sprekersnotities, zodat de spreker haar nog kan uitspreken en de bewerking
/// met één undo terug te draaien is.
///
/// Dit vult de twee bestaande dichtheidsfixes aan: "Splits slide" verdeelt
/// bullets over pagina's en "Zinnen naar losse bullets" knipt ze op — beide
/// houden álle tekst op de slide staan (de tweede legt er een kopie van in de
/// notities naast). Deze haalt tekst wég, voor het geval dat de enige echte
/// oplossing is.

/// Scheidingstekens tussen een label en zijn uitleg, in de vorm die mensen
/// intuïtief gebruiken: "Term: uitleg", "Item - uitleg", of een eerste zin
/// gevolgd door de rest. De dubbele punt en het koppelstreepje eisen witruimte
/// eromheen zodat `https://…` en `e-mail` er niet in lopen; de punt eist
/// witruimte erna zodat `1.2` en `nr.3` heel blijven.
final _labelColon = RegExp(r':\s');
final _labelDash = RegExp(r'\s[-–—]\s');
final _labelPeriod = RegExp(r'\.(?:\s+|$)');

/// Het minimum aantal woorden dat de uitleg moet tellen om het schrappen zinvol
/// te maken. Anders zou "Q3: klaar" tot "Q3" verschrompelen — dat lost niets op.
const int _minExplanationWords = 2;

/// Het label voor een bullet die géén scheidingsteken heeft: gewoon de eerste
/// zoveel woorden. Een volzin als bullet ("Wij hebben besloten de infrastructuur
/// te migreren omdat dat goedkoper is") is precies de regel die van de slide af
/// moet, en juist die had geen dubbele punt om op te knippen — dan bleef de fix
/// weg waar hij het hardst nodig was. Vijf woorden is genoeg voor een kop die te
/// herkennen is en kort genoeg om een slide mee op te schonen; dat het soms als
/// een afgekapte zin leest, is de prijs. De hele regel gaat naar de notities,
/// dus er raakt niets zoek en de auteur kan het label bijschaven.
const int _proseLabelWords = 5;

/// Of [slide] bullets heeft waarvan [trimBulletExplanations] de uitleg zou
/// verplaatsen — zodat de UI de actie alleen aanbiedt als die iets doet.
bool canTrimBulletExplanations(Slide slide) =>
    slide.bullets.any(_hasTrimmableExplanation) ||
    slide.bullets2.any(_hasTrimmableExplanation);

bool _hasTrimmableExplanation(String bullet) =>
    !isGroupHeading(bullet) &&
    _splitLabelExplanation(_plainText(bullet)) != null;

/// Nieuwe slide waarin de uitleg achter elk "label : uitleg"-bullet naar de
/// sprekersnotities is verplaatst; op de slide blijft alleen het label staan.
Slide trimBulletExplanations(Slide slide) {
  final moved = <String>[];
  final bullets = _trimColumn(slide.bullets, moved);
  final bullets2 = _trimColumn(slide.bullets2, moved);
  if (moved.isEmpty) return slide;

  final existing = slide.notes.trimRight();
  final notes = [if (existing.isNotEmpty) existing, ...moved].join('\n');
  return slide.copyWith(bullets: bullets, bullets2: bullets2, notes: notes);
}

/// Verwerkt één kolom: een trimbare bullet wordt zijn label, en de volledige
/// oorspronkelijke tekst gaat naar [moved], zodat er niets verloren gaat.
///
/// De notities krijgen de regel met zijn context mee: de tussenkop waaronder
/// hij stond (eenmaal, boven de eerste regel die eronder valt) en zijn
/// inspring-niveau. Zonder die twee leest de spreker een vlakke lijst zinnen
/// zonder te weten bij welk deel van de slide ze horen — en dan is de uitleg
/// wel bewaard maar niet meer te plaatsen.
List<String> _trimColumn(List<String> bullets, List<String> moved) {
  final result = <String>[];
  String? heading; // de tussenkop waaronder we nu lopen
  var headingMoved = false;
  for (final bullet in bullets) {
    if (isGroupHeading(bullet)) {
      heading = groupHeadingText(bullet);
      headingMoved = false;
      result.add(bullet);
      continue;
    }
    final plain = _plainText(bullet);
    final split = _splitLabelExplanation(plain);
    if (split == null) {
      result.add(bullet);
      continue;
    }
    final level = bulletLevel(bullet);
    final isChecklist = _checklistPrefix.hasMatch(bulletText(bullet));
    final checked = isChecklist && checklistItemChecked(bullet);
    result.add(
      isChecklist
          ? checklistBullet(level: level, text: split.label, checked: checked)
          : '${'\t' * level}${split.label}',
    );
    // Een naamloze kop is een scheidingsstreep, geen context om te melden.
    if (heading != null && heading.isNotEmpty && !headingMoved) {
      moved.add(heading);
      headingMoved = true;
    }
    moved.add(_movedNoteLine(level, plain));
  }
  return result;
}

/// Splitst een bullet in een label en een substantiële uitleg, of `null` als
/// dat niet zinvol kan. Kiest het vroegste scheidingsteken en eist dat de
/// uitleg minstens [_minExplanationWords] woorden telt. Zonder scheidingsteken
/// valt hij terug op de eerste woorden als label, zie [_splitProse].
({String label, String explanation})? _splitLabelExplanation(String text) {
  var at = -1;
  var length = 0;
  for (final separator in [_labelColon, _labelDash, _labelPeriod]) {
    final match = separator.firstMatch(text);
    if (match == null) continue;
    if (at < 0 || match.start < at) {
      at = match.start;
      length = match.end - match.start;
    }
  }
  if (at < 0) return _splitProse(text);

  final label = text.substring(0, at).trim();
  final explanation = text.substring(at + length).trim();
  if (label.isEmpty || explanation.isEmpty) return null;
  if (_wordCount(explanation) < _minExplanationWords) return null;
  return (label: label, explanation: explanation);
}

/// Een bullet zonder scheidingsteken: de eerste [_proseLabelWords] woorden zijn
/// het label, de rest is de uitleg. Alleen als er ná het label nog een
/// substantiële uitleg overblijft — een bullet van zes woorden is al kort.
({String label, String explanation})? _splitProse(String text) {
  final words = _words(text);
  if (words.length < _proseLabelWords + _minExplanationWords) return null;
  return (
    label: words.take(_proseLabelWords).join(' '),
    explanation: words.skip(_proseLabelWords).join(' '),
  );
}

List<String> _words(String text) =>
    text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

int _wordCount(String text) => _words(text).length;
