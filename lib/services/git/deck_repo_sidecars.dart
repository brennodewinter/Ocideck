// De sidecars van een deck in een git-repository (§9.1, #541/#651): de
// notities, de tekenlaag en de terzijdegelegde privacybevindingen, elk met
// dezelfde aanraak- en verwijderregels. Afgesplitst van deck_repo_serializer
// toen dat bestand zijn regelplafond raakte; het is één samenhangende laag —
// wat er naast deck.md ligt, wanneer je eraan mag komen, en hoe het terugkomt.
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/seal_record.dart';
import '../../utils/log.dart';
import '../annotation_codec.dart';
import '../miauw_codec.dart';
import '../privacy/dismissal_codec.dart';
import '../seal_codec.dart';
import '../sidecar_format.dart';
import '../user_notes_codec.dart';

/// Naam van de notitie-sidecar binnen een deckmap (§9.1).
///
/// Precies de naam die het deck op schijf ook draagt, zodat wie een deck van
/// een map naar een repo verhuist hetzelfde bestand terugziet en niet hoeft te
/// raden dat `deck.notes` en `<naam>.user-notes.json` hetzelfde zijn. Het
/// ontwerp schetste `deck.notes`; dat was een schets, en de `.json` zegt elk
/// ander werktuig wat het is.
const String userNotesRepoFileName = 'deck.user-notes.json';

/// Bovengrens voor de notitie-sidecar bij het teruglezen uit een repo.
///
/// Dezelfde herkomst als `FileService.maxDeckSidecarBytes`: het bestand komt
/// van buiten en wordt door `jsonDecode` nog eens gekopieerd. Hier lager, want
/// notities zijn tekst en tellen in kilobytes — de 16 MiB op schijf is er voor
/// de inktlaag, die deze weg niet neemt. Een repo waarin dit bestand tientallen
/// megabytes groot is, is geen deck met veel notities maar iets anders.
const int maxRepoUserNotesBytes = 2 * 1024 * 1024; // 2 MiB

/// Naam van de ink-sidecar binnen een deckmap (§9.7) — dezelfde naam als op
/// schijf, om dezelfde reden als bij de notities: wie een deck van een map
/// naar een repo verhuist, ziet hetzelfde bestand terug.
const String inkRepoFileName = 'deck.ink.json';

/// Bovengrens voor de ink-sidecar bij het teruglezen uit een repo — de grens
/// die de tekenlaag op schijf ook al heeft (`FileService.maxDeckSidecarBytes`):
/// streken zijn puntenlijsten en tellen op, anders dan notitietekst.
const int maxRepoInkBytes = 16 * 1024 * 1024; // 16 MiB

/// Naam van de terzijdeleggingen-sidecar binnen een deckmap (#651) — dezelfde
/// achtervoegselvorm als op schijf (`<naam>.dismissals.json`), om dezelfde
/// reden als bij de notities: wie een deck verhuist, herkent het bestand.
///
/// Dat deze sidecar überhaupt de repo in gaat is een besluit, geen gemak: een
/// terzijdelegging is een reviewbesluit over het rapport, en een tweede
/// reviewer moet niet opnieuw langs wat een collega al beoordeeld heeft
/// (FILE_FORMAT §6.7). De inhoud is daarvoor gebouwd — regel-id plus salted
/// commitment, nooit de gevonden waarde zelf.
const String dismissalsRepoFileName = 'deck.dismissals.json';

/// Bovengrens voor de terzijdeleggingen-sidecar: oordelen zijn tekstregels en
/// tellen in kilobytes, net als de notities.
const int maxRepoDismissalsBytes = 2 * 1024 * 1024; // 2 MiB

/// Naam van de MIAUW-dispositie-sidecar binnen een deckmap (#756) — dezelfde
/// achtervoegselvorm als op schijf (`<naam>.miauw.json`). Een waiver of
/// bevestiging is een reviewbesluit over het rapport, net als een
/// terzijdelegging, en reist dus mee; de merge-semantiek (unie per EIS-id,
/// laatste besluit wint, grafstenen overleven) staat in GIT_STORAGE §9.7.
const String miauwRepoFileName = 'deck.miauw.json';

