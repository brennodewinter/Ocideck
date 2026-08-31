// Legt de artefacten die naast een gedownloade webbundel horen in `build/web`
// en verzegelt de uitkomst met een checksumlijst.
//
// Waarom dit een stap is en niet een paar `cp`-regels in de Makefile: de
// volgorde is de hele truc. De checksumlijst moet over de bundel gaan zoals
// die de deur uit gaat, dus ná het laatste bestand dat erbij komt. Zolang het
// kopiëren en het hashen op twee plekken staan, is er een dag waarop iemand er
// een bestand tussen schuift en de lijst stil onvolledig wordt.
//
// Gebruik:
//   dart run tool/pack_web_release.dart            na `flutter build web`
//   dart run tool/pack_web_release.dart --check     controleer een klaargezette bundel
//
// Wat dit NIET is: een handtekening. Zie [checksumUitleg] en docs/BUILD.md —
// een lijst die naast de bundel ligt bewijst dat je hebt wat er lag, niet van
// wie het kwam.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// De bestanden die met de bundel mee moeten, als `bron: doel-in-de-bundel`.
///
/// De licentie en de derdenverklaring omdat een gedistribueerd artefact zonder
/// zijn licentievoorwaarden niet herdistribueerbaar is — dat is geen nettigheid
/// maar de voorwaarde waaronder de afhankelijkheden zelf meereizen. De SBOM
/// omdat de CRA-inventaris bij de exacte build hoort die je uitlevert, niet bij
/// de repo waar hij toevallig uit kwam.
///
/// `SOURCE.md` staat er niet voor de vorm: `main.dart.js` is gecompileerd, en
/// EUPL-1.2 artikel 5 vraagt bij het distribueren *of communiceren* van het
/// Werk om de broncode of een aanwijzing waar die te vinden is. Een gehoste
/// bundel ís communicatie. Zonder dat bestand krijgt de ontvanger onleesbare
/// JavaScript met een licentie eronder die zegt dat hij het mag bestuderen en
/// aanpassen, en geen manier om dat te doen.
const Map<String, String> releaseArtefacten = {
  'LICENSE.md': 'LICENSE.md',
  'THIRD_PARTY_NOTICES.md': 'THIRD_PARTY_NOTICES.md',
  'SOURCE.md': 'SOURCE.md',
  'sbom/ocideck.cdx.json': 'sbom/ocideck.cdx.json',
  'sbom/ocideck.spdx.json': 'sbom/ocideck.spdx.json',
  'sbom/ocideck.sbom.md': 'sbom/ocideck.sbom.md',
};

/// Bestanden die Flutter in `build/web` achterlaat maar die er niet horen.
///
/// `.last_build_id` is een intern markeringsbestand van het buildsysteem. De
/// inhoud is een md5 over onder meer het **absolute pad** van de uitvoermap op
/// de bouwmachine, dus twee mensen die dezelfde bron bouwen krijgen
/// gegarandeerd verschillende waarden. Zou het meegaan in [checksumBestand],
/// dan kan iemand die zelf bouwt — precies wat KNOWN_LIMITATIONS aanraadt —
/// de gepubliceerde digest nóóit reproduceren, om een reden die niets met de
/// code te maken heeft. De ontvanger heeft er bovendien niets aan.
///
/// `.DS_Store` is Finder-metadata die in `build/web` belandt zodra iemand de
/// map opent in Finder (#1888). `.gitignore` vangt hem niet — `build/` is geen
/// git-gebied — en hij brak de reproduceerbaarheid van de bundel en lekte
/// bestandsnamen op de publieke webhost. Breder: elk `.`-bestand dat de bundel
/// niet bewust meeneemt hoort er niet. [ruimOnverwachteDotfiles] vangt die hele
/// klasse; [bewusteDotfiles] bepaalt wat "bewust" is, en deze lijst wint daarvan
/// — `web/.DS_Store` bestaat op een Mac ook.
const List<String> nietUitleveren = ['.last_build_id', '.DS_Store'];

