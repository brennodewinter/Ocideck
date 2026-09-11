// Part of the tabs_provider library — see tabs_provider.dart.
// De schijfaanmaak achter newDocument(), top-level gehouden zodat het niet
// meetelt voor het klasseplafond van TabsNotifier en tabs_provider.dart onder
// de bestandsgrens blijft. Raakt geen TabsNotifier-veld — alleen de
// instellingen die worden doorgegeven.

part of 'tabs_provider.dart';

/// Maakt meteen een leeg `document.md` (of `document 2.md`, …) aan in de
/// ingestelde thuismap (de eerste bibliotheek) en geeft het pad terug, of
/// `null` als er geen bibliotheek is ingesteld of de map onbereikbaar blijkt.
/// De aanroeper valt dan terug op een naamloos tabblad.
///
/// De naam wordt atomisch geclaimd via `File.create(exclusive: true)`
/// (O_EXCL): twee vensters of een reeds bestaand bestand overschrijven
/// nooit stilletjes elkaars werk — een schrijfbeurt over een bestaand
/// bestand heen is dataverlies, en dat is precies de hoek die OciDeck
/// nergens mag snijden. De bestandsnaam volgt de actieve interfacetaal via
/// [AppLocalizations.active.d]; 'document' is al vertaald in elke taal
/// (zie `unchangedInEnglish` in app_localizations_test).
///
/// Een leeg document is 0 bytes op schijf, en `MarkdownDocument.parse('').source`
/// is `''`, dus `create(exclusive: true)` volstaat — geen aparte
/// `saveDocument`-schrijving nodig. `loadDocument(filePath: path)` zet het
/// tabblad daarna schoon met een overeenkomende `savedFileHash`.
Future<String?> _createNewDocumentFile(AppSettings settings) async {
  final home = settings.homeDirectory;
  if (home == null || home.isEmpty) return null;
  try {
    await Directory(home).create(recursive: true);
  } on FileSystemException catch (e) {
    logWarning(
      'newDocument: thuismap onbereikbaar, terugval op naamloos tabblad',
      e,
    );
    return null;
  }
  final base = AppLocalizations.active.d('document');
  for (var n = 1; ; n++) {
    final name = n == 1 ? '$base.md' : '$base $n.md';
    final path = p.join(home, name);
    try {
      await File(path).create(exclusive: true);
      return path;
    } on FileSystemException {
      // Bestaat de naam al, dan proberen we de volgende. Een echte fout
      // (vol volume) is hier géén naamconflict: geef null terug, zodat de
      // aanroeper terugvalt op een naamloos tabblad.
      if (!await File(path).exists()) return null;
    }
  }
}
