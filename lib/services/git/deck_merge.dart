import '../../models/annotation.dart';
import '../../models/deck.dart';
import '../../models/slide.dart';
import '../annotation_codec.dart';
import '../slide_dedup_service.dart';
import '../user_notes_codec.dart';
import 'version_diff.dart';

/// Hoe veel twee slides op elkaar moeten lijken om ze bij een merge als *dezelfde*
/// slide te tellen. Bewust losser dan de drempel van [diffDeckVersions] (die een
/// leesbare vergelijking wil), want de twee gaan verschillend fout op:
///
/// - te gretig koppelen kost de gebruiker één keuze — hij krijgt een conflict
///   voorgelegd dat er misschien geen was;
/// - te terughoudend koppelen laat één herschreven slide stil uiteenvallen in
///   "allebei weggegooid, en hier zijn twee nieuwe" — géén conflictmelding, en
///   een deck met een dubbele slide.
///
/// De eerste fout is zichtbaar en herstelbaar, de tweede sluipend. Dus liever
/// een conflict te veel.
const double _mergePairingThreshold = 0.3;

/// Eén slide waar beide kanten iets anders mee deden — het enige wat OciDeck
/// niet zelf kan beslissen (§8.6).
class SlideConflict {
  /// Waar de slide in de gemeenschappelijke voorouder stond.
  final int baseIndex;
  final Slide base;

  /// Onze kant en die van de ander; `null` betekent "deze kant verwijderde hem".
  final Slide? ours;
  final Slide? theirs;

  /// Waar de voorlopige keuze in [DeckMergeResult.merged] staat, of null wanneer
  /// beide kanten hem weggooiden. Hiermee kan de UI de andere kant er zó
  /// inwisselen zonder de merge over te doen.
  final int? mergedIndex;

  const SlideConflict({
    required this.baseIndex,
    required this.base,
    required this.ours,
    required this.theirs,
    this.mergedIndex,
  });

  SlideConflict _at(int? index) => SlideConflict(
    baseIndex: baseIndex,
    base: base,
    ours: ours,
    theirs: theirs,
    mergedIndex: index,
  );

  /// Of het een verwijder-tegen-wijzig-botsing is: die leest anders dan twee
  /// concurrerende bewerkingen, want er is geen "beide versies" om te tonen.
  bool get isDeleteAgainstEdit => ours == null || theirs == null;
}

/// De uitkomst van een driewegs-merge van één deck.
class DeckMergeResult {
  /// Het samengevoegde deck. Bij een conflict staat voorlopig ónze kant erin —
  /// nooit stilletjes die van de ander — zodat er altijd iets toonbaars is;
  /// [conflicts] vertelt waar de gebruiker nog moet kiezen.
  final Deck merged;

  final List<SlideConflict> conflicts;

  const DeckMergeResult(this.merged, this.conflicts);

  bool get isClean => conflicts.isEmpty;
}

