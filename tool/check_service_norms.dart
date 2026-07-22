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