/// Bovengrens voor de dispositie-sidecar: hooguit ~92 EIS-nummers met een
/// motiveringsregel, dus kilobytes — zelfde maat als de terzijdeleggingen.
const int maxRepoMiauwBytes = 2 * 1024 * 1024; // 2 MiB

/// Naam van de zegel-sidecar binnen een deckmap (#541) — dezelfde
/// achtervoegselvorm als op schijf (`<naam>.seal.json`).
///
/// Dat dit bestand meereist is een besluit, geen gemak (D13, herzien
/// 23-07-2026): git is hier een bestandssysteem, geen enforcer. Wat een zegel
/// betékent — afgekaart, niet meer te wijzigen — bewaakt de app zelf, door een
/// verzegeld deck alleen-lezen te maken; de opslag bewaart alleen wat er is.
/// Een verzegeld rapport dat zónder zijn zegel uit de repo terugkomt leest als
/// een rapport dat nooit verzegeld is, en dat is het verlies dat dit bestand
/// voorkomt.
const String sealRepoFileName = 'deck.seal.json';

/// Bovengrens voor de zegel-sidecar: een hash, wat metadata en een
/// RFC 3161-token van enkele kilobytes — zelfde maat als de notities.
const int maxRepoSealBytes = 2 * 1024 * 1024; // 2 MiB

/// Levert de bytes achter een afbeeldingsverwijzing, of null wanneer die niet te
/// lezen is (web zonder mem:-treffer, een pad buiten het project, een leesfout).
/// In de app is dit `ImageService.readSlideImageBytes`; in tests een fake.
typedef AssetByteResolver = Future<Uint8List?> Function(String path);

/// Levert de bytes van één bestand ín de deckmap, of null als het er niet is.
/// De forge leest het als blob, de werkkopie uit haar bestandenmap.
typedef RepoFileReader = Future<Uint8List?> Function(String repoPath);

/// Hang de notities uit `deck.user-notes.json` weer aan [deck] — de omkering
/// van wat [buildDeckRepoFiles] schrijft.
///
/// Geen bestand is de gewone toestand: een deck zonder notities heeft er geen,
/// en een deck dat vóór deze functie bestond gedroeg zich zo. Een bestand dat
/// er wél is maar niet te lezen valt, levert een deck zónder notities op in
/// plaats van een mislukte open — dezelfde ruil als op schijf en bij
/// grafiekdata. Notities zijn een laag over het deck, niet het deck.
///
/// **Maar dan mag de schrijfkant het bestand niet weggooien.** Die bescherming
/// zit in [repoUserNotesState] (de schrijfkant vraagt zelf "mag ik hieraan
/// komen?"); [RepoUserNotes.onleesbaar] is de leeskant van hetzelfde oordeel,
/// voor een aanroeper die wil melden. Op schijf is dat contract al dichtgezet
/// (`_sidecarUntouchable`, zie `sidecar_format.dart`: "half inlezen is het
/// gevaarlijke geval"); hier weegt het zwaarder, want dit bestand is niet van
/// jou alleen. Conflictmarkeringen uit een merge búiten OciDeck zijn geen
/// geldige JSON, en een sidecar van een nieuwere build leest deze build
/// bewust niet — in beide gevallen zou "ik zag geen notities, dus ik verwijder
/// het bestand" andermans werk wissen bij je eerstvolgende opslag.
///
/// Daarom is de vlag ruim: elk bestand dat er ligt maar géén notities opleverde
/// telt als onleesbaar. Dat kost hoogstens een verweesd bestand dat blijft
/// staan; de andere kant kost werk dat niemand terug kan halen.
///
/// [UserNotesCodec.decode] hangt elke notitie terug aan de dia met dezelfde
/// vingerafdruk, dus dit moet ná het parsen van `deck.md` gebeuren: de dia-id's
/// zijn dan pas bekend.
typedef RepoUserNotes = ({Deck deck, bool onleesbaar});