/// Het bootstrap-bestand dat Flutter genereert, en het enige met een
/// bouw-tot-bouw-verschil.
///
/// `flutter build web` schrijft in `flutter_bootstrap.js` één regel
/// `serviceWorkerVersion: "<getal>"` met een **willekeurig** getal — twee schone
/// builds van dezelfde bron verschillen gegarandeerd op dat ene getal en verder
/// op niets. Empirisch getoetst: van 2854 bestanden was dit het enige dat
/// afweek (#1027, `assurance/reproduceerbare-builds.md`). Dat getal is niets
/// meer dan een cache-buster in de queryparameter `flutter_service_worker.js?v=…`
/// van een inmiddels afgeschreven service-workermechanisme; het staat niet in de
/// service-worker zelf (die is over builds heen byte-voor-byte gelijk).
///
/// Zonder dit weggewerkt kan iemand die zelf bouwt — precies wat
/// KNOWN_LIMITATIONS aanraadt — de gepubliceerde bundeldigest nooit
/// reproduceren, om een reden die niets met de code te maken heeft. Dezelfde
/// grond als bij [nietUitleveren]; daarom hoort de reparatie hier, vóór
/// [checksumBestand] wordt geschreven.
const String bootstrapBestand = 'flutter_bootstrap.js';

/// De service-worker waarnaar [bootstrapBestand]'s versie-cachebuster verwijst.
const String serviceWorkerBestand = 'flutter_service_worker.js';

/// De naam van de checksumlijst in de bundel.
///
/// De inhoud is het formaat van `sha256sum` — `<hash><twee spaties><pad>` —
/// zodat zowel GNU coreutils (`sha256sum -c`) als BSD/macOS
/// (`shasum -a 256 -c`) hem zonder omweg kunnen nalopen. Een eigen formaat zou
/// een eigen gereedschap vragen, en dan controleert niemand het.
const String checksumBestand = 'SHA256SUMS';

/// Wat de checksumlijst wél en niet zegt. Staat hier omdat de zin die dit
/// verkeerd samenvat in documentatie belandt en dan een belofte wordt.
///
/// Let op het verschil tussen *tonen* en *laten nakijken*. Een eerdere versie
/// zei dat de lijst toont dat de bundel overeenkomt met een elders gepubliceerde
/// waarde. Dat toont hij niet — dat is iets wat de lezer moet dóén, en op
/// zichzelf zegt de lijst niet meer dan dat hij met zichzelf klopt. In een
/// aankondiging overgenomen leest die eerste formulering als "de bundel draagt
/// het bewijs bij zich", en dat is een sterkere claim dan waar is.
const String checksumUitleg =
    'SHA256SUMS laat je nakijken of je bundel volledig en onbeschadigd is. Op '
    'zichzelf bewijst de lijst niets: pas als je hem afzet tegen een waarde uit '
    'een ander kanaal zegt hij iets. Het is geen handtekening — wie de bundel '
    'kan vervangen, kan de lijst vervangen.';

Future<void> main(List<String> args) async {
  final bundel = Directory('build/web');
  if (!bundel.existsSync()) {
    stderr.writeln('build/web niet gevonden — draai eerst `make build-web`.');
    exit(2);
  }

  if (args.contains('--check')) {
    final klachten = controleer(bundel);
    if (klachten.isEmpty) {
      stdout.writeln(
        'Release-artefacten OK: ${releaseArtefacten.length} bestand(en) aanwezig, '
        '$checksumBestand klopt met de bundel.',
      );
      exit(0);
    }
    stderr.writeln('Release-artefacten NIET in orde:');
    for (final k in klachten) {
      stderr.writeln('  - $k');
    }
    exit(1);
  }

  final ontbreekt = pak(bundel, Directory.current);
  if (ontbreekt.isNotEmpty) {
    stderr.writeln('Ontbrekende bronbestanden:');
    for (final o in ontbreekt) {
      stderr.writeln('  - $o');
    }
    exit(1);
  }

  final digest = bundelDigest(bundel);
  stdout.writeln(
    'Release-artefacten geplaatst en $checksumBestand geschreven.',
  );
  stdout.writeln('sha256 van $checksumBestand: $digest');
  stdout.writeln('Neem die waarde op in de release-aankondiging.');
}

