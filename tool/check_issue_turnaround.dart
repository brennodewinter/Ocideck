// Meetinstrument voor de doorlooptijd van GEWONE issues.
//
//   dart run tool/check_issue_turnaround.dart            (of: make doorlooptijd)
//   dart run tool/check_issue_turnaround.dart --quiet     (zwijgt als er niets speelt)
//   dart run tool/check_issue_turnaround.dart --strict     (eindigt op 1 bij een signaal)
//
// ── Waarom dit naast check_service_norms staat ─────────────────────────────
//
// `tool/check_service_norms.dart` meet beveiligingsmeldingen tegen termijnen
// die dit project zichzelf oplegt. Voor de gewone tracker bestaan zulke
// termijnen NIET, en dat is een bewuste keuze: een zelf opgelegde deadline die
// je op een rustige week mist, verandert een leermoment in een verwijt.
//
// Daarom meet dit instrument wél, maar oordeelt het niet. Het rapporteert
// leeftijd, tijd tot eerste reactie en stilstand; welk getal te hoog is, is
// een gesprek en geen constante. Zodra er een basislijn ligt kan dat gesprek
// gevoerd worden — dat is de volgorde: eerst meten, dan pas een norm.
//
// ── Adviserend is hier de STANDAARD, niet een vlag ─────────────────────────
//
// De zusterpoort heeft `--advisory` omdat haar standaard streng is. Hier is het
// andersom: dit gereedschap eindigt uit zichzelf op 0, ook als er een issue van
// een half jaar oud onbeantwoord staat. Wie het tóch als poort wil gebruiken —
// bijvoorbeeld nadat er een norm is afgesproken — zet `--strict`.
//
// Een `--advisory`-vlag die niets doet omdat adviserend al de standaard is,
// staat er expres niet: een vlag die geen verschil maakt, leert de lezer dat
// vlaggen er niet toe doen.
//
// ── Wat het meet ───────────────────────────────────────────────────────────
//
// Uit gegevens die er toch al zijn — de tijdstempels op de issues en op de
// reacties. Vier dingen, in volgorde van gewicht:
//
//   zonder reactie — hoeveel open issues nog nooit antwoord kregen. Dit is het
//                    getal dat het zwaarst telt. Een issue dat traag wordt
//                    opgelost is ongemak; een issue waar nooit iemand op
//                    reageert is een indiener die niet weet of hij gehoord is.
//   leeftijd       — hoe lang elk open issue al openstaat, en welke de oudste
//                    is.
//   eerste reactie — melding → de eerste reactie van iemand anders dan de
//                    indiener, over de issues die er een kregen.
//   triage-stilstand — issues met het label `triage` die daar blijven staan.
//                    `triage` betekent "nog te wegen"; een issue dat er maanden
//                    op staat, is niet gewogen maar vergeten.
//
// ── Waarom een REACTIE en niet een label ───────────────────────────────────
//
// De zusterpoort telt élke gebeurtenis van een ander als eerste reactie: een
// label, een toewijzing, een reactie. Hier telt alleen een reactie mee. Het
// verschil is het perspectief. Bij een beveiligingsmelding meet je of er
// gewerkt wordt; een label is dan een bewijs van leven. Bij een gewone issue
// meet je wat de indiener merkt, en die ziet een label niet als antwoord.
//
// Dat scheelt bovendien een netwerkvraag per issue: de reacties van de hele
// repository komen in één gepagineerde lijst binnen.
//
// ── Beveiligingsmeldingen tellen hier niet mee ─────────────────────────────
//
// Issues met een beveiligingslabel worden overgeslagen: die hebben hun eigen
// termijnen en hun eigen instrument. Ze hier meetellen zou het beeld twee keer
// vertekenen — de strenge norm verdwijnt in een gemiddelde, en een cijfer over
// "de gewone tracker" gaat dan over iets anders dan de naam belooft.
//
// ── Waarom hier geen inhoud in de uitvoer staat ────────────────────────────
//
// Net als de zusterpoort schrijft dit gereedschap nummers en datums, geen
// titels en geen indieners. Het kan in een cron-mail terechtkomen, en de
// inhoud van andermans issue hoort niet ongevraagd in een postvak. Het nummer
// is genoeg om het op te zoeken.
//
// Exit codes:  0 = gemeten (ook als er signalen zijn — zie hierboven)
//              1 = alleen met --strict: ten minste één signaal
//              2 = de meting kon niet draaien (geen sleutel, geen netwerk)
//
// Uitkomst 2 zwijgt ook onder `--quiet`. Een instrument dat niet kan meten moet
// dat zeggen; anders is stilte niet te onderscheiden van "alles in orde".
import 'dart:convert';
import 'dart:io';