Future<RepoUserNotes> withRepoUserNotes(
  Deck deck, {
  required String deckDir,
  required RepoFileReader read,
}) async {
  Uint8List? bytes;
  try {
    bytes = await read(p.posix.join(deckDir, userNotesRepoFileName));
  } catch (e) {
    // Onbereikbaar is niet hetzelfde als afwezig: een netwerkhapering mag geen
    // verwijdering worden.
    logWarning('withRepoUserNotes: notitiebestand onbereikbaar', e);
    return (deck: deck, onleesbaar: true);
  }
  if (bytes == null || bytes.isEmpty) {
    return (deck: deck, onleesbaar: false);
  }
  if (bytes.length > maxRepoUserNotesBytes) {
    logWarning(
      'withRepoUserNotes: notitiebestand is ${bytes.length} bytes '
      '(grens $maxRepoUserNotesBytes) — niet geladen',
    );
    return (deck: deck, onleesbaar: true);
  }
  final String json;
  try {
    json = utf8.decode(bytes);
  } on FormatException catch (e) {
    logWarning('withRepoUserNotes: notitiebestand is geen geldige UTF-8', e);
    return (deck: deck, onleesbaar: true);
  }
  final notes = UserNotesCodec.decode(json, deck.slides);
  return notes.isEmpty
      ? (deck: deck, onleesbaar: true)
      : (deck: deck.copyWith(userNotes: notes), onleesbaar: false);
}

/// Hang de tekeningen uit `deck.ink.json` weer aan [deck] — hetzelfde contract
/// als [withRepoUserNotes], inclusief de ruime onleesbaar-vlag: elk bestand dat
/// er ligt maar geen streken opleverde telt als onleesbaar. De vlag beschrijft
/// de leeskant; de bescherming van de schrijfkant komt niet hiervandaan maar
/// uit [repoInkState], dat conflictmarkeringen en een nieuwere versie als
/// onaanraakbaar aanmerkt. Streken die nergens meer heranker­en (de dia is weg
/// of herschreven) vallen wél weg — dat is het gedocumenteerde §6.2-gedrag,
/// geen leesfout.
typedef RepoInk = ({Deck deck, bool onleesbaar});

Future<RepoInk> withRepoInk(
  Deck deck, {
  required String deckDir,
  required RepoFileReader read,
}) async {
  Uint8List? bytes;
  try {
    bytes = await read(p.posix.join(deckDir, inkRepoFileName));
  } catch (e) {
    // Onbereikbaar is niet hetzelfde als afwezig: een netwerkhapering mag geen
    // verwijdering worden.
    logWarning('withRepoInk: inkbestand onbereikbaar', e);
    return (deck: deck, onleesbaar: true);
  }
  if (bytes == null || bytes.isEmpty) {
    return (deck: deck, onleesbaar: false);
  }
  if (bytes.length > maxRepoInkBytes) {
    logWarning(
      'withRepoInk: inkbestand is ${bytes.length} bytes '
      '(grens $maxRepoInkBytes) — niet geladen',
    );
    return (deck: deck, onleesbaar: true);
  }
  final String json;
  try {
    json = utf8.decode(bytes);
  } on FormatException catch (e) {
    logWarning('withRepoInk: inkbestand is geen geldige UTF-8', e);
    return (deck: deck, onleesbaar: true);
  }
  final ink = AnnotationCodec.decode(json, deck.slides);
  return ink.isEmpty
      ? (deck: deck, onleesbaar: true)
      : (deck: deck.copyWith(annotations: ink), onleesbaar: false);
}