/// Ruimt [releaseArtefacten] in [bundel] op, verwijdert [nietUitleveren] en
/// schrijft daarna [checksumBestand].
///
/// Geeft de bronpaden terug die niet bestonden; is die lijst leeg, dan is de
/// bundel compleet. Een ontbrekende bron is een fout en geen waarschuwing —
/// een bundel zonder licentie mag de deur niet uit.
List<String> pak(Directory bundel, Directory wortel) {
  final ontbreekt = <String>[];
  for (final MapEntry(key: bron, value: doel) in releaseArtefacten.entries) {
    final bestand = File('${wortel.path}/$bron');
    if (!bestand.existsSync()) {
      ontbreekt.add(bron);
      continue;
    }
    final uit = File('${bundel.path}/$doel');
    uit.parent.createSync(recursive: true);
    bestand.copySync(uit.path);
  }
  if (ontbreekt.isNotEmpty) return ontbreekt;

  for (final pad in nietUitleveren) {
    final bestand = File('${bundel.path}/$pad');
    if (bestand.existsSync()) bestand.deleteSync();
  }

  // Ruim ook `.`-bestanden die niet op de lijst staan maar er niet horen —
  // `.DS_Store`, `.DS_Store?`, `.localized`, en alles wat Finder of de OS
  // in de bouwmap dropt (#1888). Wat de bundel bewust meeneemt blijft staan;
  // zie [bewusteDotfiles] voor waar die opzet uit blijkt (#1888).
  ruimOnverwachteDotfiles(bundel, bewusteDotfiles(wortel));

  normaliseerServiceWorkerVersie(bundel);

  // Een commit-aanduiding in de bundel (#1893): `version.json` geeft alleen
  // het build-nummer, niet welke commit er live staat. `git describe` is al
  // berekend door deploy_web.sh, maar dat is een handmatige route die niets
  // achterlaat. Dit bestand wél — het reist mee in de bundel en in SHA256SUMS.
  schrijfBuildInfo(bundel);

  File(
    '${bundel.path}/$checksumBestand',
  ).writeAsStringSync(checksumLijst(bundel));
  return const [];
}

/// Schrijft `build-info.json` in [bundel] met de commit-aanduiding.
///
/// `git describe --tags --always --dirty` geeft een leesbare aanduiding die
/// werkt op een tag (`v0.4.10`), een branch (`v0.4.10-24-gabcdef`), of een
/// kale commit (`abcdef`). Buiten een git-werkkopie (bijv. een uitgepakte
/// tarball) geeft het `onbekend` — het bestand verschijnt nog steeds, zodat
/// de checksumlijst compleet is, maar de ontvanger weet dat hij het zelf
/// moet opzoeken (#1893).
void schrijfBuildInfo(Directory bundel) {
  final result = Process.runSync('git', [
    'describe',
    '--tags',
    '--always',
    '--dirty',
  ]);
  final describe = result.exitCode == 0
      ? (result.stdout as String).trim()
      : 'onbekend';
  final info = JsonEncoder.withIndent('  ').convert({
    // Alleen git_describe, geen build_time: een tijdstip maakt de bundel
    // niet-reproduceerbaar (#1027) en de "twee keer inpakken"-test faalt.
    'git_describe': describe,
  });
  File('${bundel.path}/build-info.json').writeAsStringSync('$info\n');
}

/// De `.`-ingangen die de bundel bewust meeneemt, als pad relatief aan de
/// bundelwortel.
///
/// Twee bronnen, en de tweede repareert wat de sweep van #1888 te ruim wegnam.
/// [releaseArtefacten] dekt wat déze stap erbij legt, maar `flutter build web`
/// kopieert `web/` ongewijzigd in `build/web`, en twee van die ingangen
/// beginnen met een punt omdat de webstandaard dat voorschrijft: `.htaccess`
/// draagt de beveiligingsheaders waar `tool/check_web_hardening.dart` op staat
/// (#849), en `.well-known/security.txt` is het meldadres uit RFC 9116. Ze
/// staan niet in [releaseArtefacten] — deze stap legt ze er niet bij, ze liggen
/// er al — dus is `web/` de enige plek waar hun opzet uit blijkt. Een sweep die
/// alleen naar [releaseArtefacten] keek, veegde ze allebei weg.
///
/// Afleiden uit `web/` en niet opsommen: een volgende dotfile die daar bewust
/// bij komt, hoort er dan meteen in — en de vorm van deze fout was juist dat
/// een lijst achterbleef bij wat de bundel werkelijk meeneemt.
///
/// [nietUitleveren] wint van de herkomst: op een Mac ligt in `web/` ook een
/// `.DS_Store`, en juist die hoort de bundel niet uit (#1888).
Set<String> bewusteDotfiles(Directory wortel) {
  final bewust = {
    for (final doel in releaseArtefacten.values)
      if (doel.split('/').last.startsWith('.')) doel,
  };
  final web = Directory('${wortel.path}/web');
  if (!web.existsSync()) return bewust;
  for (final entiteit in web.listSync(recursive: true)) {
    final pad = relatiefIn(web, entiteit.path);
    // Een verborgen map neemt zijn hele inhoud mee: `.well-known/security.txt`
    // begint zelf niet met een punt, maar hoort er wel bij.
    if (!pad.split('/').any((deel) => deel.startsWith('.'))) continue;
    if (nietUitleveren.contains(pad.split('/').last)) continue;
    bewust.add(pad);
  }
  return bewust;
}

