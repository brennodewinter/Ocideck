// Het bouwen en controleren van een redactiemanifest.
//
// Los van de projectie, en dat is opzettelijk. De projectie draait bij élke
// render — preview, thumbnail, presenter — en moet dus puur en deterministisch
// zijn. Zou zij salts genereren, dan gaf ze bij elke frame een ander resultaat en
// zou de preview blijven herbouwen.
//
// Het manifest wordt daarom één keer gemaakt: bij export.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../models/deck.dart';
import '../../models/privacy_disposition.dart';
import '../../models/privacy_finding.dart';
import '../../models/redaction_manifest.dart';
import '../../models/slide.dart';
import 'privacy_own_identity.dart';
import 'privacy_scanner.dart';

/// Bouwt en verifieert redactiemanifesten.
class RedactionManifestService {
  /// Regels die de gebruiker heeft uitgezet — die redigeren we niet, dus staan ze
  /// ook niet in het manifest.
  final Set<String> disabledRules;

  /// Idem voor de eigen gegevens van de gebruiker.
  final OwnIdentity ownIdentity;

  /// Injecteerbaar voor de test; standaard een cryptografisch veilige bron.
  ///
  /// De salt is geen decoratie: zonder salt is een SHA-256 van een geredigeerd
  /// BSN in seconden terug te rekenen (10⁹ kandidaten), en dan publiceer je
  /// precies wat je zojuist hebt weggelakt.
  final Random _random;

  RedactionManifestService({
    Random? random,
    this.disabledRules = const {},
    this.ownIdentity = OwnIdentity.empty,
  }) : _random = random ?? Random.secure();

  /// Bouwt het manifest voor [deck]: één entry per redactie die de projectie op
  /// dit deck zou toepassen.
  ///
  /// Het resultaat draagt de salts. Gebruik [RedactionManifest.withoutSalts]
  /// voor het exemplaar dat bij de geredigeerde versie hoort.
  RedactionManifest build(
    Deck deck, {
    PrivacyExportProfile profile = PrivacyExportProfile.full,
  }) {
    final entries = <RedactionEntry>[];
    for (final r in redactedValues(deck, profile: profile)) {
      final salt = _newSalt();
      final commitment = commitmentFor(salt: salt, value: r.value);
      entries.add(
        RedactionEntry(
          // Vier hex-tekens zijn genoeg om één redactie in een gesprek aan te
          // wijzen ("ik betwist redactie a3f1") en te weinig om iets te verraden.
          id: commitment.substring(0, 4),
          commitment: commitment,
          salt: salt,
          rule: r.finding.ruleId,
          slideIndex: r.finding.slideIndex,
          field: r.finding.field,
        ),
      );
    }
    return RedactionManifest(derivedFrom: deck.sealHash, entries: entries);
  }

  /// Elke waarde die de projectie op dit deck zou wegredigeren, in vaste
  /// volgorde (slide, dan bevinding). Eén bron van waarheid voor zowel het
  /// bouwen als het verifiëren van een manifest — anders lopen die twee uiteen.
  List<({PrivacyFinding finding, String value})> redactedValues(
    Deck deck, {
    PrivacyExportProfile profile = PrivacyExportProfile.full,
  }) {
    final scan = PrivacyScanner(
      disabledRules: disabledRules,
      ownIdentity: ownIdentity,
    ).scan(deck);
    final out = <({PrivacyFinding finding, String value})>[];

    for (var i = 0; i < deck.slides.length; i++) {
      final slide = deck.slides[i];
      final disposition = effectivePrivacyDisposition(
        deck: deck.privacy,
        slide: slide.privacy,
      );
      // In het geredigeerde profiel gaat alles eruit, ongeacht wat de auteur voor
      // de zaal heeft besloten.
      final redactAll = profile == PrivacyExportProfile.redacted;
      if (!redactAll && disposition != PrivacyDisposition.redact) continue;

      for (final finding in scan.forSlide(i)) {
        final value = _valueOf(slide, finding);
        if (value != null) out.add((finding: finding, value: value));
      }
    }
    return out;
  }