/// Hang de terzijdeleggingen uit `deck.dismissals.json` weer aan [deck] —
/// zelfde contract als de notities en de ink. Geen herankeren nodig: de
/// identiteit is regel-id + commitment, niet een dia-positie, dus dit hoeft
/// niet eens na het parsen — maar het reist met de andere lagen mee door
/// [withRepoSidecars], zodat er één plek blijft waar een laag vergeten kan
/// worden.
typedef RepoDismissals = ({Deck deck, bool onleesbaar});

Future<RepoDismissals> withRepoDismissals(
  Deck deck, {
  required String deckDir,
  required RepoFileReader read,
}) async {
  Uint8List? bytes;
  try {
    bytes = await read(p.posix.join(deckDir, dismissalsRepoFileName));
  } catch (e) {
    logWarning('withRepoDismissals: terzijdeleggingenbestand onbereikbaar', e);
    return (deck: deck, onleesbaar: true);
  }
  if (bytes == null || bytes.isEmpty) {
    return (deck: deck, onleesbaar: false);
  }
  if (bytes.length > maxRepoDismissalsBytes) {
    logWarning(
      'withRepoDismissals: terzijdeleggingenbestand is ${bytes.length} bytes '
      '(grens $maxRepoDismissalsBytes) — niet geladen',
    );
    return (deck: deck, onleesbaar: true);
  }
  final String json;
  try {
    json = utf8.decode(bytes);
  } on FormatException catch (e) {
    logWarning(
      'withRepoDismissals: terzijdeleggingenbestand is geen geldige UTF-8',
      e,
    );
    return (deck: deck, onleesbaar: true);
  }
  // Het zout uit het bestand wint; de fallback geldt alleen wanneer het
  // bestand er geen draagt, en dan valt er ook niets te matchen — dezelfde
  // redenering als bij het openen van schijf (file_service_open).
  final d = DismissalCodec.decode(json, fallbackSalt: newDismissalSalt());
  return d.isEmpty
      ? (deck: deck, onleesbaar: true)
      : (deck: deck.copyWith(dismissals: d), onleesbaar: false);
}

/// Hang de MIAUW-dispositie uit `deck.miauw.json` weer aan [deck] — zelfde
/// contract als de andere lagen, en net als bij de terzijdeleggingen is er
/// geen heranker-stap: de identiteit is het EIS-nummer, geen dia-positie.
typedef RepoMiauw = ({Deck deck, bool onleesbaar});

Future<RepoMiauw> withRepoMiauw(
  Deck deck, {
  required String deckDir,
  required RepoFileReader read,
}) async {
  Uint8List? bytes;
  try {
    bytes = await read(p.posix.join(deckDir, miauwRepoFileName));
  } catch (e) {
    logWarning('withRepoMiauw: MIAUW-dispositiebestand onbereikbaar', e);
    return (deck: deck, onleesbaar: true);
  }
  if (bytes == null || bytes.isEmpty) {
    return (deck: deck, onleesbaar: false);
  }
  if (bytes.length > maxRepoMiauwBytes) {
    logWarning(
      'withRepoMiauw: MIAUW-dispositiebestand is ${bytes.length} bytes '
      '(grens $maxRepoMiauwBytes) — niet geladen',
    );
    return (deck: deck, onleesbaar: true);
  }
  final String json;
  try {
    json = utf8.decode(bytes);
  } on FormatException catch (e) {
    logWarning(
      'withRepoMiauw: MIAUW-dispositiebestand is geen geldige UTF-8',
      e,
    );
    return (deck: deck, onleesbaar: true);
  }
  final d = MiauwCodec.decode(json);
  return d.isEmpty
      ? (deck: deck, onleesbaar: true)
      : (deck: deck.copyWith(miauw: d), onleesbaar: false);
}