/// Verwijdert `.`-ingangen in [bundel] die niet in [bewust] staan.
///
/// De expliciete lijst in [nietUitleveren] vangt de bekende gevallen, maar een
/// allowlist is sterker dan een denylist: Finder dropt `.DS_Store`, macOS
/// dropt `.localized`, en de volgende OS-versie dropt iets dat nog niemand
/// heeft gezien. Alles wat met een punt begint en niet bewust is meegenomen,
/// hoort niet in een uit te leveren bundel (#1888).
///
/// Vergelijken op het volledige pad en niet op de bestandsnaam: `.htaccess`
/// hoort in de bundelwortel omdat hij in `web/` staat, en dat zegt niets over
/// een `.htaccess` die ergens diep in `canvaskit/` opduikt.
void ruimOnverwachteDotfiles(Directory bundel, Set<String> bewust) {
  for (final entiteit in bundel.listSync(recursive: true)) {
    final pad = relatiefIn(bundel, entiteit.path);
    if (!pad.split('/').last.startsWith('.')) continue;
    if (bewust.contains(pad)) continue;
    // `listSync` is een momentopname: staat een verborgen map hierboven al
    // verwijderd, dan bestaat dit pad niet meer en zou `deleteSync` gooien.
    if (!entiteit.existsSync()) continue;
    entiteit.deleteSync(recursive: true);
  }
}