// ── De signaaldrempels ─────────────────────────────────────────────────────

/// Vanaf hoeveel dagen zonder enige reactie een open issue in de aandachtslijst
/// komt.
///
/// Twee weken, en bewust geen norm: het is de drempel waarop dit gereedschap
/// het je vertelt, niet de termijn waarbinnen iets moet gebeuren. Verlaag hem
/// gerust — hij verandert alleen wat je te horen krijgt, niet wat er faalt.
const int geenReactieSignaalDagen = 14;

/// Vanaf hoeveel dagen een issue dat op `triage` blijft staan als stilstand
/// wordt gemeld.
///
/// `triage` is een tussenstation. Een maand erop staan betekent dat de weging
/// nooit is afgemaakt — en dat is iets anders dan een issue dat gewogen is en
/// bewust wacht.
const int triageStilstandDagen = 30;

/// Labels die een issue tot beveiligingsmelding maken; die horen bij
/// `tool/check_service_norms.dart` en worden hier overgeslagen.
///
/// Dezelfde verzameling als daar, hier apart opgeschreven zodat dit bestand
/// zelfstandig te lezen en te toetsen is.
const beveiligingsLabels = <String>{'beveiliging', 'security', 'kwetsbaarheid'};

/// Het label dat "nog te wegen" betekent.
const triageLabel = 'triage';

// ── Het issue ──────────────────────────────────────────────────────────────

/// Eén issue uit de gewone tracker, teruggebracht tot de momenten die ertoe
/// doen. Geen titel, geen indiener, geen tekst — zie de kop van dit bestand.
class TrackerIssue {
  const TrackerIssue({
    required this.nummer,
    required this.geopend,
    this.eersteReactie,
    this.gesloten,
    this.labels = const {},
  });

  /// Het issuenummer in de forge.
  final int nummer;

  /// Wanneer het issue geopend is.
  final DateTime geopend;

  /// De eerste reactie van iemand anders dan de indiener, of null.
  final DateTime? eersteReactie;

  /// Wanneer het issue gesloten is, of null.
  final DateTime? gesloten;

  /// De labelnamen, in kleine letters.
  final Set<String> labels;

  bool get isOpen => gesloten == null;

  /// Staat dit issue nog op `triage`?
  bool get wachtOpWeging => isOpen && labels.contains(triageLabel);

  /// Hoe lang het issue open is (of open wás), in kalenderdagen, gemeten op
  /// [nu].
  int leeftijd(DateTime nu) => _dagenTussen(geopend, gesloten ?? nu);

  /// Dagen tot de eerste reactie, of null als die er niet is.
  ///
  /// Sluiten telt niet als reactie. Een issue dat zonder een woord gesloten
  /// wordt, is niet beantwoord — en juist dát moet zichtbaar blijven.
  int? dagenTotReactie() =>
      eersteReactie == null ? null : _dagenTussen(geopend, eersteReactie!);
}

/// Kalenderdagen tussen twee momenten, op dagniveau en nooit negatief.
///
/// Kalenderdagen en geen werkdagen: dit meet hoe lang een indiener wacht, en
/// die wacht ook in het weekend. De zusterpoort rekent in werkdagen omdat zij
/// een norm meet die een mens moet halen; hier is er geen norm om te halen.
int _dagenTussen(DateTime van, DateTime tot) {
  final a = _kalenderdag(van);
  final b = _kalenderdag(tot);
  final verschil = b.difference(a).inDays;
  return verschil < 0 ? 0 : verschil;
}

DateTime _kalenderdag(DateTime moment) {
  final lokaal = moment.toLocal();
  return DateTime(lokaal.year, lokaal.month, lokaal.day);
}

// ── Uit de forge-JSON ──────────────────────────────────────────────────────

DateTime? _tijd(Object? waarde) {
  if (waarde is! String || waarde.isEmpty) return null;
  final moment = DateTime.tryParse(waarde);
  // Forgejo schrijft een leeg tijdstip als het jaar 1; dat is geen datum.
  return (moment == null || moment.year < 1900) ? null : moment;
}

