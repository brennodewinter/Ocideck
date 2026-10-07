// Part of the deck_provider library — see deck_provider.dart.
//
// De lokale-conflicttoestand van een open deck (#1951, #2323): de exacte
// basisversie van de laatste open- of opslagbeurt, de schijf-vingerafdruk
// waarmee externe wijziging wordt opgemerkt, herladen vanaf schijf, en het
// toepassen van een samengevoegde versie als één ongedaan-stap. Eigen
// klasse omdat dit één concern is met meerdere aanraakpunten in de
// notifier — en de notifier zelf over haar omvangplafond kwam.
part of 'deck_provider.dart';

/// De lokale-conflicttoestand van [DeckNotifier]: alles wat met
/// schijfverandering-buiten-de-app te maken heeft op één plek.
class DeckLocalMerge {
  final DeckNotifier _n;

  DeckLocalMerge(this._n);

  /// Het deck zoals het bij de laatste geslaagde open- of opslagbeurt op
  /// schijf stond — de gemeenschappelijke voorouder voor de driewegs-merge
  /// (#2323). Null bij een padloos of vuil-hersteld tabblad: dan is er geen
  /// aantoonbare basis en biedt de conflictdialoog geen samenvoeging aan.
  Deck? base;

  /// #1951: het tijdstip waarop het bestand op schijf voor het laatst is
  /// gewijzigd, zoals gezien bij openen of de laatste opslag. De schil
  /// vergelijkt dit met de huidige mtime vóór opslaan — wijkt die af, dan
  /// heeft een ander venster of programma het bestand ondertussen
  /// geschreven.
  DateTime? _fileMtime;

  /// Of het bestand op schijf sinds openen/opslaan is gewijzigd of
  /// verwijderd.
  Future<bool> fileChangedExternally() async {
    final path = _n.currentState.filePath;
    if (path == null) return false;
    return _n._file.fileChangedSince(path, _fileMtime);
  }

  /// Lees de mtime van het huidige bestand en onthoud hem. Aangeroepen na
  /// openen en na opslaan, zodat de volgende opslaan-controle een verse
  /// vergelijking heeft.
  Future<void> recordMtime() async {
    final path = _n.currentState.filePath;
    _fileMtime = path == null ? null : await _n._file.fileMtime(path);
  }

  /// Geen gekende schijfstand meer: een nieuw of gesloten deck.
  void clear() {
    base = null;
    _fileMtime = null;
  }

  /// #1951: herlaad het bestand vanaf schijf; de huidige wijzigingen gaan
  /// verloren. Geeft true terug als het herladen is gelukt. Gebruikt door
  /// de conflict-dialoog ("Herladen") wanneer een ander venster het bestand
  /// ondertussen heeft geschreven.
  Future<bool> reloadFromDisk() async {
    final path = _n.currentState.filePath;
    if (path == null) return false;
    final deck = await _n._file.openDeck(path);
    if (deck == null) return false;
    _n._clearHistory();
    base = deck;
    _n._replacementState = DeckState(
      deck: deck,
      filePath: path,
      isDirty: false,
    );
    await recordMtime();
    return true;
  }

  /// #2323: zet de samengevoegde conflictoplossing in het open tabblad —
  /// als één ongedaan-maken-stap en zónder op te slaan: het tabblad blijft
  /// vuil, want de merge is nog niet op schijf.
  ///
  /// [expectedMtime] is de vingerafdruk die de analyse van de schijfversie
  /// vastlegde. Klopt hij niet meer, dan is de analyse verlopen en wordt er
  /// niets toegepast — de aanroeper moet opnieuw vergelijken, want een
  /// samenvoeging op een vervallen schijfversie zou nieuwere wijzigingen
  /// stil overschrijven.
  Future<bool> apply(Deck merged, {required DateTime? expectedMtime}) async {
    final path = _n.currentState.filePath;
    if (path == null) return false;
    final now = await _n._file.fileMtime(path);
    if (now != expectedMtime) return false;
    _n._mutate(merged, bumpRevision: true);
    // De schijfversie zit nu ín het tabblad; de opslag die volgt
    // overschrijft bewust en hoeft het conflict niet opnieuw te melden.
    _fileMtime = now;
    return true;
  }
}