/// Hang het zegel uit `deck.seal.json` weer aan [deck] — zelfde contract als
/// de andere lagen. Geen heranker-stap: het zegel gaat over het document als
/// geheel, niet over een dia.
///
/// De hash in het zegel gaat over de bytes van de `.md` zoals die verzegeld op
/// schijf stond ([SealForm.fileBytes]), en dat zijn niet de bytes die de repo
/// draagt — de serialisatie herschrijft afbeeldingspaden naar de pool. Een
/// deck dat uit git opent draagt daarom wél zijn zegel maar geen
/// [Deck.fileHash], en meldt zich als niet-narekenbaar in plaats van als
/// gemanipuleerd — precies zoals een `.ocideck`-pakket dat al doet
/// (`tabs_provider_package.dart`). Narekenen kan tegen het oorspronkelijke
/// bestand, niet tegen de repo-kopie.
typedef RepoSeal = ({Deck deck, bool onleesbaar});

Future<RepoSeal> withRepoSeal(
  Deck deck, {
  required String deckDir,
  required RepoFileReader read,
}) async {
  Uint8List? bytes;
  try {
    bytes = await read(p.posix.join(deckDir, sealRepoFileName));
  } catch (e) {
    logWarning('withRepoSeal: zegelbestand onbereikbaar', e);
    return (deck: deck, onleesbaar: true);
  }
  if (bytes == null || bytes.isEmpty) {
    return (deck: deck, onleesbaar: false);
  }
  if (bytes.length > maxRepoSealBytes) {
    logWarning(
      'withRepoSeal: zegelbestand is ${bytes.length} bytes '
      '(grens $maxRepoSealBytes) — niet geladen',
    );
    return (deck: deck, onleesbaar: true);
  }
  final String json;
  try {
    json = utf8.decode(bytes);
  } on FormatException catch (e) {
    logWarning('withRepoSeal: zegelbestand is geen geldige UTF-8', e);
    return (deck: deck, onleesbaar: true);
  }
  final record = SealCodec.decode(json);
  return record == null
      ? (deck: deck, onleesbaar: true)
      : (deck: record.applyTo(deck), onleesbaar: false);
}

/// Schrijf (of verwijder) de sidecars van [deck] in de commitset — de ene
/// aanroep die `buildDeckRepoFiles` doet, zodat een vierde laag maar op één
/// plek vergeten kan worden.
///
/// Op een stabiel pad naast deck.md, om dezelfde reden als de grafiekdata: een
/// poolpad ís de hash van de inhoud, dus elk getypt teken zou een nieuw
/// bestand minten en het vorige laten wegkwijnen. Ingesprongen geschreven —
/// geen opmaakvoorkeur maar de reden dat D7 klopt; zie `UserNotesCodec.encode`.
/// Grafstenen tellen als inhoud, twee keer: een dia met alléén gewiste streken
/// schrijft wél een inkbestand (D7), en "alles herroepen" schrijft wél een
/// terzijdeleggingenbestand — weggooien laat het gewiste bij de eerstvolgende
/// samenvoeging terugkeren van de andere kant.
Future<void> writeAllRepoSidecars(
  Deck deck, {
  required String deckDir,
  RepoFileReader? read,
  required Map<String, Uint8List> upserts,
  required List<String> deletes,
}) async {
  await writeRepoSidecar(
    path: p.posix.join(deckDir, userNotesRepoFileName),
    state: (path) => repoUserNotesState(path, read),
    encoded: UserNotesCodec.encode(
      deck.slides,
      deck.userNotes,
      forTextMerge: true,
    ),
    upserts: upserts,
    deletes: deletes,
  );
  await writeRepoSidecar(
    path: p.posix.join(deckDir, inkRepoFileName),
    state: (path) => repoInkState(path, read),
    encoded: AnnotationCodec.encode(
      deck.slides,
      deck.annotations,
      forTextMerge: true,
    ),
    upserts: upserts,
    deletes: deletes,
  );
  await writeRepoSidecar(
    path: p.posix.join(deckDir, dismissalsRepoFileName),
    state: (path) => repoDismissalsState(path, read),
    encoded: switch (deck.dismissals) {
      null => null,
      final d => DismissalCodec.encode(d, forTextMerge: true),
    },
    upserts: upserts,
    deletes: deletes,
  );
  await writeRepoSidecar(
    path: p.posix.join(deckDir, miauwRepoFileName),
    state: (path) => repoMiauwState(path, read),
    encoded: MiauwCodec.encodeDisposition(deck.miauw, forTextMerge: true),
    upserts: upserts,
    deletes: deletes,
  );
  // Compact en niet ingesprongen, en dat is geen slordigheid: de D7-reden voor
  // inspringen — een tekst-merge die per entry werkt — bestaat hier niet. Een
  // zegel wordt in één keer gezet en nooit samengevoegd; twee versies van één
  // zegel zijn geen conflict maar een vergissing (§9.7).
  await writeRepoSidecar(
    path: p.posix.join(deckDir, sealRepoFileName),
    state: (path) => repoSealState(path, read),
    encoded: SealCodec.encode(SealRecord.of(deck)),
    upserts: upserts,
    deletes: deletes,
  );
}