Set<String> _labelnamen(Object? labels) => {
  if (labels is List)
    for (final label in labels)
      if (label is Map && label['name'] is String)
        (label['name']! as String).toLowerCase(),
};

/// Bij welk issuenummer hoort deze reactie? Null voor een reactie op een pull
/// request of wanneer het nummer niet af te leiden is.
///
/// Forgejo laat `issue_url` leeg voor een reactie op een pull request en vult
/// dan `pull_request_url`. Beide velden zijn er altijd, dus de vorm van de URL
/// is de betrouwbaarste aanwijzing en niet de aanwezigheid van een sleutel.
int? issuenummerVanReactie(Map<String, Object?> reactie) {
  for (final veld in ['issue_url', 'html_url']) {
    final url = reactie[veld];
    if (url is! String || url.isEmpty) continue;
    final treffer = RegExp(r'/issues/(\d+)(?:$|[#?])').firstMatch(url);
    if (treffer != null) return int.tryParse(treffer.group(1)!);
  }
  return null;
}

/// Het moment van de eerste reactie per issuenummer.
///
/// [reacties] is de platte lijst die de forge teruggeeft voor de hele
/// repository; [indieners] zegt per issuenummer wie het indiende, zodat een
/// indiener die zichzelf achterna praat niet als antwoord telt.
Map<int, DateTime> eersteReactiesUit(
  List<Object?> reacties,
  Map<int, String?> indieners,
) {
  final eerste = <int, DateTime>{};
  for (final ruw in reacties) {
    if (ruw is! Map<String, Object?>) continue;
    final nummer = issuenummerVanReactie(ruw);
    if (nummer == null) continue;
    final wanneer = _tijd(ruw['created_at']);
    if (wanneer == null) continue;
    final wie = (ruw['user'] as Map?)?['login'];
    if (wie != null && wie == indieners[nummer]) continue;
    final bekend = eerste[nummer];
    if (bekend == null || wanneer.isBefore(bekend)) eerste[nummer] = wanneer;
  }
  return eerste;
}

/// Zet de ruwe issuelijst plus de ruwe reactielijst om in [TrackerIssue]s.
///
/// Pull requests en beveiligingsmeldingen vallen af. Dat filter zit hier en
/// niet in de netwerkvraag, zodat het te toetsen is zonder forge — en zodat het
/// ook werkt wanneer de labels nog niet bestaan.
List<TrackerIssue> issuesUit(List<Object?> issues, List<Object?> reacties) {
  final ruwe = <int, Map<String, Object?>>{};
  final indieners = <int, String?>{};
  for (final issue in issues) {
    if (issue is! Map<String, Object?>) continue;
    if (issue['pull_request'] != null) continue;
    final nummer = issue['number'];
    if (nummer is! int) continue;
    if (_labelnamen(
      issue['labels'],
    ).intersection(beveiligingsLabels).isNotEmpty) {
      continue;
    }
    if (_tijd(issue['created_at']) == null) continue;
    ruwe[nummer] = issue;
    final wie = (issue['user'] as Map?)?['login'];
    indieners[nummer] = wie is String ? wie : null;
  }

  final eerste = eersteReactiesUit(reacties, indieners);
  final resultaat = [
    for (final entry in ruwe.entries)
      TrackerIssue(
        nummer: entry.key,
        geopend: _tijd(entry.value['created_at'])!,
        eersteReactie: eerste[entry.key],
        gesloten: _tijd(entry.value['closed_at']),
        labels: _labelnamen(entry.value['labels']),
      ),
  ]..sort((a, b) => a.nummer.compareTo(b.nummer));
  return resultaat;
}

// ── Het beeld ──────────────────────────────────────────────────────────────

/// Wat er uit een verzameling issues te zeggen valt op één peilmoment.
class Doorloopbeeld {
  const Doorloopbeeld({
    required this.open,
    required this.gesloten,
    required this.zonderReactie,
    required this.langZonderReactie,
    required this.oudste,
    required this.medianeLeeftijd,
    required this.medianeReactietijd,
    required this.langsteReactietijd,
    required this.beantwoord,
    required this.triageStilstand,
  });

  /// De open issues, oudste eerst.
  final List<TrackerIssue> open;

  /// Hoeveel issues gesloten zijn.
  final int gesloten;

