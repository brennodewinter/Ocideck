// Meetinstrument voor de servicenormen rond beveiligingsmeldingen.
//
//   dart run tool/check_service_norms.dart              (of: make servicenormen)
//   dart run tool/check_service_norms.dart --advisory   (rapporteert, faalt nooit)
//   dart run tool/check_service_norms.dart --quiet       (zwijgt als alles goed is)
//
// ── Waarom dit hier staat en niet in docs/ ──────────────────────────────────
//
// OciDeck houdt de reactietermijnen van de Cyberweerbaarheidsverordening
// vrijwillig aan. Dat is een keuze over gedrag, geen productbelofte. Het
// verschil is niet cosmetisch:
//
//   Een norm die je MEET kun je missen, onderzoeken en bijstellen. Hij dient
//   jezelf.
//   Een norm die je PUBLICEERT is een toezegging aan derden. Hij wordt een
//   producteigenschap waarop je wordt afgerekend — in een vragenlijst, in een
//   aanbesteding, en uiteindelijk in een aansprakelijkheidsdiscussie. Dan is de
//   gemiste termijn niet meer een aanleiding om te leren, maar een verwijt.
//
// Daarom staan de getallen hieronder als CODE in het gereedschap, en niet als
// zin in een document. Drie plekken zijn bewust vermeden:
//
//   docs/*.md   Alles daar wordt als asset meegeleverd (zie pubspec.yaml) én
//               krijgt een leestegel in de app; docs_registration_test dwingt
//               dat af. Een intern normendocument daar IS een gepubliceerde
//               belofte, ongeacht de kop erboven.
//   SECURITY.md Het naar buiten gerichte beveiligingsbeleid. Precies het
//               document waar een termijn een toezegging wordt.
//   README/     Idem: de voorkant van het project.
//
// `tool/` reist met niets mee. Het zit niet in lib/, niet in de assets, niet in
// een bouwartefact — het is de werkplaats, niet het product. En doordat de
// normen naast de meting staan in plaats van in een tekst ernaast, kunnen ze
// niet uit elkaar lopen: bijstellen betekent hier de meting bijstellen.
//
// De repository is open, dus dit bestand is leesbaar. Dat is geen bezwaar.
// Openbaar zijn en een toezegging doen zijn niet hetzelfde: dit zijn interne
// alarmdrempels waarop wij onszelf wekken, geen termijn waarop een derde zich
// kan beroepen. Wie deze grens weer wil verleggen, verplaatst geen bestand maar
// neemt een besluit.
//
// ── Wat het meet ───────────────────────────────────────────────────────────
//
// Uit gegevens die er al zijn. Een handgeschreven lijst veroudert en niemand
// vult hem; de tijdstempels van de meldingen zijn er hoe dan ook. Per melding
// met een beveiligingslabel worden drie afstanden gerekend:
//
//   eerste reactie — melding → de eerste gebeurtenis van iemand anders dan de
//                    melder (een reactie, een label, een toewijzing).
//   oordeel        — melding → het moment waarop een oordeellabel geplakt is:
//                    is dit echt of is het ruis. Sluiten telt ook als oordeel;
//                    een gesloten melding is beoordeeld.
//   oplossing      — melding → sluiting, alleen voor een BEVESTIGDE melding.
//                    Ruis hoeft niet opgelost te worden.
//
// ── Nul metingen ───────────────────────────────────────────────────────────
//
// Er is nog geen release en dus geen melding. Dat is de reden om dit nú te
// bouwen: het instrument hoort er te staan vóór de eerste melding, niet erna.
// Bij een lege verzameling zegt het dat er niets gemeten is — en uitdrukkelijk
// niet dat de normen gehaald worden. Stilte mag hier net zomin als goedkeuring
// lezen als bij tool/check_reference_data.dart.
//
// ── Hoe je het merkt zonder erop te letten ─────────────────────────────────
//
// De poort draait mee in `make check-full`, dus vóór elke release komt een
// overschrijding onder ogen. Dat is niet genoeg: een termijn verloopt tussen
// releases door. Daarvoor is `--quiet` er — dan zwijgt dit gereedschap zolang
// alles binnen de norm valt en schrijft het alleen bij een dreiging of een
// overschrijding. Zet het daarmee in cron (of launchd) en je hoort er niets
// van tot er iets te horen valt:
//
//   0 8 * * 1-5  cd /pad/naar/ocideck && dart run tool/check_service_norms.dart --quiet --advisory
//
// Dat installeren is een keuze van de beheerder, geen onderdeel van deze repo:
// het is instelling van een machine, niet van het project.
//
// Exit codes:  0 = geen norm overschreden (een dreiging meldt zich wél, maar
//                  faalt niet: hij vraagt aandacht, niet een rode poort)
//              1 = ten minste één norm overschreden
//              2 = de meting kon niet draaien (geen sleutel, geen netwerk)
//
// Met `--advisory` is de uitkomst altijd 0. Zie de redenering in
// tool/check_reference_data.dart: de poort vraagt *mag dit door?*, de
// adviserende variant vraagt *weet ik hoe het ervoor staat?*.
import 'dart:convert';
import 'dart:io';