/// Voeg twee bewerkingen van hetzelfde deck samen ten opzichte van hun
/// gemeenschappelijke voorouder [base] (§8.6).
///
/// **Waarom op slide-niveau en niet als tekst.** Git zou `deck.md` driewegs
/// samenvoegen en bij een botsing conflictmarkers achterlaten. Dat kan hier
/// niet: een `deck.md` met markers parseert niet meer, en een deck dat niet
/// parseert kan de app niet tónen — precies op het moment dat de gebruiker moet
/// kiezen zou hij niets zien. Een slide is bovendien de eenheid waarin hij
/// denkt. Dus koppelen we slides (dezelfde tweeslags-alignment als
/// [diffDeckVersions]) en botsen we per slide.
///
/// De volgorde van **onze** kant is de ruggengraat: dat is de indeling die de
/// gebruiker voor zich ziet. Slides die alleen de ander toevoegde komen
/// erachteraan; een slide die wij weggooiden maar de ander bewerkte komt terug
/// als conflict, niet als stille verwijdering.
DeckMergeResult mergeDeckVersions(
  Deck base,
  Deck ours,
  Deck theirs, {
  SlideDedupService? dedup,
  double editedThreshold = _mergePairingThreshold,
}) {
  final service = dedup ?? SlideDedupService();
  final ourDiff = diffDeckVersions(
    base,
    ours,
    dedup: service,
    editedThreshold: editedThreshold,
  );
  final theirDiff = diffDeckVersions(
    base,
    theirs,
    dedup: service,
    editedThreshold: editedThreshold,
  );

  final ourByBase = _byBaseIndex(ourDiff);
  final theirByBase = _byBaseIndex(theirDiff);

  final conflicts = <SlideConflict>[];
  // Per base-slide: wat wordt het? null = weg. Ontbreekt = onaangeroerd.
  final resolved = <int, Slide?>{};

  for (var i = 0; i < base.slides.length; i++) {
    final o = ourByBase[i];
    final t = theirByBase[i];
    final ourSide = _sideOf(o, base.slides[i]);
    final theirSide = _sideOf(t, base.slides[i]);

    if (!ourSide.changed && !theirSide.changed) {
      resolved[i] = base.slides[i];
      continue;
    }
    if (ourSide.changed && !theirSide.changed) {
      resolved[i] = ourSide.slide;
      continue;
    }
    if (!ourSide.changed && theirSide.changed) {
      resolved[i] = theirSide.slide;
      continue;
    }

    // Beide kanten deden iets. Hetzelfde? Dan is er niets te kiezen.
    final a = ourSide.slide, b = theirSide.slide;
    if (a == null && b == null) {
      resolved[i] = null; // allebei weggegooid
      continue;
    }
    if (a != null &&
        b != null &&
        service.signatureOf(a) == service.signatureOf(b)) {
      resolved[i] = a;
      continue;
    }
    conflicts.add(
      SlideConflict(baseIndex: i, base: base.slides[i], ours: a, theirs: b),
    );
    // Voorlopig onze kant; bij een verwijdering aan onze kant die van hen, zodat
    // het werk van de ander zichtbaar blijft tot er gekozen is.
    resolved[i] = a ?? b;
  }

  // Bouw op langs ónze volgorde, en onthoud waar elke base-slide belandde zodat
  // een conflict straks ter plekke omgewisseld kan worden.
  final out = <Slide>[];
  final placed = <int>{};
  final landedAt = <int, int>{};
  for (var j = 0; j < ours.slides.length; j++) {
    final baseIndex = _baseIndexOfAfter(ourDiff, j);
    if (baseIndex == null) {
      out.add(ours.slides[j]); // door ons toegevoegd
      continue;
    }
    placed.add(baseIndex);
    final keep = resolved[baseIndex];
    if (keep != null) {
      landedAt[baseIndex] = out.length;
      out.add(keep);
    }
  }
  // Base-slides die wij weggooiden maar die het overleefden (de ander bewerkte
  // ze) horen er alsnog in — anders verdwijnt andermans werk stil.
  for (var i = 0; i < base.slides.length; i++) {
    if (placed.contains(i)) continue;
    final keep = resolved[i];
    if (keep != null) {
      landedAt[i] = out.length;
      out.add(keep);
    }
  }
  // En wat alleen de ander toevoegde.
  for (var j = 0; j < theirs.slides.length; j++) {
    if (_baseIndexOfAfter(theirDiff, j) == null) out.add(theirs.slides[j]);
  }

  // Deckniveau: onze metadata wint, met één uitzondering. De classificatie gaat
  // naar de strengste van de twee — anders zou een merge stilletjes andermans
  // TLP-verhoging weggooien, en dat is precies het soort fail-open dat de rest
  // van dit pad juist dichttimmert (§9.4).
  final tlp = effectiveTlp(deckTlp: ours.tlp, slideTlp: theirs.tlp);
  return DeckMergeResult(
    ours.copyWith(
      slides: out,
      tlp: tlp,
      userNotes: _mergedUserNotes(ours, theirs, out),
      annotations: _mergedAnnotations(ours, theirs, out),
    ),
    [for (final c in conflicts) c._at(landedAt[c.baseIndex])],
  );
}

/// De notities van beide kanten, opnieuw verankerd aan de samengevoegde dia's.
///
/// Zonder dit zou `ours.userNotes` letterlijk meekomen — gesleuteld op de id's
/// van *onze* parse, terwijl [out] grotendeels uit dia's van de basis en van de
/// ander bestaat. Die id's worden bij élke parse opnieuw uitgedeeld, dus geen
/// enkele sleutel zou nog een dia aanwijzen. De schrijfkant ziet dan een deck
/// zonder notities, en verwijdert het notitiebestand uit de repo: het meest
/// gewone geval — twee mensen die op verschillende dia's een notitie typen —
/// zou beider werk wissen. Zelfde patroon en zelfde reden als bij het
/// omschakelen naar markdown-modus (`deck_provider_markdown.dart`).
///
/// De ander eerst, wijzelf erover: bij dezelfde dia wint onze tekst, gelijk aan
/// hoe de rest van deze merge onze kant laat voorgaan. Verschillende dia's
/// raken elkaar niet, en dat is de belofte van D7.
Map<String, String> _mergedUserNotes(Deck ours, Deck theirs, List<Slide> out) {
  final merged = <String, String>{
    ..._reanchored(theirs, out),
    ..._reanchored(ours, out),
  };
  return merged;
}

