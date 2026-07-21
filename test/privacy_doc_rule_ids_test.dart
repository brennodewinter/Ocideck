// Elk regel-id in een tabel in OCIWACHT.md bestaat, of staat als gepland te boek.
//
// De aanleiding was drift die niemand zag. De §3-D-tabel noemde het kenteken
// `contact.plate` en de buitenlandse postcode `contact.postcode_intl`; de code
// geeft ze uit als `nl.plate` en `<land>.postcode`. Die prefix is geen detail —
// `privacyRuleRegion` leidt het land uit de eerste twee letters af, en dát is
// wat de regel achter de regiopoort zet. Wie in de tabel `contact.plate`
// opzoekt vindt niets, en concludeert dat de regel niet bestaat.
//
// De omgekeerde toets (staat elk code-id in de documentatie?) is hier bewust
// niet gebouwd: die is vandaag groen en blijft dat, omdat elk id ergens in een
// routekaartregel staat. Hij zou dus geen drift meten maar alleen ruis geven.
//
// Wat deze test níét kan: hij leest tabellen, geen proza. Een zin als "nog niet
// gebouwd: X" blijft onbewaakt, want die claim heeft geen vorm om op te
// haken. Dat is een echte grens en geen omissie — zet een claim over wat er
// bestaat daarom liever in een tabel dan in een alinea.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/privacy/privacy_digital_rules.dart';
import 'package:ocideck/services/privacy/privacy_eu_rules.dart';
import 'package:ocideck/services/privacy/privacy_lexicon_data.dart';
import 'package:ocideck/services/privacy/privacy_plate_rules.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/privacy/privacy_secret_rules.dart';
import 'package:ocideck/services/privacy/privacy_structural_rules.dart';
import 'package:ocideck/services/privacy/privacy_world_rules.dart';

/// Regels die in de catalogus staan maar nog niet gebouwd zijn.
///
/// Deze lijst hoort te krimpen. Staat een id hier én in de code, dan is de test
/// rood: dat is het moment om hem eruit te halen, en het is precies het moment
/// waarop je het anders zou vergeten.
const Set<String> geplandeRegels = {
  // EU-landen waarvoor nog geen pakket is gebouwd, plus twee losse nummers in
  // landen die al wél een pakket hebben.
  'cy.id', 'lt.ak', 'lu.matricule', 'lv.pk', 'mt.id', 'de.svnr', 'es.nie',

  // Reis- en identiteitsdocumenten naast de gebouwde `doc.mrz`.
  'doc.passport_nl', 'doc.driving_licence', 'doc.residence',

  // Financieel: §3-C is deels gebouwd (`fin.iban`, `fin.pan`, `fin.cvv`).
  'fin.bic', 'fin.nl_bankrekening', 'fin.sepa_mandate', 'fin.salary',
  'fin.crypto_btc', 'fin.crypto_eth', 'fin.crypto_xmr',

  // Geheimen: alleen de `.env`-achtige toekenning ontbreekt nog.
  'secret.env_assignment',

  // Structureel: `struct.mailto`, `struct.url_*`, `struct.user_path` en
  // `struct.share_link` zijn gebouwd, deze vijf nog niet.
  'struct.exif', 'struct.filename', 'struct.frontmatter_author',
  'struct.remote_media', 'struct.strike_not_redaction',

  // Bulk: `bulk.quasi_combo` is gebouwd, k-anonimiteit nog niet.
  'bulk.k_anonymity',
};

// Hier stonden `sk.rodne_cislo` en `lt.ak` als "krijgt bewust nooit een eigen
// regel, staat hier zodat de tabelrij mag blijven bestaan". Die tabelrijen
// bestaan niet meer: `sharedRegionRules` maakt van `cz.rodne_cislo` en
// `ee.isikukood` regels die onder twéé landcodes vallen, en dát is nu wat er in
// OCIWACHT §3-A staat. Een uitzondering die niets meer uitzondert hoort weg —
// anders leest een volgende lezer hem als bewijs dat er nog iets open staat.

/// Wat een bestandsnaam is en geen regel-id.
const Set<String> _bestandsextensies = {'dart', 'md', 'json', 'yaml', 'yml'};