// ── De normen ──────────────────────────────────────────────────────────────

/// Een interne termijn waarop dit project zichzelf wekt.
///
/// [limiet] is de norm zelf, [waarschuwVanaf] de drempel waarboven het
/// "dreigt" heet. Die tweede is geen zachtere norm maar een vooraankondiging:
/// een termijn die je pas op de laatste dag ziet, red je niet meer.
class ServiceNorm {
  const ServiceNorm({
    required this.id,
    required this.omschrijving,
    required this.limiet,
    required this.waarschuwVanaf,
    required this.inWerkdagen,
  });

  final String id;
  final String omschrijving;
  final int limiet;
  final int waarschuwVanaf;

  /// Werkdagen voor de menselijke termijnen (reageren en oordelen doet een
  /// mens, en die werkt niet in het weekend), kalenderdagen voor de oplossing
  /// (een kwetsbaarheid rust niet in het weekend).
  final bool inWerkdagen;

  String get eenheid => inWerkdagen ? 'werkdagen' : 'dagen';
}

/// De normen om mee te beginnen. Bij te stellen zodra er echte metingen zijn —
/// dat is het hele nut van meten in plaats van beloven.
const serviceNormen = <ServiceNorm>[
  ServiceNorm(
    id: 'eerste-reactie',
    omschrijving: 'eerste reactie',
    limiet: 5,
    waarschuwVanaf: 4,
    inWerkdagen: true,
  ),
  ServiceNorm(
    id: 'oordeel',
    omschrijving: 'oordeel echt-of-ruis',
    limiet: 10,
    waarschuwVanaf: 8,
    inWerkdagen: true,
  ),
  ServiceNorm(
    id: 'oplossing',
    omschrijving: 'oplossing na bevestiging',
    limiet: 90,
    waarschuwVanaf: 75,
    inWerkdagen: false,
  ),
];

/// Labels die een issue tot beveiligingsmelding maken. Kleine letters; de
/// vergelijking is hoofdletterongevoelig.
const meldingLabels = <String>{'beveiliging', 'security', 'kwetsbaarheid'};

/// Labels waarmee het oordeel "dit is echt" wordt vastgelegd.
const bevestigdLabels = <String>{'bevestigd', 'confirmed', 'geldig'};

/// Labels waarmee het oordeel "dit is geen bevinding" wordt vastgelegd.
const ruisLabels = <String>{
  'geen-bevinding',
  'ruis',
  'invalid',
  'niet-reproduceerbaar',
};

// ── Werkdagen ──────────────────────────────────────────────────────────────

/// Paaszondag in [jaar], Gregoriaans (Meeus/Jones/Butcher).
///
/// Het hele feestdagenrooster hangt hieraan: tweede paasdag, Hemelvaart en
/// tweede pinksterdag zijn er verschuivingen van.
DateTime paaszondag(int jaar) {
  final a = jaar % 19;
  final b = jaar ~/ 100;
  final c = jaar % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final maand = (h + l - 7 * m + 114) ~/ 31;
  final dag = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(jaar, maand, dag);
}

/// De dagen die dit project als vrij rekent in [jaar].
///
/// Goede Vrijdag en Bevrijdingsdag staan er bewust NIET in: die zijn niet
/// algemeen vrij, en ze weglaten laat de klok doortikken. Dat is de veilige
/// richting — een norm die te streng meet meldt hooguit te vroeg, een norm die
/// te ruim meet mist een overschrijding.
Set<DateTime> feestdagen(int jaar) {
  final pasen = paaszondag(jaar);
  // Koningsdag schuift naar zaterdag als 27 april op zondag valt.
  final aprilZevenentwintig = DateTime(jaar, 4, 27);
  final koningsdag = aprilZevenentwintig.weekday == DateTime.sunday
      ? DateTime(jaar, 4, 26)
      : aprilZevenentwintig;
  return {
    DateTime(jaar, 1, 1), // Nieuwjaarsdag
    pasen.add(const Duration(days: 1)), // Tweede paasdag
    koningsdag,
    pasen.add(const Duration(days: 39)), // Hemelvaartsdag
    pasen.add(const Duration(days: 50)), // Tweede pinksterdag
    DateTime(jaar, 12, 25), // Eerste kerstdag
    DateTime(jaar, 12, 26), // Tweede kerstdag
  };
}

