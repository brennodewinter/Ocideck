// Part of the tabs_provider library — see tabs_provider.dart.
// De aanmaak van een nieuw document: de extension-methode en de
// schijfhelpers erachter, in een part-bestand zodat tabs_provider.dart onder
// de bestandsgrens blijft; de top-level helpers tellen bovendien niet mee
// voor het klasseplafond van TabsNotifier.

part of 'tabs_provider.dart';

/// De aanmaakkant van de documentmodus — spiegel van `newDeckInNewTab`.
extension TabsNotifierNewDocument on TabsNotifier {
  /// Maak een nieuw, leeg document in een nieuw tabblad.
  ///
  /// [filePath] is de plek die de gebruiker in de aanmaakdialoog koos (#2177):
  /// het bestand staat dan meteen op schijf — met de gekozen naam en map —
  /// zodat het een echte naam en herkomst heeft, en de eerste Cmd/Ctrl+S
  /// in-place opslaat in plaats van 'Opslaan als…' te vragen. `null` (web, of
  /// "Nog niet opslaan" in de dialoog) geeft een naamloos tabblad in het
  /// geheugen; de eerste opslaan kiest dan alsnog een pad.
  ///
  /// Levert `false` wanneer het bestand niet aangemaakt kon worden — een
  /// naamconflict of een schijffout. Er komt dan óók geen tabblad, zodat de
  /// aanroeper de mislukking kan melden in plaats van stil op een naamloos
  /// tabblad uit te komen.
  Future<bool> newDocument({String? filePath}) async {
    if (filePath == null || !supportsLocalProjectFolders) {
      _placeDocumentTab(MarkdownDocument.parse(''));
      return true;
    }
    if (!await _createDocumentFileAt(filePath)) return false;
    if (!mounted) {
      await _deleteOrphanedDocumentFile(filePath);
      return false;
    }
    _placeDocumentTab(MarkdownDocument.parse(''), filePath: filePath);
    await _settings.addRecentFile(filePath, kind: MarkdownKind.document);
    return true;
  }
}

/// Maakt [filePath] aan als leeg bestand voor [TabsNotifier.newDocument] —
/// het pad dat de gebruiker in de aanmaakdialoog koos (#2177). De naam wordt
/// atomisch geclaimd via `File.create(exclusive: true)` (O_EXCL): bestaat
/// het pad al, dan wordt het nooit stilletjes overschreven — een schrijfbeurt
/// over een bestaand bestand heen is dataverlies, en dat is precies de hoek
/// die OciDeck nergens mag snijden. De dialoog meldt een naamconflict al
/// vooraf; dit is de harde grens erachter voor de race met een tweede venster
/// of een proces dat er net vóór ons was.
///
/// Levert `false` bij een conflict én bij elke andere schrijffout (de
/// aanroeper meldt dat aan de gebruiker; er komt dan ook geen tabblad). Een
/// leeg document is 0 bytes op schijf en `MarkdownDocument.parse('').source`
/// is `''`, dus `create` volstaat — geen aparte `saveDocument`-schrijving
/// nodig. `loadDocument(filePath: path)` zet het tabblad daarna schoon met
/// een overeenkomende `savedFileHash`.
Future<bool> _createDocumentFileAt(String filePath) async {
  try {
    await Directory(p.dirname(filePath)).create(recursive: true);
    await File(filePath).create(exclusive: true);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Ruimt het zojuist aangemaakte lege bestand weer op wanneer de notifier
/// ondertussen is afgebroken — anders blijft een wees van 0 bytes op schijf
/// staan. Best effort: faalt ook dat, dan blijft een leeg bestand staan.
Future<void> _deleteOrphanedDocumentFile(String filePath) async {
  try {
    await File(filePath).delete();
  } on FileSystemException {
    // Opruim-mislukking is onschadelijk — het bestand is 0 bytes.
  }
}