void main() {
  final repoWortel = Directory.current.path;
  final ontwerp = File('$repoWortel/docs/design/OCIWACHT.md');

  /// Alle regel-ids die de code werkelijk kan uitgeven.
  Set<String> codeRegelIds() {
    final ids = <String>{
      ...euIdentifierRules.map((r) => r.id),
      ...worldIdentifierRules.map((r) => r.id),
      ...secretRules.map((r) => r.id),
      ...structuralRules.map((r) => r.id),
      ...digitalRules.map((r) => r.id),
      ...contextualDigitalRules.map((r) => r.rule.id),
      ...intlPostcodeRules.map((r) => r.ruleId),
      // De art. 9-categorieën bestaan alleen als `category` op een
      // lexiconterm; er is geen lijst met `special.*` in de code.
      ...bundledPrivacyLexicon.map((e) => e.category),
    };

    // De hardgecodeerde detectoren staan in geen lijst; hun ids zijn literalen
    // in de bron. Een bronscan is hier eerlijker dan een tweede handmatige
    // lijst, want die zou precies zo uit de pas lopen als de tabellen deden.
    final literal = RegExp(r"\b(?:id|ruleId):\s*'([a-z0-9_]+\.[a-z0-9_]+)'");
    final privacyDir = Directory('$repoWortel/lib/services/privacy');
    for (final f in privacyDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        ids.add(m.group(1)!);
      }
    }
    return ids;
  }

  /// Regel-ids uit de eerste kolom van een markdowntabel.
  ///
  /// Alleen de eerste kolom, want daar staat het onderwerp van de rij. Verderop
  /// in een rij staan ids in toelichtende zin ("zelfde reden als `ca.sin`") en
  /// die zeggen niets over wat er bestaat.
  Set<String> tabelRegelIds() {
    final rij = RegExp(r'^\|\s*(`[a-z0-9_]+\.[a-z0-9_]+`(?:\s*/\s*)?)+\s*\|');
    final id = RegExp(r'`([a-z0-9_]+\.[a-z0-9_]+)`');
    final ids = <String>{};
    for (final regel in ontwerp.readAsLinesSync()) {
      if (!rij.hasMatch(regel)) continue;
      final eersteKolom = regel.split('|')[1];
      for (final m in id.allMatches(eersteKolom)) {
        // `privacy_checksums_test.dart` heeft dezelfde vorm als een regel-id.
        // De tabel met testbestanden is echte documentatie, dus filteren op
        // vorm is beter dan die tabel uitzonderen.
        if (_bestandsextensies.contains(m.group(1)!.split('.').last)) continue;
        ids.add(m.group(1)!);
      }
    }
    return ids;
  }

  test('het ontwerpdocument staat er en levert tabellen op', () {
    // Zonder ondergrens laat een hernoemd bestand of een gewijzigde tabelvorm
    // de test groen door er niets meer in te stoppen.
    expect(ontwerp.existsSync(), isTrue, reason: ontwerp.path);
    expect(tabelRegelIds().length, greaterThan(100));
    expect(codeRegelIds().length, greaterThan(60));
  });

  test('elk regel-id in een tabel bestaat, of staat als gepland te boek', () {
    final code = codeRegelIds();
    final onbekend =
        tabelRegelIds()
            .where((id) => !code.contains(id) && !geplandeRegels.contains(id))
            .toList()
          ..sort();

    expect(
      onbekend,
      isEmpty,
      reason:
          'deze ids staan in een tabel in OCIWACHT.md maar kent de code niet. '
          'Is de regel hernoemd, werk dan de tabel bij; moet hij nog gebouwd '
          'worden, zet hem dan in `geplandeRegels` in deze test.',
    );
  });

  test('geplande regels zijn ook echt nog niet gebouwd', () {
    final code = codeRegelIds();
    final gebouwd = geplandeRegels.where(code.contains).toList()..sort();

    expect(
      gebouwd,
      isEmpty,
      reason:
          'deze regels staan als gepland te boek maar bestaan al. Haal ze uit '
          '`geplandeRegels`, en controleer of de tabel in OCIWACHT.md ze onder '
          'de juiste naam noemt.',
    );
  });

  test('de regiopoort herkent het land van elk gebouwd regel-id', () {
    // De drift die deze test uitlokte ging over een prefix, dus toets die ook
    // rechtstreeks: een id dat met een bekende landcode begint hoort achter de
    // regiopoort te vallen, en een id dat dat niet doet hoort altijd te draaien.
    for (final id in codeRegelIds()) {
      final regio = privacyRuleRegion(id);
      if (regio == null) continue;
      expect(
        defaultPrivacyRegions,
        contains(regio),
        reason: 'regel $id hangt aan regio $regio, en die staat in geen pakket',
      );
    }
  });
}