/// De kalenderdatum van [moment] in lokale tijd, zonder tijd van de dag.
///
/// Werkdagen zijn een lokaal begrip: een melding die om 23:30 UTC op vrijdag
/// binnenkomt is in Nederland al zaterdag.
DateTime kalenderdag(DateTime moment) {
  final lokaal = moment.toLocal();
  return DateTime(lokaal.year, lokaal.month, lokaal.day);
}

/// Is [moment] een werkdag: maandag t/m vrijdag en geen feestdag.
bool isWerkdag(DateTime moment) {
  final dag = kalenderdag(moment);
  if (dag.weekday == DateTime.saturday || dag.weekday == DateTime.sunday) {
    return false;
  }
  return !feestdagen(dag.year).contains(dag);
}

/// Verstreken werkdagen tussen [van] en [tot].
///
/// Geteld worden de werkdagen ná de dag van [van] tot en met de dag van [tot].
/// Op vrijdag melden en maandag antwoorden is dus 1 werkdag, niet 3 — en op
/// vrijdag melden en zaterdag antwoorden is 0.
int werkdagenTussen(DateTime van, DateTime tot) {
  var loper = kalenderdag(van);
  final einde = kalenderdag(tot);
  if (!einde.isAfter(loper)) return 0;
  var aantal = 0;
  while (loper.isBefore(einde)) {
    loper = DateTime(loper.year, loper.month, loper.day + 1);
    if (isWerkdag(loper)) aantal++;
  }
  return aantal;
}

/// Verstreken kalenderdagen tussen [van] en [tot], op dagniveau.
int kalenderdagenTussen(DateTime van, DateTime tot) {
  final verschil = kalenderdag(tot).difference(kalenderdag(van)).inDays;
  return verschil < 0 ? 0 : verschil;
}

/// De afstand tussen [van] en [tot] in de eenheid van [norm].
int afstandVoor(ServiceNorm norm, DateTime van, DateTime tot) =>
    norm.inWerkdagen
    ? werkdagenTussen(van, tot)
    : kalenderdagenTussen(van, tot);

// ── De melding ─────────────────────────────────────────────────────────────

/// Eén beveiligingsmelding, teruggebracht tot de momenten die ertoe doen.
///
/// Geen titel, geen tekst, geen melder. Dit gereedschap kan in een cron-mail
/// terechtkomen, en de inhoud van een openstaande kwetsbaarheidsmelding hoort
/// niet ongevraagd in iemands postvak. Het nummer is genoeg om hem op te
/// zoeken; wie hem mag lezen, leest hem in de forge.
class Melding {
  const Melding({
    required this.nummer,
    required this.gemeld,
    this.eersteReactie,
    this.oordeelOp,
    this.bevestigd = false,
    this.gesloten,
    this.afgesprokenUiterlijk,
  });

  /// Het issuenummer in de forge.
  final int nummer;

  /// Wanneer de melding binnenkwam.
  final DateTime gemeld;

  /// De eerste gebeurtenis van iemand anders dan de melder, of null.
  final DateTime? eersteReactie;

  /// Wanneer een oordeellabel (echt of ruis) geplakt is, of null.
  final DateTime? oordeelOp;

  /// Luidde het oordeel "dit is echt"?
  final bool bevestigd;

  /// Wanneer de melding gesloten is, of null.
  final DateTime? gesloten;

  /// Een in overleg afgesproken eerdere einddatum (de due date op het issue).
  ///
  /// De norm is "binnen 90 dagen **of eerder in overleg**". Zo'n afspraak is
  /// geen aantekening in een verslag maar een datum op de melding zelf — dan
  /// meet dit gereedschap er ook tegen.
  final DateTime? afgesprokenUiterlijk;
}

/// Hoe een melding er tegenover één norm voor staat.
enum Stand {
  /// Binnen de norm afgerond.
  gehaald,

  /// Nog bezig, ruim binnen de norm.
  loopt,

  /// Nog bezig, over de waarschuwingsdrempel: dit gaat mis als het zo blijft.
  dreigt,

  /// Over de norm heen — of hij nu nog loopt of te laat is afgerond.
  overschreden,