/// De tekeningen van beide kanten, verenigd per streek — D7's union, mét de
/// grafstenen die hem eerlijk houden.
///
/// Dezelfde heranker-stap als bij de notities, en om dezelfde reden: de
/// streeksleutels wijzen naar dia-id's van de eigen parse, en [out] draagt
/// andere. Daarna is de merge géén "onze kant wint" maar een **unie op
/// streek-id**: twee mensen die op één dia tekenden waren het niet oneens, ze
/// tekenden allebei. Onze streken houden hun volgorde, wat alleen de ander
/// heeft komt erachteraan.
///
/// Eén regel beslist bij een dubbel id, en het is de regel waarvoor de
/// grafsteen bestaat: **gewist wint van niet-gewist**, ongeacht de kant. Een
/// wissing die een merge niet overleeft is erger dan een die niet werkt, want
/// de gebruiker zág hem verdwijnen (D7). De grafsteen blijft dus ook in de
/// uitkomst staan — weggooien zou hem bij de vólgende merge weer laten
/// terugkeren van de kant die hem nog draagt.
Map<String, List<InkStroke>> _mergedAnnotations(
  Deck ours,
  Deck theirs,
  List<Slide> out,
) {
  final our = _reanchoredInk(ours, out);
  final their = _reanchoredInk(theirs, out);
  final merged = <String, List<InkStroke>>{};
  for (final key in {...our.keys, ...their.keys}) {
    final byId = <String, InkStroke>{};
    final order = <String>[];
    for (final stroke in [...?our[key], ...?their[key]]) {
      final seen = byId[stroke.id];
      if (seen == null) {
        byId[stroke.id] = stroke;
        order.add(stroke.id);
      } else if (stroke.erased && !seen.erased) {
        byId[stroke.id] = stroke;
      }
    }
    merged[key] = [for (final id in order) byId[id]!];
  }
  return merged;
}

/// [deck]'s tekeningen, gesleuteld op de id's van [out] — via de codec, die op
/// de vingerafdruk van een dia verankert en niet op haar id.
Map<String, List<InkStroke>> _reanchoredInk(Deck deck, List<Slide> out) {
  if (deck.annotations.isEmpty) return const {};
  final encoded = AnnotationCodec.encode(deck.slides, deck.annotations);
  if (encoded == null) return const {};
  return AnnotationCodec.decode(encoded, out);
}

/// [deck]'s notities, gesleuteld op de id's van [out] in plaats van die van
/// [deck] — via de codec, die op de vingerafdruk van een dia verankert en niet
/// op haar id.
Map<String, String> _reanchored(Deck deck, List<Slide> out) {
  if (deck.userNotes.isEmpty) return const {};
  final encoded = UserNotesCodec.encode(deck.slides, deck.userNotes);
  if (encoded == null) return const {};
  return UserNotesCodec.decode(encoded, out);
}

/// De wijziging per base-slide, op index van de voorouder.
Map<int, SlideChange> _byBaseIndex(VersionDiff diff) => {
  for (final c in diff.changes)
    if (c.beforeIndex != null) c.beforeIndex!: c,
};

/// Voor een slide in de nieuwe versie: uit welke base-slide kwam hij, of null
/// wanneer hij nieuw is.
int? _baseIndexOfAfter(VersionDiff diff, int afterIndex) {
  for (final c in diff.changes) {
    if (c.afterIndex == afterIndex) return c.beforeIndex;
  }
  return null;
}

/// Wat één kant met een base-slide deed: veranderde de inhoud, en wat werd het?
({bool changed, Slide? slide}) _sideOf(SlideChange? change, Slide base) {
  // Geen vermelding betekent: deze kant raakte hem niet aan.
  if (change == null) return (changed: false, slide: base);
  switch (change.kind) {
    case SlideChangeKind.removed:
      return (changed: true, slide: null);
    case SlideChangeKind.edited:
      return (changed: true, slide: change.after);
    // Verplaatsen is geen inhoudswijziging: het botst niet met een bewerking.
    case SlideChangeKind.moved:
    case SlideChangeKind.unchanged:
      return (changed: false, slide: change.after ?? base);
    case SlideChangeKind.added:
      return (changed: false, slide: base);
  }
}