/// [pad] relatief aan [wortel], altijd met '/' als scheidingsteken.
///
/// Twee redenen om te normaliseren en niet op de OS-scheiding te leunen: de
/// checksumlijst is een portabel artefact (`sha256sum -c` draait op Linux) en
/// moet op elk platform dezelfde regels geven; en op Windows levert `listSync`
/// backslashes, waardoor een prefix-vergelijking met een '/'-achtervoegsel
/// faalde en het hele absolute pad teruggaf — dat plakte verderop als
/// `bundel/C:\...\bestand` en gooide een PathNotFoundException.
String relatiefIn(Directory wortel, String pad) {
  final basis = wortel.path.replaceAll(r'\', '/');
  final voorvoegsel = basis.endsWith('/') ? basis : '$basis/';
  final genormaliseerd = pad.replaceAll(r'\', '/');
  return genormaliseerd.startsWith(voorvoegsel)
      ? genormaliseerd.substring(voorvoegsel.length)
      : genormaliseerd;
}

/// Vervangt het willekeurige `serviceWorkerVersion`-getal in [bootstrapBestand]
/// door een waarde die afgeleid is van de inhoud van [serviceWorkerBestand], en
/// haalt daarmee de laatste bouw-tot-bouw-variatie uit de bundel (#1027).
///
/// Waarom afgeleid en niet een vaste constante: dit getal is de cache-buster
/// achter `flutter_service_worker.js?v=…`. Een vaste waarde zou het reproduceerbaar
/// maken maar de cache-invalidatie breken — een terugkerende bezoeker zou na een
/// nieuwe release een verouderde service-worker kunnen houden. Afgeleid van de
/// service-workerinhoud verandert de waarde precies dan wanneer die inhoud
/// verandert: reproduceerbaar én semantisch juist. Empirisch is de service-worker
/// zelf al byte-voor-byte gelijk over builds, dus deze afleiding is stabiel.
///
/// Robuust tegen een toekomstige Flutter: ontbreekt het bootstrap-bestand, de
/// service-worker of de versieregel, dan is dit een no-op — het mechanisme is
/// afgeschreven en kan verdwijnen. De reparatie mag nooit een build breken.
void normaliseerServiceWorkerVersie(Directory bundel) {
  final bootstrap = File('${bundel.path}/$bootstrapBestand');
  final serviceWorker = File('${bundel.path}/$serviceWorkerBestand');
  if (!bootstrap.existsSync() || !serviceWorker.existsSync()) return;

  final patroon = RegExp(r'(serviceWorkerVersion:\s*")\d+(")');
  final inhoud = bootstrap.readAsStringSync();
  if (!patroon.hasMatch(inhoud)) return;

  final versie = serviceWorkerVersieUit(serviceWorker.readAsBytesSync());
  bootstrap.writeAsStringSync(
    inhoud.replaceAllMapped(patroon, (m) => '${m[1]}$versie${m[2]}'),
  );
}

/// De deterministische service-workerversie voor [serviceWorkerInhoud]: de
/// eerste 32 bits van de sha256 als decimaal getal. Dat houdt dezelfde vorm en
/// grootteorde aan als het getal dat Flutter er zelf neerzette, zodat niets
/// verderop over een onverwacht formaat struikelt.
String serviceWorkerVersieUit(List<int> serviceWorkerInhoud) {
  final hex = sha256.convert(serviceWorkerInhoud).toString().substring(0, 8);
  return int.parse(hex, radix: 16).toString();
}

/// De checksumlijst over [bundel], in `sha256sum`-formaat, op pad gesorteerd.
///
/// [checksumBestand] zelf blijft er buiten — een lijst kan haar eigen hash niet
/// bevatten, en `sha256sum -c` zou over die regel struikelen.
String checksumLijst(Directory bundel) {
  final regels = <String>[];
  for (final pad in bundelBestanden(bundel)) {
    final hash = sha256.convert(File('${bundel.path}/$pad').readAsBytesSync());
    regels.add('$hash  $pad');
  }
  return '${regels.join('\n')}\n';
}

/// De sha256 van de checksumlijst zelf: één waarde die de hele bundel dekt en
/// die een mens uit een release-aankondiging kan overtikken.
String bundelDigest(Directory bundel) {
  final lijst = File('${bundel.path}/$checksumBestand');
  if (!lijst.existsSync()) return '';
  return sha256.convert(lijst.readAsBytesSync()).toString();
}

/// Loopt een klaargezette [bundel] na: staan de artefacten er, en beschrijft
/// [checksumBestand] precies de bestanden die er liggen?
///
/// Zowel een gewijzigd bestand als een bestand dat niet in de lijst staat is
/// een klacht. Dat tweede is het geval dat er in de praktijk toe doet: een
/// stap die later een bestand toevoegt zou anders buiten de lijst vallen en
/// niemand zou het merken.
List<String> controleer(Directory bundel) {
  final klachten = <String>[];
  for (final doel in releaseArtefacten.values) {
    if (!File('${bundel.path}/$doel').existsSync()) {
      klachten.add('$doel ontbreekt in de bundel.');
    }
  }

  final lijst = File('${bundel.path}/$checksumBestand');
  if (!lijst.existsSync()) {
    klachten.add(
      '$checksumBestand ontbreekt — draai tool/pack_web_release.dart.',
    );
    return klachten;
  }

  final opgeschreven = <String, String>{};
  for (final regel in const LineSplitter().convert(lijst.readAsStringSync())) {
    if (regel.trim().isEmpty) continue;
    final scheiding = regel.indexOf('  ');
    if (scheiding < 0) {
      klachten.add('Onleesbare regel in $checksumBestand: $regel');
      continue;
    }
    opgeschreven[regel.substring(scheiding + 2)] = regel.substring(
      0,
      scheiding,
    );
  }

  for (final pad in bundelBestanden(bundel)) {
    final verwacht = opgeschreven.remove(pad);
    if (verwacht == null) {
      klachten.add('$pad staat niet in $checksumBestand.');
      continue;
    }
    final werkelijk = sha256
        .convert(File('${bundel.path}/$pad').readAsBytesSync())
        .toString();
    if (werkelijk != verwacht) {
      klachten.add('$pad wijkt af van $checksumBestand.');
    }
  }
  for (final pad in opgeschreven.keys) {
    klachten.add('$pad staat in $checksumBestand maar ligt niet in de bundel.');
  }
  return klachten;
}

/// Elk bestand in [bundel], als pad relatief aan de bundel, gesorteerd —
/// behalve de checksumlijst zelf.
///
/// Sorteren maakt de **volgorde** bepaald, zodat twee lijsten over dezelfde
/// bestanden regel voor regel te vergelijken zijn. Of twee builds van dezelfde
/// bron byte voor byte dezelfde inhoud opleveren — reproduceerbaarheid — is nu
/// getoetst: [normaliseerServiceWorkerVersie] haalt de enige *intrinsieke*
/// bouw-tot-bouw-variatie weg, en binnen een vaste bouwomgeving zijn de bestanden
/// die deze lijst dekt na `pak` per bestand identiek over schone builds heen
/// (#1027). Wat dat "vaste bouwomgeving" nog omvat — de native-assetslaag — en
/// waarom dit de bundelinhoud betreft en niet het tar.gz-omhulsel eromheen, staat
/// in `assurance/reproduceerbare-builds.md`.
List<String> bundelBestanden(Directory bundel) {
  final paden = <String>[];
  for (final entiteit in bundel.listSync(recursive: true)) {
    if (entiteit is! File) continue;
    // Relatief en met '/' als scheidingsteken; zie [relatiefIn] voor waarom
    // dat op Windows niet vanzelf goed gaat.
    final pad = relatiefIn(bundel, entiteit.path);
    if (pad == checksumBestand) continue;
    paden.add(pad);
  }
  paden.sort();
  return paden;
}
