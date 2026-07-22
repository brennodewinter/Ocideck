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
const List<String> nietUitleveren = ['.last_build_id'];

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

  File(
    '${bundel.path}/$checksumBestand',
  ).writeAsStringSync(checksumLijst(bundel));
  return const [];
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
/// bron byte voor byte hetzelfde opleveren is een andere vraag —
/// reproduceerbaarheid — en die is hier niet getoetst en wordt hier niet
/// beweerd.
List<String> bundelBestanden(Directory bundel) {
  final voorvoegsel = '${bundel.path}/';
  final paden = <String>[];
  for (final entiteit in bundel.listSync(recursive: true)) {
    if (entiteit is! File) continue;
    final pad = entiteit.path.startsWith(voorvoegsel)
        ? entiteit.path.substring(voorvoegsel.length)
        : entiteit.path;
    if (pad == checksumBestand) continue;
    paden.add(pad);
  }
  paden.sort();
  return paden;
}
