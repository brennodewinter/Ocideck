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
import 'privacy_regions.dart';
import 'privacy_scanner.dart';

/// Bouwt en verifieert redactiemanifesten.
class RedactionManifestService {
  /// Regels die de gebruiker heeft uitgezet — die redigeren we niet, dus staan ze
  /// ook niet in het manifest.
  final Set<String> disabledRules;

  /// Idem voor de eigen gegevens van de gebruiker.
  final OwnIdentity ownIdentity;

  /// De landpakketten die aanstaan. Moet gelijk zijn aan wat
  /// [PrivacyProjection.forAudience] krijgt: het manifest beschrijft wat de
  /// projectie heeft weggelakt, dus een pakket dat hier wél en daar níet meetelt
  /// levert een entry voor een blok dat in de export niet staat. De ontvanger
  /// gaat dan zoeken naar een redactie die er niet is — precies het vertrouwen
  /// dat dit manifest hoort te vestigen.
  final Set<String> regions;

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
    this.regions = defaultPrivacyRegions,
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
    final values = redactedValues(deck, profile: profile);
    final salts = [for (final _ in values) _newSalt()];
    final commitments = [
      for (var i = 0; i < values.length; i++)
        commitmentFor(salt: salts[i], value: values[i].value),
    ];
    final idLength = shortUniqueIdLength(commitments);