/// Schrijf (of verwijder) één sidecar in de commitset, met de vaste volgorde:
/// eérst de vraag "mag ik hier überhaupt aan komen?", dan pas wat erin moet —
/// dezelfde volgorde als `_sidecarUntouchable` op schijf, en niet toevallig:
/// overschrijven is net zo goed half inlezen als verwijderen dat is. Ligt er
/// een bestand dat deze build niet las, dan zou een bestand met jouw ene entry
/// er overheen gaan en de rest ongemerkt weg zijn — erger dan een
/// verwijdering, want het resultaat ziet er gezond uit.
///
/// Verwijderen gebeurt alleen bij [RepoSidecarState.ours]: alleen weghalen wat
/// we ook hadden kunnen schrijven, anders komt een gewiste entry bij de
/// volgende open gewoon terug.
Future<void> writeRepoSidecar({
  required String path,
  required Future<RepoSidecarState> Function(String path) state,
  required String? encoded,
  required Map<String, Uint8List> upserts,
  required List<String> deletes,
}) async {
  final s = await state(path);
  if (s == RepoSidecarState.untouchable) return;
  if (encoded != null) {
    upserts[path] = Uint8List.fromList(utf8.encode(encoded));
  } else if (s == RepoSidecarState.ours) {
    deletes.add(path);
  }
}

/// Wat er op een sidecarpad in de repo ligt, voor zover deze build ermee
/// overweg kan.
enum RepoSidecarState {
  /// Er ligt niets, of we konden niet kijken. Schrijven mag; verwijderen niet —
  /// er valt niets te verwijderen, en "ik weet het niet" is geen opdracht.
  absent,

  /// Een bestand van dit formaat, niet nieuwer dan deze build. Schrijven én
  /// verwijderen mag: we hadden het zelf kunnen schrijven.
  ours,

  /// Er ligt iets dat deze build niet begrijpt — conflictmarkeringen uit een
  /// merge buiten OciDeck, een hogere `version`, of iets wat geen sidecar is.
  /// Niet aanraken, in geen van beide richtingen.
  untouchable,
}

/// De toestand van het notitiebestand op [path], gelezen via [read].
///
/// De regel is opzettelijk streng, en de reden is asymmetrie. Ten onrechte met
/// rust laten kost een verweesd bestand dat bij de volgende opslag vanzelf
/// wordt bijgewerkt. Ten onrechte aanraken kost werk van iemand anders, en dat
/// weet die pas als hij ernaar zoekt.
///
/// Bewust níét via [sidecarIsFromNewerBuild]: die beantwoordt de vraag "komt
/// dit van later?" en zegt bij onleesbare JSON terecht nee. Hier is de vraag
/// een andere — "mag ik hieraan komen?" — en daar is onleesbaar juist het
/// sterkste nee dat er is. Dezelfde bytes, tegengesteld antwoord; vandaar dat
/// het hier uitgeschreven staat in plaats van omgekeerd hergebruikt.
///
/// Zonder [read] is de uitkomst [RepoSidecarState.absent]: het native pad geeft
/// geen lezer mee, en daar moeten de notities wél kunnen reizen. Dat verwijderen
/// er dan nooit gebeurt, is de veilige helft van diezelfde onwetendheid.
Future<RepoSidecarState> repoUserNotesState(
  String path,
  RepoFileReader? read,
) => _repoSidecarState(
  path,
  read,
  maxBytes: maxRepoUserNotesBytes,
  version: UserNotesCodec.version,
  wat: 'notitiebestand',
);