  /// Deze norm geldt hier niet (ruis hoeft niet opgelost te worden).
  nietVanToepassing,
}

/// De uitkomst van één norm tegen één melding.
class Meting {
  const Meting({
    required this.nummer,
    required this.norm,
    required this.stand,
    required this.verstreken,
    required this.limiet,
    required this.afgerond,
  });

  final int nummer;
  final ServiceNorm norm;
  final Stand stand;

  /// Verstreken tijd in de eenheid van de norm.
  final int verstreken;

  /// De limiet waartegen gemeten is — lager dan de norm als er een eerdere
  /// datum is afgesproken.
  final int limiet;

  /// Is de klok gestopt, of loopt hij nog?
  final bool afgerond;

  bool get vraagtAandacht =>
      stand == Stand.dreigt || stand == Stand.overschreden;
}

/// De drempel waarboven het "dreigt" heet, meegeschaald met [limiet].
///
/// Bij de volle norm is dat gewoon `norm.waarschuwVanaf`. Is er een kortere
/// termijn afgesproken, dan schuift de waarschuwing evenredig mee: een afspraak
/// van 30 dagen waarschuwt op 25, niet op 75 — dat laatste zou pas na afloop
/// vallen en de waarschuwing zinloos maken.
int waarschuwingsdrempel(ServiceNorm norm, int limiet) {
  if (limiet >= norm.limiet) return norm.waarschuwVanaf;
  final geschaald = (limiet * norm.waarschuwVanaf) ~/ norm.limiet;
  return geschaald < 1 ? 1 : geschaald;
}

Stand _standVoor({
  required int verstreken,
  required int limiet,
  required int drempel,
  required bool afgerond,
}) {
  if (verstreken > limiet) return Stand.overschreden;
  if (afgerond) return Stand.gehaald;
  return verstreken >= drempel ? Stand.dreigt : Stand.loopt;
}

/// Het moment waarop de klok voor [norm] stopte, of null als hij nog loopt.
///
/// Sluiten stopt elke klok. Een gesloten melding wacht niet meer op een eerste
/// reactie — anders zou een zelf gemelde en zelf afgehandelde bevinding tot in
/// eeuwigheid als onbeantwoord blijven staan.
DateTime? _eindpuntVoor(ServiceNorm norm, Melding melding) {
  switch (norm.id) {
    case 'eerste-reactie':
      return melding.eersteReactie ?? melding.gesloten;
    case 'oordeel':
      return melding.oordeelOp ?? melding.gesloten;
    default:
      return melding.gesloten;
  }
}

/// De effectieve limiet voor [norm]: de norm, of de eerder afgesproken datum.
int _limietVoor(ServiceNorm norm, Melding melding) {
  final afspraak = melding.afgesprokenUiterlijk;
  if (norm.id != 'oplossing' || afspraak == null) return norm.limiet;
  final afgesproken = kalenderdagenTussen(melding.gemeld, afspraak);
  return afgesproken < norm.limiet ? afgesproken : norm.limiet;
}

/// Meet [melding] langs [norm], met [nu] als peilmoment.
Meting beoordeel({
  required ServiceNorm norm,
  required Melding melding,
  required DateTime nu,
}) {
  // De oplossingsnorm geldt alleen voor een bevestigde melding: ruis hoeft niet
  // opgelost te worden, en een melding zonder oordeel valt nog onder de
  // oordeelnorm — die telt hem al.
  if (norm.id == 'oplossing' && !melding.bevestigd) {
    return Meting(
      nummer: melding.nummer,
      norm: norm,
      stand: Stand.nietVanToepassing,
      verstreken: 0,
      limiet: norm.limiet,
      afgerond: melding.gesloten != null,
    );
  }
  final eindpunt = _eindpuntVoor(norm, melding);
  final limiet = _limietVoor(norm, melding);
  final verstreken = afstandVoor(norm, melding.gemeld, eindpunt ?? nu);
  return Meting(
    nummer: melding.nummer,
    norm: norm,
    stand: _standVoor(
      verstreken: verstreken,
      limiet: limiet,
      drempel: waarschuwingsdrempel(norm, limiet),
      afgerond: eindpunt != null,
    ),
    verstreken: verstreken,
    limiet: limiet,
    afgerond: eindpunt != null,
  );
}

/// Elke norm langs elke melding.
List<Meting> meetAlles(List<Melding> meldingen, DateTime nu) => [
  for (final melding in meldingen)
    for (final norm in serviceNormen)
      beoordeel(norm: norm, melding: melding, nu: nu),
];