    final entries = <RedactionEntry>[
      for (var i = 0; i < values.length; i++)
        RedactionEntry(
          id: commitments[i].substring(0, idLength),
          commitment: commitments[i],
          salt: salts[i],
          rule: values[i].finding.ruleId,
          slideIndex: values[i].finding.slideIndex,
          field: values[i].finding.field,
        ),
    ];
    return RedactionManifest(derivedFrom: deck.sealHash, entries: entries);
  }

  /// De kortste referentie die binnen dít manifest niemand dubbel aanwijst.
  ///
  /// Het id bestaat om één redactie in een gesprek aan te kunnen wijzen ("ik
  /// betwist redactie a3f1e2b7"). Dat werkt alleen als het er precies één
  /// aanwijst. Hier stonden vier hex-tekens: 65.536 mogelijkheden, en dus — het
  /// verjaardagsprobleem — bij ongeveer 300 redacties al een kans van één op
  /// twee dat er twee samenvallen. Een pentestrapport met 300 redacties is niet
  /// bijzonder, en dan wijst een betwisting naar twee dingen tegelijk.
  ///
  /// [kRedactionIdMinChars] is de ondergrond; wordt dat binnen dit manifest niet
  /// uniek, dan groeit de lengte tot het wel zo is. Eén lengte voor álle entries
  /// (zoals git zijn hashes afkort), want een lijst met ids van wisselende
  /// lengte leest slecht en nodigt uit tot verkeerd overtypen.
  ///
  /// Alleen uniciteit *binnen* een manifest telt: een betwisting gaat altijd
  /// over één document. Dat het commitment volledig meereist blijft de
  /// bewijslast — het id is de handgreep, niet het bewijs.
  static int shortUniqueIdLength(List<String> commitments) {
    for (
      var length = kRedactionIdMinChars;
      length < kCommitmentHexChars;
      length++
    ) {
      final seen = <String>{};
      var unique = true;
      for (final c in commitments) {
        if (!seen.add(c.substring(0, length))) {
          unique = false;
          break;
        }
      }
      if (unique) return length;
    }
    // Twee gelijke commitments betekenen twee gelijke (salt, waarde)-paren, en
    // salts zijn 128 willekeurige bits. Onbereikbaar, maar dan is de volledige
    // hash het enige eerlijke antwoord.
    return kCommitmentHexChars;
  }

  /// Elke waarde die de projectie op dit deck zou wegredigeren, in vaste
  /// volgorde (deckbreed, dan slide, dan bevinding). Eén bron van waarheid voor
  /// zowel het bouwen als het verifiëren van een manifest — anders lopen die
  /// twee uiteen.
  ///
  /// De `isRedactable`-poort is dezelfde als in `PrivacyProjection._byFragment`,
  /// en dat is geen detail. Zonder die poort telde het manifest ook de losse
  /// aanwijzingen mee — een deck met "de diagnose is nog niet gesteld" leverde
  /// twee entries op terwijl er nul blokken in de export stonden. De ontvanger
  /// zocht dan naar redacties die er niet zijn, en dat ondermijnt precies het
  /// vertrouwen dat het manifest hoort te vestigen.
  List<({PrivacyFinding finding, String value})> redactedValues(
    Deck deck, {
    PrivacyExportProfile profile = PrivacyExportProfile.full,
  }) {
    final scan = PrivacyScanner(
      disabledRules: disabledRules,
      ownIdentity: ownIdentity,
      regions: regions,
    ).scan(deck);
    final out = <({PrivacyFinding finding, String value})>[];

    // Eerst de deckbrede redacties. Die stonden hier niet, en dan had een ████
    // in het PDF-auteursveld of in de andere documentmetadata geen entry om te
    // betwisten: de ontvanger zag dát er iets weg was, maar had geen id om naar
    // te wijzen en geen commitment om tegen te toetsen. Ze komen vóór de dia's
    // omdat de projectie ze ook als eerste verwerkt — `verifyAgainstSource`
    // vergelijkt op positie, dus de volgorde is onderdeel van het contract.
    if (deck.privacy == PrivacyDisposition.redact ||
        profile == PrivacyExportProfile.redacted) {
      for (final finding in scan.findings.where(
        (f) => f.isDeckWide && f.isRedactable,
      )) {
        final value = _deckValueOf(deck, finding);
        if (value != null) out.add((finding: finding, value: value));
      }
    }

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

      for (final finding in scan.forSlide(i).where((f) => f.isRedactable)) {
        final value = _valueOf(slide, finding);
        if (value != null) out.add((finding: finding, value: value));
      }
    }
    return out;
  }

  /// De oorspronkelijke tekst achter een deckbrede bevinding.
  ///
  /// Dezelfde velden, dezelfde nummering en dezelfde volgorde als
  /// `PrivacyScannerFragments._deckFragments` en `PrivacyProjection._project`.
  /// Lopen die drie uiteen, dan committeert het manifest een andere tekst dan
  /// er is weggelakt — en dan faalt een eerlijke verificatie.
  String? _deckValueOf(Deck deck, PrivacyFinding finding) {
    final i = finding.fragmentIndex;
    final text = switch (finding.field) {
      'deckTitle' => deck.title,
      'author' => deck.author,
      'organization' => deck.organization,
      'description' => deck.description,
      'keywords' => deck.keywords,
      'version' => deck.version,
      'date' => deck.date,
      'standardsUsed' => _at(deck.standardsUsed, i),
      'toolsUsed' => _at(deck.toolsUsed.map((t) => t.name).toList(), i),
      'miauwWaivers' => _at(deck.miauwWaivers.values.toList(), i),
      'miauwConfirmations' => _at(deck.miauwConfirmations.values.toList(), i),
      _ => null,
    };
    return _span(text, finding);
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
      // Het scope-object van een checklist wordt sinds kort óók geredigeerd; de
      // mediapaden bewust niet (zie `PrivacyProjection._projectMedia`), dus
      // daar valt geen tekstbereik te committen.
      'checklistScope' => slide.checklistScope,
      _ => null,
    };
    return _span(text, finding);
  }

  /// De tekst achter een bevinding, of `null` als er niets te committen valt.
  ///
  /// Een leeg bereik is geen redactie. `struct.notes_leak` is zo'n bevinding:
  /// hij meldt *dát* er iets in de sprekersnotities staat en wijst met `[0,0)`
  /// nergens naar. Die kreeg hier een entry met het commitment over de lége
  /// string — een redactie die niet in het document staat, met een commitment
  /// dat iedereen in één regel kan naspelen. Precies het tegendeel van wat het
  /// manifest hoort te bewijzen.
  static String? _span(String? text, PrivacyFinding finding) {
    if (text == null) return null;
    if (finding.end > text.length) return null;
    if (finding.end <= finding.start) return null;
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