/// De toestand van de ink-sidecar op [path] — dezelfde strenge regel, en sinds
/// FILE_FORMAT dit bestand als bewerkbaar documenteert geldt ook hier: wat een
/// merge buiten OciDeck of een nieuwere build erin achterliet is niet van ons.
Future<RepoSidecarState> repoInkState(String path, RepoFileReader? read) =>
    _repoSidecarState(
      path,
      read,
      maxBytes: maxRepoInkBytes,
      version: AnnotationCodec.version,
      wat: 'inkbestand',
    );

/// De toestand van de terzijdeleggingen-sidecar op [path] — zelfde strenge
/// regel; dit bestand draagt reviewbesluiten van mogelijk een ándere reviewer.
Future<RepoSidecarState> repoDismissalsState(
  String path,
  RepoFileReader? read,
) => _repoSidecarState(
  path,
  read,
  maxBytes: maxRepoDismissalsBytes,
  version: DismissalCodec.version,
  wat: 'terzijdeleggingenbestand',
);

/// De toestand van de MIAUW-dispositie-sidecar op [path] — zelfde strenge
/// regel; ook dit bestand draagt reviewbesluiten van mogelijk een ándere
/// reviewer.
Future<RepoSidecarState> repoMiauwState(String path, RepoFileReader? read) =>
    _repoSidecarState(
      path,
      read,
      maxBytes: maxRepoMiauwBytes,
      version: MiauwCodec.version,
      wat: 'MIAUW-dispositiebestand',
    );

/// De toestand van de zegel-sidecar op [path] — zelfde strenge regel; dit
/// bestand draagt de vaststelling van mogelijk een ándere ondertekenaar.
Future<RepoSidecarState> repoSealState(String path, RepoFileReader? read) =>
    _repoSidecarState(
      path,
      read,
      maxBytes: maxRepoSealBytes,
      version: SealCodec.version,
      wat: 'zegelbestand',
    );

Future<RepoSidecarState> _repoSidecarState(
  String path,
  RepoFileReader? read, {
  required int maxBytes,
  required int version,
  required String wat,
}) async {
  if (read == null) return RepoSidecarState.absent;
  Uint8List? bytes;
  try {
    bytes = await read(path);
  } catch (e) {
    logWarning('repoSidecarState: $wat onbereikbaar, niet aanraken', e);
    return RepoSidecarState.untouchable;
  }
  if (bytes == null || bytes.isEmpty) return RepoSidecarState.absent;
  if (bytes.length > maxBytes) return RepoSidecarState.untouchable;
  try {
    final data = jsonDecode(utf8.decode(bytes));
    // Geldige JSON is nog geen sidecar. `declaredSidecarVersion` valt bij alles
    // wat geen map is terug op versie 1 — een top-level array zou dus van ons
    // heten. Sinds FILE_FORMAT §6.3.1 uitnodigt dit bestand vanuit een ander
    // werktuig te schrijven, is dat geen theorie meer.
    if (data is! Map) return RepoSidecarState.untouchable;
    return declaredSidecarVersion(data) <= version
        ? RepoSidecarState.ours
        : RepoSidecarState.untouchable;
  } on FormatException catch (e) {
    logWarning(
      'repoSidecarState: $wat is geen leesbare JSON '
      '(conflictmarkeringen?) — niet aanraken',
      e,
    );
    return RepoSidecarState.untouchable;
  }
}