  /// Open issues die nog nooit antwoord kregen, oudste eerst. Het getal dat het
  /// zwaarst telt.
  final List<TrackerIssue> zonderReactie;

  /// Daarvan: de issues die de signaaldrempel gepasseerd zijn.
  final List<TrackerIssue> langZonderReactie;

  /// Het oudste open issue, of null als er geen open issue is.
  final TrackerIssue? oudste;

  /// Mediane leeftijd van de open issues in dagen, of null zonder open issue.
  final int? medianeLeeftijd;

  /// Mediane tijd tot de eerste reactie in dagen, over de issues die er een
  /// kregen; null als er nog geen enkele reactie is.
  final int? medianeReactietijd;

  /// Het issue dat het langst op zijn eerste reactie wachtte, of null.
  final TrackerIssue? langsteReactietijd;

  /// Over hoeveel issues de reactietijd gemeten is.
  final int beantwoord;

  /// Open issues die te lang op `triage` blijven staan, oudste eerst.
  final List<TrackerIssue> triageStilstand;

  /// Is er iets waarvoor iemand nu iets zou moeten doen?
  bool get vraagtAandacht =>
      langZonderReactie.isNotEmpty || triageStilstand.isNotEmpty;
}

/// De mediaan van [waarden], of null bij een lege lijst.
///
/// Mediaan en geen gemiddelde: één issue van drie jaar oud trekt een gemiddelde
/// zo ver weg dat het niets meer zegt over de gewone gang van zaken. Bij een
/// even aantal is dit de bovenste van de twee middelste — naar boven afronden
/// is de veilige richting voor een getal dat traagheid moet laten zien.
int? mediaan(List<int> waarden) {
  if (waarden.isEmpty) return null;
  final gesorteerd = [...waarden]..sort();
  return gesorteerd[gesorteerd.length ~/ 2];
}

/// Maakt het beeld op met [nu] als peilmoment.
Doorloopbeeld meet(List<TrackerIssue> issues, DateTime nu) {
  int oudsteEerst(TrackerIssue a, TrackerIssue b) {
    final byLeeftijd = b.leeftijd(nu).compareTo(a.leeftijd(nu));
    return byLeeftijd != 0 ? byLeeftijd : a.nummer.compareTo(b.nummer);
  }

  final open = issues.where((i) => i.isOpen).toList()..sort(oudsteEerst);
  final zonderReactie = open.where((i) => i.eersteReactie == null).toList();
  final beantwoord = issues.where((i) => i.eersteReactie != null).toList();
  final reactietijden = [for (final i in beantwoord) i.dagenTotReactie()!];

  return Doorloopbeeld(
    open: open,
    gesloten: issues.length - open.length,
    zonderReactie: zonderReactie,
    langZonderReactie: zonderReactie
        .where((i) => i.leeftijd(nu) >= geenReactieSignaalDagen)
        .toList(),
    oudste: open.isEmpty ? null : open.first,
    medianeLeeftijd: mediaan([for (final i in open) i.leeftijd(nu)]),
    medianeReactietijd: mediaan(reactietijden),
    langsteReactietijd: beantwoord.isEmpty
        ? null
        : (beantwoord.toList()..sort(
                (a, b) => b.dagenTotReactie()!.compareTo(a.dagenTotReactie()!),
              ))
              .first,
    beantwoord: beantwoord.length,
    triageStilstand:
        open
            .where(
              (i) => i.wachtOpWeging && i.leeftijd(nu) >= triageStilstandDagen,
            )
            .toList()
          ..sort(oudsteEerst),
  );
}

// ── Het rapport ────────────────────────────────────────────────────────────

String _datum(DateTime moment) {
  final d = _kalenderdag(moment);
  return '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';
}

String _dagen(int aantal) => aantal == 1 ? '1 dag' : '$aantal dagen';

List<String> _zonderReactieBlok(Doorloopbeeld beeld, DateTime nu) {
  if (beeld.open.isEmpty) return const [];
  final regels = <String>[
    'Zonder enige reactie: ${beeld.zonderReactie.length} van '
        '${beeld.open.length} open issues'
        '${beeld.zonderReactie.isEmpty ? '' : ' — dit is het getal dat het '
                  'zwaarst telt'}',
  ];
  for (final issue in beeld.zonderReactie) {
    final oud = issue.leeftijd(nu) >= geenReactieSignaalDagen;
    regels.add(
      '    #${issue.nummer}  ${_dagen(issue.leeftijd(nu)).padLeft(9)} open, '
      'geopend ${_datum(issue.geopend)}${oud ? '  ← langer dan '
                '$geenReactieSignaalDagen dagen' : ''}',
    );
  }
  return regels;
}

