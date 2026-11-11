// Part of the file_service library — see ../file_service.dart.
// Split out for navigability: de sidecar-poort (capped lezen, fail-closed
// schrijven) naast een <naam>.md. Alle imports leven in de hoofdlibrary.
part of '../file_service.dart';

// ── De sidecar-poort ────────────────────────────────────────────────────────
//
// Buiten de klasse, en niet alleen om de klassenratchet: deze twee raken geen
// enkel veld van FileService. Ze gaan over één bestand op schijf, en dat is de
// hele reden dat ze los te lezen zijn.

/// De tekst van [sidecar], of null zodra hij groter is dan
/// [FileService.maxDeckSidecarBytes].
///
/// Dezelfde herkomst als een deck of grafiekdata: een sidecar komt uit een
/// pakket, een repo of iemands map, en werd hier onbegrensd ingelezen — met de
/// tweede kopie die `jsonDecode` er meteen bovenop legt. [laag] noemt de laag
/// in de logregel, want stil overslaan leest als "er stond niets in".
Future<String?> _readSidecarCapped(
  File sidecar,
  String laag, [
  List<String>? skipped,
]) async {
  try {
    final length = await sidecar.length();
    if (length > FileService.maxDeckSidecarBytes) {
      logWarning(
        'FileService: $laag sidecar of $length bytes exceeds the '
        '${FileService.maxDeckSidecarBytes ~/ (1024 * 1024)} MiB cap and was '
        'not read',
        sidecar.path,
      );
      // De gebruiker hoort dit ook te zien, niet alleen het logbestand: zijn
      // strepen zijn er niet, en zonder melding leest dat als "ik heb nooit
      // getekend" in plaats van "deze laag is overgeslagen" (#564).
      skipped?.add(laag);
      return null;
    }
    return await sidecar.readAsString();
  } on FileSystemException catch (e) {
    // Onleesbaar gedraagt zich als "geen laag": bij het openen slaat de
    // gebruiker hem over met een melding, bij het opslaan telt null als
    // "onbespreekbaar" en blijft het bestand staan (zie _sidecarUntouchable).
    logWarning('FileService: $laag sidecar niet leesbaar', e);
    skipped?.add(laag);
    return null;
  }
}

// ── De sidecars naast een `<naam>.md` ────────────────────────────────────────
//
// Vijf bestanden, één vorm: bepaal het pad, laat een sidecar van een nieuwere
// build met rust, en schrijf of verwijder. Dat stond vijf keer uitgeschreven —
// twintig regels boilerplate per sidecar, met de kans om er bij de zesde één
// stap van te vergeten. De stap die je niet mag vergeten is de middelste: half
// inlezen en terugschrijven wist wat deze build niet begreep.
//
// Top-level en niet in `FileService`: geen van deze functies raakt een veld van
// die klasse aan. Ze stonden daar alleen omdat ze bij het opslaan horen.

/// Schrijft de sidecar met achtervoegsel [extension] naast [mdPath], of
/// verwijdert hem wanneer [encode] niets oplevert — dan hoort er ook geen
/// bestand te liggen.
///
/// Draagt het bestand op schijf een hogere versie dan [supportedVersion], dan
/// gebeurt er niets: niet lezen én niet overschrijven (`sidecar_format.dart`).
Future<void> _writeSidecarNextTo(
  String mdPath,
  String extension,
  int supportedVersion,
  String label,
  String? Function() encode,
) async {
  final sidecar = File(p.setExtension(mdPath, extension));
  if (await _sidecarUntouchable(sidecar, supportedVersion, label)) return;
  final json = encode();
  if (json == null) {
    // Opruimen mag de eigenlijke opslag niet blokkeren: een sidecar die we
    // niet kunnen peilen raken we sowieso niet aan (fail closed — een
    // delete op een onzeker bestand is erger dan een achtergebleven sidecar).
    try {
      if (await sidecar.exists()) await sidecar.delete();
    } on FileSystemException catch (e) {
      logWarning('FileService: $label sidecar niet opgeruimd', e);
    }
  } else {
    await writeStringAtomicIfChanged(sidecar, json);
  }
}

/// Pad van de annotatie-sidecar naast een deck `<naam>.md`.
String _sidecarPath(String mdPath) => p.setExtension(mdPath, '.ink.json');

Future<void> _writeSidecar(Deck deck, String filePath) => _writeSidecarNextTo(
  filePath,
  '.ink.json',
  AnnotationCodec.version,
  'ink',
  () => AnnotationCodec.encode(deck.slides, deck.annotations),
);

/// Pad van de gebruikersnotities-sidecar.
String _userNotesSidecarPath(String mdPath) =>
    p.setExtension(mdPath, '.user-notes.json');

Future<void> _writeUserNotesSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.user-notes.json',
      UserNotesCodec.version,
      'user-notes',
      () => UserNotesCodec.encode(deck.slides, deck.userNotes),
    );

/// Pad van de MIAUW-dispositie-sidecar.
String _miauwSidecarPath(String mdPath) =>
    p.setExtension(mdPath, '.miauw.json');

Future<void> _writeMiauwSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.miauw.json',
      MiauwCodec.version,
      'MIAUW',
      () => MiauwCodec.encodeDisposition(deck.miauw),
    );

/// Pad van de sidecar met terzijdegelegde privacybevindingen (§6.7, #651).
String _dismissalsSidecarPath(String mdPath) =>
    p.setExtension(mdPath, '.dismissals.json');

Future<void> _writeDismissalsSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.dismissals.json',
      DismissalCodec.version,
      'dismissals',
      () {
        final value = deck.dismissals;
        return value == null ? null : DismissalCodec.encode(value);
      },
    );

/// Pad van de zegel-sidecar.
String _sealSidecarPath(String mdPath) => p.setExtension(mdPath, '.seal.json');

Future<void> _writeSealSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.seal.json',
      SealCodec.version,
      'seal',
      () => SealCodec.encode(SealRecord.of(deck)),
    );

/// Of de sidecar op [sidecar] bij het opslaan met rust gelaten moet worden,
/// inclusief het niet-verwijderen. [laag] noemt de laag in de logregel.
///
/// Twee aanleidingen, één uitkomst. Hij komt uit een nieuwere OciDeck dan deze
/// build ([supported]) — de leeskant laadt zo'n bestand al niet in (zie de
/// codecs). Of hij is te groot om te lezen. In beide gevallen draagt het deck
/// de inhoud niet in het geheugen, en dan wist de eerstvolgende opslag het
/// bestand: niets laden en toch overschrijven is erger dan half lezen.
Future<bool> _sidecarUntouchable(
  File sidecar,
  int supported,
  String laag,
) async {
  try {
    if (!await sidecar.exists()) return false;
  } on FileSystemException catch (e) {
    // Kunnen we niet vaststellen of er iets ligt, dan raken we er zeker
    // niets aan — overschrijven van iets onleesbaars is de ergste uitkomst.
    logWarning('FileService: $laag sidecar niet te peilen', e);
    return true;
  }
  try {
    final raw = await _readSidecarCapped(sidecar, laag);
    // De cap-reden staat al in het log van _readSidecarCapped.
    if (raw == null) return true;
    if (!sidecarIsFromNewerBuild(raw, supported)) return false;
    logWarning(
      'FileService: $laag sidecar is from a newer OciDeck and was left '
      'untouched',
      sidecar.path,
    );
    return true;
  } catch (e) {
    // Onleesbaar is niet "van later": dat valt onder gewone corruptie.
    logWarning('FileService: sidecar version unreadable', e);
    return false;
  }
}