  String _newSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// De oorspronkelijke tekst die achter een bevinding zit. Puur uit de bron —
  /// het manifest bewaart hem nooit, alleen zijn commitment.
  String? _valueOf(Slide slide, PrivacyFinding finding) {
    final text = switch (finding.field) {
      'title' => slide.title,
      'subtitle' => slide.subtitle,
      'columnTitle1' => slide.columnTitle1,
      'columnTitle2' => slide.columnTitle2,
      'imageCaption' => slide.imageCaption,
      'imageCaption2' => slide.imageCaption2,
      'imageAltText' => slide.imageAltText,
      'imageAltText2' => slide.imageAltText2,
      'quote' => slide.quote,
      'quoteAuthor' => slide.quoteAuthor,
      'customMarkdown' => slide.customMarkdown,
      'notes' => slide.notes,
      'bullets' => _at(slide.bullets, finding.fragmentIndex),
      'bullets2' => _at(slide.bullets2, finding.fragmentIndex),
      'tableRows' => _tableCell(slide, finding.fragmentIndex),
      _ => null,
    };
    if (text == null) return null;
    if (finding.end > text.length) return null;
    return text.substring(finding.start, finding.end);
  }

  String? _at(List<String> list, int index) =>
      index >= 0 && index < list.length ? list[index] : null;

  /// De cel achter een vlakke index, met dezelfde staplengte als de scanner en
  /// de projectie: de bréédste rij. Zocht dit met `row.length` per rij, dan wees
  /// een index bij een tabel met ongelijke rijen naar een andere cel dan waar de
  /// bevinding vandaan kwam — en dan viel de redactie stil uit het manifest,
  /// omdat de teruggerekende tekst niet meer klopte.
  String? _tableCell(Slide slide, int flatIndex) {
    final stride = slide.tableRows.fold<int>(
      0,
      (m, r) => r.length > m ? r.length : m,
    );
    if (stride == 0) return null;
    final r = flatIndex ~/ stride;
    final c = flatIndex % stride;
    if (r >= slide.tableRows.length) return null;
    final row = slide.tableRows[r];
    return c < row.length ? row[c] : null;
  }

  /// Het commitment: SHA-256 over salt en waarde.
  ///
  /// De NUL-byte is een domeinscheider: hij kan niet in de salt (base64url) en
  /// niet in de waarde voorkomen, dus `salt‖waarde` is ondubbelzinnig. Zonder
  /// scheider zouden ('ab', 'c') en ('a', 'bc') hetzelfde commitment geven.
  /// Geschreven als escape — een rauwe control-byte maakt het bestand binair
  /// voor grep en onreviewbaar in een diff.
  static String commitmentFor({required String salt, required String value}) =>
      sha256.convert(utf8.encode('$salt\u0000$value')).toString();

  /// Controleert één betwiste redactie.
  ///
  /// Dit is **selectieve openbaarmaking**: de auteur onthult alleen díé salt en
  /// díé waarde, en bewijst daarmee dat redactie `#a3f1` precies dat verborg —
  /// zonder één van de andere redacties prijs te geven. Precies wat een derde
  /// partij nodig heeft die één bevinding wil natrekken zonder het hele rapport
  /// ongeredigeerd te krijgen.
  static bool verifyEntry(
    RedactionEntry entry, {
    required String salt,
    required String value,
  }) => commitmentFor(salt: salt, value: value) == entry.commitment;

  /// Controleert of [manifest] een eerlijke afleiding is van [source].
  ///
  /// Voor wie beide versies heeft: elke entry moet terug te rekenen zijn uit de
  /// bron, en er mogen er niet meer of minder zijn dan de bron oplevert. Zo valt
  /// zowel een toegevoegde als een weggelaten redactie op.
  ///
  /// [profile] moet hetzelfde zijn als waarmee het manifest gebouwd is. Een
  /// geredigeerd exemplaar bevat immers méér redacties dan een volledig, en
  /// tegen de verkeerde lat leggen zou een eerlijk manifest ten onrechte
  /// verdacht maken.
  bool verifyAgainstSource(
    RedactionManifest manifest,
    Deck source, {
    PrivacyExportProfile profile = PrivacyExportProfile.full,
  }) {
    // Zonder salts valt er niets na te rekenen. Dat is precies de bedoeling van
    // het exemplaar dat bij de geredigeerde versie hoort — dus dit is geen fout,
    // maar wel een "nee".
    if (!manifest.carriesSalts) return false;

    final actual = redactedValues(source, profile: profile);
    // Een toegevoegde óf weggelaten redactie valt hiermee allebei op.
    if (actual.length != manifest.entries.length) return false;

    for (var i = 0; i < manifest.entries.length; i++) {
      final claimed = manifest.entries[i];
      final real = actual[i];
      if (claimed.rule != real.finding.ruleId) return false;
      if (claimed.slideIndex != real.finding.slideIndex) return false;
      if (claimed.field != real.finding.field) return false;
      if (!verifyEntry(claimed, salt: claimed.salt, value: real.value)) {
        return false;
      }
    }
    return true;
  }
}