List<String> _leeftijdBlok(Doorloopbeeld beeld, DateTime nu) {
  if (beeld.open.isEmpty) {
    return ['Geen open issues. Er valt geen leeftijd te meten.'];
  }
  final oudste = beeld.oudste!;
  return [
    'Open: ${beeld.open.length} issue(s), ${beeld.gesloten} gesloten',
    '    oudste     #${oudste.nummer} — ${_dagen(oudste.leeftijd(nu))}, '
        'geopend ${_datum(oudste.geopend)}',
    '    mediaan    ${_dagen(beeld.medianeLeeftijd!)} open',
  ];
}

List<String> _reactieBlok(Doorloopbeeld beeld) {
  if (beeld.beantwoord == 0) {
    return [
      'Eerste reactie: nog geen enkel issue kreeg een reactie. Dat is geen '
          'meting maar een bevinding.',
    ];
  }
  final langste = beeld.langsteReactietijd!;
  return [
    'Eerste reactie (over ${beeld.beantwoord} beantwoorde issue(s)):',
    '    mediaan    ${_dagen(beeld.medianeReactietijd!)}',
    '    langste    ${_dagen(langste.dagenTotReactie()!)} — #${langste.nummer}',
  ];
}

List<String> _triageBlok(Doorloopbeeld beeld, DateTime nu) {
  if (beeld.triageStilstand.isEmpty) {
    return [
      'Triage: geen issue staat langer dan $triageStilstandDagen dagen op '
          '`$triageLabel`.',
    ];
  }
  return [
    'Triage zonder vervolg: ${beeld.triageStilstand.length} issue(s) staan '
        'langer dan $triageStilstandDagen dagen op `$triageLabel`',
    for (final issue in beeld.triageStilstand)
      '    #${issue.nummer}  ${_dagen(issue.leeftijd(nu)).padLeft(9)} open, '
          'geopend ${_datum(issue.geopend)}',
    '    `$triageLabel` betekent "nog te wegen". Zo lang erop staan betekent '
        'niet gewogen maar vergeten.',
  ];
}

List<String> _leeg() => const [
  'Geen gewone issues gevonden. Er is niets gemeten.',
  '',
  '    Nul metingen is geen bewijs dat het goed gaat. Beveiligingsmeldingen en',
  '    pull requests tellen hier niet mee; blijft er dan niets over, dan is de',
  '    tracker leeg of onbereikbaar — twee dingen die er hetzelfde uitzien.',
];

/// De regels die dit gereedschap schrijft. Leeg betekent: niets te zeggen.
List<String> rapport({
  required List<TrackerIssue> issues,
  required DateTime nu,
  required String bron,
  bool quiet = false,
}) {
  final beeld = meet(issues, nu);
  if (quiet && !beeld.vraagtAandacht) return const [];

  final regels = <String>[
    '== OciDeck doorlooptijd gewone issues ==',
    'Bron: $bron  (beveiligingsmeldingen tellen hier niet mee — die meet '
        'check_service_norms)',
    'Peildatum: ${_datum(nu)}',
    '',
  ];
  if (issues.isEmpty) {
    regels.addAll(_leeg());
    return regels;
  }
  regels
    ..addAll(_leeftijdBlok(beeld, nu))
    ..add('')
    ..addAll(_zonderReactieBlok(beeld, nu))
    ..add('')
    ..addAll(_reactieBlok(beeld))
    ..add('')
    ..addAll(_triageBlok(beeld, nu))
    ..add('')
    ..add(_slotzin(beeld));
  return regels;
}

String _slotzin(Doorloopbeeld beeld) {
  if (beeld.langZonderReactie.isNotEmpty) {
    return '${beeld.langZonderReactie.length} issue(s) wachten langer dan '
        '$geenReactieSignaalDagen dagen op een eerste woord. Er is geen norm '
        'die dit verbiedt; dat maakt het niet minder waar.';
  }
  if (beeld.triageStilstand.isNotEmpty) {
    return 'Alles is beantwoord, maar de weging is ergens blijven liggen.';
  }
  // Bewust NIET "alles is beantwoord": er kunnen open issues zonder reactie
  // zijn die alleen nog te jong zijn voor de drempel. Dat verschil verzwijgen
  // zou dit slot een geruststelling maken die de regels erboven tegenspreken.
  return 'Geen signaal: niets wacht langer dan $geenReactieSignaalDagen dagen '
      'op een eerste woord, en niets staat vast op de weging. Dit is een '
      'meting, geen goedkeuring — de getallen hierboven zijn waar het gesprek '
      'over gaat.';
}

/// 1 zodra er een signaal is. Alleen gebruikt onder `--strict`; zonder die vlag
/// eindigt dit gereedschap altijd op 0.
int exitCodeVoor(Doorloopbeeld beeld) => beeld.vraagtAandacht ? 1 : 0;

// ── De vraag aan de forge ──────────────────────────────────────────────────

/// Waar de meting haar gegevens vandaan haalt: de ruwe issuelijst en de ruwe
/// reactielijst, precies zoals de forge ze teruggeeft.
///
/// Dit is een typedef en geen vaste functie zodat de meting te draaien is
/// zonder netwerk. De tests voeren vaste gegevens in; er staat geen sleutel en
/// geen echte reactie in een testbestand.
typedef ForgeGegevens =
    Future<({List<Object?> issues, List<Object?> reacties})> Function();

/// Waar de forge staat en welke repository het betreft.
class ForgeAdres {
  const ForgeAdres(this.host, this.eigenaar, this.repo);

  final String host;
  final String eigenaar;
  final String repo;

  /// Altijd https: de API-poort is een andere dan de git-poort, en
  /// onversleuteld halen we hier niets op.
  Uri get api => Uri.https(host, '/api/v1/repos/$eigenaar/$repo');

  String get web => 'https://$host/$eigenaar/$repo';
}

final _sshVorm = RegExp(
  r'^ssh://[^@]+@([^:/]+)(?::\d+)?/(.+?)/(.+?)(?:\.git)?$',
);
// De negatieve vooruitblik houdt `ssh://…:2222/Groep/Project.git` buiten deze
// vorm; zonder hem leest hij de poort als eigenaar.
final _scpVorm = RegExp(
  r'^(?![a-z][a-z0-9+.-]*://)[^@]+@([^:]+):(.+?)/(.+?)(?:\.git)?$',
);
final _httpVorm = RegExp(
  r'^https?://(?:[^@/]+@)?([^:/]+)(?::\d+)?/(.+?)/(.+?)(?:\.git)?$',
);

/// Leidt het forge-adres af uit een git-remote-URL, of null als dat niet lukt.
///
/// Bewust afgeleid en niet ingetypt: een vaste host in dit bestand zou blijven
/// staan als de repository verhuist, en dan meet dit gereedschap stilletjes de
/// verkeerde plek.
ForgeAdres? forgeUit(String remoteUrl) {
  final url = remoteUrl.trim();
  for (final vorm in [_sshVorm, _scpVorm, _httpVorm]) {
    final m = vorm.firstMatch(url);
    if (m != null) return ForgeAdres(m.group(1)!, m.group(2)!, m.group(3)!);
  }
  return null;
}

/// De sleutelbos-ingang met het lees-token voor de forge. De sleutel zelf staat
/// nergens in deze repository en wordt ook nooit uitgeschreven — hij gaat in
/// een header, nooit in een URL, dus ook niet in een foutmelding.
const _sleutelbosDienst = 'forgejo-pawprint-api';

/// Naam van de omgevingsvariabele die de sleutelbos overslaat (voor een machine
/// zonder macOS-sleutelbos).
const _tokenOmgeving = 'OCIDECK_FORGE_TOKEN';

String? _token() {
  final uitOmgeving = Platform.environment[_tokenOmgeving]?.trim();
  if (uitOmgeving != null && uitOmgeving.isNotEmpty) return uitOmgeving;
  if (!Platform.isMacOS) return null;
  final uitslag = Process.runSync('security', [
    'find-generic-password',
    '-s',
    _sleutelbosDienst,
    '-w',
  ]);
  if (uitslag.exitCode != 0) return null;
  final token = (uitslag.stdout as String).trim();
  return token.isEmpty ? null : token;
}

ForgeAdres? _adresUitRemote() {
  final uitslag = Process.runSync('git', ['remote', 'get-url', 'origin']);
  if (uitslag.exitCode != 0) return null;
  return forgeUit(uitslag.stdout as String);
}

Future<List<Object?>> _haal(HttpClient client, Uri uri, String token) async {
  final verzoek = await client.getUrl(uri);
  verzoek.headers.set(HttpHeaders.authorizationHeader, 'token $token');
  verzoek.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final antwoord = await verzoek.close();
  final tekst = await antwoord.transform(utf8.decoder).join();
  if (antwoord.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${antwoord.statusCode} voor ${uri.path}');
  }
  final ontleed = jsonDecode(tekst);
  return ontleed is List ? ontleed : const [];
}

/// Alle bladzijden van [pad] achter elkaar, tot de forge er geen meer geeft.
Future<List<Object?>> _allePaginas(
  HttpClient client,
  ForgeAdres adres,
  String token,
  String pad,
  Map<String, String> vraag,
) async {
  final alles = <Object?>[];
  for (var pagina = 1; pagina <= 40; pagina++) {
    final blad = await _haal(
      client,
      adres.api.replace(
        path: '${adres.api.path}$pad',
        queryParameters: {...vraag, 'limit': '50', 'page': '$pagina'},
      ),
      token,
    );
    if (blad.isEmpty) break;
    alles.addAll(blad);
  }
  return alles;
}

/// De echte ophaallaag: issues en reacties uit de forge.
ForgeGegevens forgeBron(ForgeAdres adres, String token) => () async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    return (
      issues: await _allePaginas(client, adres, token, '/issues', {
        'state': 'all',
        'type': 'issues',
      }),
      // Eén lijst voor de hele repository in plaats van een tijdlijn per issue:
      // dat scheelt een netwerkvraag per issue, en de reacties zijn precies wat
      // de indiener als antwoord ziet.
      reacties: await _allePaginas(
        client,
        adres,
        token,
        '/issues/comments',
        const {},
      ),
    );
  } finally {
    client.close(force: true);
  }
};

const _gebruik = '''
Gebruik: dart run tool/check_issue_turnaround.dart [--quiet] [--strict]

  --quiet     Zwijg zolang er geen signaal is (voor cron).
  --strict    Eindig op 1 bij een signaal. Standaard is dit adviserend: er is
              geen afgesproken norm voor gewone issues, dus is er niets om op
              te falen.
  --help      Deze tekst.

Sleutel: $_tokenOmgeving, anders de sleutelbos-ingang '$_sleutelbosDienst'.''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_gebruik);
    return;
  }
  const bekend = {'--quiet', '--strict'};
  final onbekend = args.where((a) => !bekend.contains(a)).toList();
  if (onbekend.isNotEmpty) {
    stderr.writeln('Onbekende vlag: ${onbekend.join(', ')}\n\n$_gebruik');
    exit(2);
  }
  final quiet = args.contains('--quiet');
  final strict = args.contains('--strict');

  final adres = _adresUitRemote();
  if (adres == null) {
    stderr.writeln(
      'check_issue_turnaround: kon de forge niet afleiden uit '
      "'git remote get-url origin'.",
    );
    exit(2);
  }
  final token = _token();
  if (token == null) {
    stderr.writeln(
      'check_issue_turnaround: geen leessleutel gevonden. Zet $_tokenOmgeving '
      "of leg hem in de sleutelbos onder '$_sleutelbosDienst'.",
    );
    exit(2);
  }

  List<TrackerIssue> issues;
  try {
    final gegevens = await forgeBron(adres, token)();
    issues = issuesUit(gegevens.issues, gegevens.reacties);
  } on Exception catch (fout) {
    // De sleutel zit in een header en niet in de URL, dus hij kan hier niet
    // uitlekken. Wel gaat dit naar stderr en niet naar stdout: ook onder
    // --quiet moet "ik kon niet meten" hoorbaar zijn.
    stderr.writeln(
      'check_issue_turnaround: de meting kon niet draaien — $fout',
    );
    exit(2);
  }

  final nu = DateTime.now();
  for (final regel in rapport(
    issues: issues,
    nu: nu,
    bron: adres.web,
    quiet: quiet,
  )) {
    stdout.writeln(regel);
  }
  exit(strict ? exitCodeVoor(meet(issues, nu)) : 0);
}
