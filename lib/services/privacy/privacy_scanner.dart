// De privacyscanner: leest een deck na op gegevens die privacygevoelig kunnen
// zijn.
//
// Twee dingen sturen het ontwerp:
//
// 1. Vals-positieven zijn duurder dan vals-negatieven. Een scanner die bij elk
//    ordernummer "BSN!" roept, wordt uitgezet — en detecteert daarna niets meer.
//    Vandaar checksums (privacy_checksums.dart), een registry van nepwaarden
//    (privacy_allowlist.dart) en contextpoorten waar de checksum te zwak is.
//
// 2. De scanner is een hulpmiddel, geen garantie. Hij vindt geen tekst in
//    afbeeldingen, geen gegevens in gelinkte bestanden, en geen gevoelige
//    informatie zonder herkenbaar patroon. Een slide zonder meldingen is een
//    slide waarin WIJ niets hebben gevonden.
//
// De scan is puur en synchroon: dezelfde slide geeft altijd dezelfde bevindingen.

import '../../models/deck.dart';
import '../../models/privacy_finding.dart';
import '../../models/privacy_lexicon.dart';
import '../../models/slide.dart';
import 'privacy_allowlist.dart';
import 'privacy_bulk_rules.dart';
import 'privacy_checksums.dart';
import 'privacy_context_role.dart';
import 'privacy_contact_rules.dart';
import 'privacy_digital_rules.dart';
import 'privacy_document_rules.dart';
import 'privacy_eu_rules.dart';
import 'privacy_bulk_lexicon.dart';
import 'privacy_lexicon_data.dart';
import 'privacy_location_rules.dart';
import 'privacy_own_identity.dart';
import 'privacy_regions.dart';
import 'privacy_phone_rules.dart';
import 'privacy_plate_rules.dart';
import 'privacy_special_rules.dart';
import 'privacy_structural_rules.dart';
import 'privacy_secret_rules.dart';

part 'privacy_scanner_detectors.dart';

/// Eén tekstfragment van een slide, met de veldnaam waar het uit komt.
typedef _Fragment = ({String field, int index, String text});

/// Hoe ver een contextwoord vóór een treffer mag staan om nog te tellen.
///
/// Ruim genoeg voor "Het burgerservicenummer van betrokkene is 123456782", krap
/// genoeg dat een woord elders in de zin niet meetelt.
const int kContextWindow = 40;

/// Het gewicht waarmee een term uit de gebundelde bronnen meedoet.
///
/// Maximaal, want zo'n term ís het gegeven waar een signaalwoord alleen naar
/// wijst: `taaislijmziekte` tegenover `diagnose`, `katholicisme` tegenover
/// `geloofsovertuiging`. Zie `privacy_bulk_lexicon.dart` voor de metingen die
/// dat rechtvaardigen.
const int _kBulkTermWeight = 5;

/// Contextwoorden die van een 11-proef-treffer een echte BSN-melding maken.
/// Zonder een van deze blijft de treffer informatief — zie [_scanBsn].
const List<String> bsnContextWords = [
  'bsn',
  'burgerservicenummer',
  'burgerservice',
  'sofinummer',
  'sofi-nummer',
  'sofinr',
];

final _reEmail = RegExp(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}");

/// Een IBAN staat vaak met spaties in een tekst. We accepteren die en
/// normaliseren pas in de validatie.
final _reIban = RegExp(r'\b[A-Z]{2}\d{2}(?:[ -]?[A-Z0-9]){10,30}\b');

/// Negen losstaande cijfers. Bewust ruim: de 11-proef en de contextpoort doen
/// het filterwerk, niet de regex.
final _reNineDigits = RegExp(r'(?<!\d)\d{9}(?!\d)');

/// Leest een deck na op privacygevoelige gegevens.
class PrivacyScanner {
  /// Regels die de gebruiker heeft uitgezet.
  ///
  /// Een uitgezette regel vuurt niet, nergens — óók niet bij redactie. Dat is een
  /// ander soort keuze dan de hoofdschakelaar, en het onderscheid is belangrijk:
  ///
  ///   * de hoofdschakelaar zegt "val me niet lastig". Dat is geen oordeel over de
  ///     inhoud, dus een deck met `privacy: redact` blijft gewoon redigeren;
  ///   * een uitgezette regel zegt "deze regel heeft het mís over mijn inhoud".
  ///     Dat ís een oordeel over de inhoud, en het honoreren ervan betekent dat we
  ///     hem ook niet mogen wegredigeren. Iemand die `nl.bsn` uitzet omdat zijn
  ///     ordernummers erop afgaan, wil die ordernummers niet zwart in zijn export.
  final Set<String> disabledRules;

  /// De eigen gegevens van de gebruiker: naam, e-mailadres, telefoonnummer,
  /// organisatiedomein.
  ///
  /// De grootste praktische vals-positieven-bron is de auteur zelf — zijn adres
  /// in de footer, zijn naam op de titelslide. Dat is geen bevinding maar de
  /// afzender.
  final OwnIdentity ownIdentity;

  /// De landpakketten die aan staan (OCIWACHT §5.7, §7).
  ///
  /// Alleen regels met een landcode in hun id kijken hiernaar; de universele
  /// laag — IBAN, e-mail, secrets, MRZ, digitale identificatoren — draait
  /// altijd. Zie `privacy_regions.dart` voor waarom het standaardpakket heel
  /// Europa is en niet alleen het thuisland.
  final Set<String> regions;

  const PrivacyScanner({
    this.disabledRules = const {},
    this.ownIdentity = OwnIdentity.empty,
    this.regions = defaultPrivacyRegions,
  });

  /// Scant het hele deck. Deckbrede velden (titel, auteur, trefwoorden) krijgen
  /// [kDeckWidePrivacyIndex].
  PrivacyScanResult scan(Deck deck) {
    final findings = <PrivacyFinding>[];

    final deckFindings = <PrivacyFinding>[];
    for (final fragment in _deckFragments(deck)) {
      _scanFragment(fragment, kDeckWidePrivacyIndex, deckFindings);
    }
    findings.addAll(_enabled(deckFindings));
    for (var i = 0; i < deck.slides.length; i++) {
      final slideFindings = <PrivacyFinding>[];
      final fragments = _slideFragments(deck.slides[i]).toList();
      for (final fragment in fragments) {
        _scanFragment(fragment, i, slideFindings);
      }
      final enabled = _escalateSpecialCategories(
        _enabled(slideFindings),
        _textsOf(fragments),
      );
      findings.addAll(enabled);
      // De massa-bevinding komt bovenóp de losse: veertig e-mailadressen zijn
      // veertig bevindingen én één ledenlijst, en die tweede is de melding waar
      // het om gaat.
      findings.addAll(
        _enabled(bulkFindingsFor(deck.slides[i], i, enabled).toList()),
      );
    }
    return PrivacyScanResult(findings);
  }

  /// Scant één slide los — voor de per-slide memoisatie in de provider.
  PrivacyScanResult scanSlide(Slide slide, int index) {
    final findings = <PrivacyFinding>[];
    final fragments = _slideFragments(slide).toList();
    for (final fragment in fragments) {
      _scanFragment(fragment, index, findings);
    }
    final enabled = _escalateSpecialCategories(
      _enabled(findings),
      _textsOf(fragments),
    );
    return PrivacyScanResult([
      ...enabled,
      ..._enabled(bulkFindingsFor(slide, index, enabled).toList()),
    ]);
  }

  /// Uitgezette regels en uitgeschakelde landpakketten eruit.
  ///
  /// Vóór de escalatie, zodat een uitgezette identificator ook geen bijzonder
  /// gegeven meer omhoog trekt. Dat geldt voor beide filters om dezelfde reden:
  /// wie het Poolse pakket uitzet, wil geen PESEL-melding en wil er ook geen
  /// diagnose door zien escaleren.
  List<PrivacyFinding> _enabled(List<PrivacyFinding> findings) {
    return [
      for (final f in findings)
        if (!disabledRules.contains(f.ruleId) &&
            privacyRuleInRegions(f.ruleId, regions))
          f,
    ];
  }

  /// De co-occurrence-escalator (OCIWACHT §5.6).
  ///
  /// Een trefwoord als "diagnose" of "verdachte" meldt op zichzelf niets dat de
  /// gebruiker onderbreekt — een slide *óver* de AVG noemt die woorden nu eenmaal,
  /// en een privacyles die alarm slaat is binnen een dag uitgezet.
  ///
  /// Staat er op dezelfde slide óók een gegeven dat één persoon aanwijst, dan is
  /// het bijzondere gegeven herleidbaar tot een persoon — en dát is precies wat
  /// artikel 9 beschermt. Dán pas gaat de melding omhoog.
  ///
  /// De poort kent daarvoor twee koppelingsroutes, en ze reiken bewust niet even
  /// ver:
  ///
  ///   * een **identificator** (BSN, nationaal nummer, e-mailadres) koppelt
  ///     slidebreed — een slide is klein genoeg dat "er staat hier iemand" opgaat;
  ///   * een **naam** koppelt alleen binnen zijn eigen mededeling. Een naam is
  ///     geen identificator maar een toeschrijving, en die reikt tot het einde van
  ///     de zin. Zie [nameLinkReaches] voor wat er misging zonder die grens.
  ///
  /// En dan verbreedt de escalatie ook het **bereik**, niet alleen de zekerheid.
  /// Zodra het bijzondere gegeven herleidbaar is tot een persoon, is het gegeven
  /// de hele mededeling — zie [statementSpan]. Daarom heeft deze functie de
  /// fragmenttekst nodig: zonder die tekst weet ze niet waar de mededeling begint
  /// en eindigt.
  List<PrivacyFinding> _escalateSpecialCategories(
    List<PrivacyFinding> findings,
    Map<String, String> fragmentTexts,
  ) {
    if (!findings.any((f) => f.family == PrivacyFamily.specialCategory)) {
      return findings;
    }
    final slideWideLink = findings.any(identifiesAPerson);
    final names = [
      for (final f in findings)
        if (namesAPerson(f)) f,
    ];
    if (!slideWideLink && names.isEmpty) return findings;

    return [
      for (final f in findings)
        if (f.family == PrivacyFamily.specialCategory)
          _escalateIfLinked(f, names, slideWideLink, fragmentTexts)
        else
          f,
    ];
  }

  PrivacyFinding _escalateIfLinked(
    PrivacyFinding finding,
    List<PrivacyFinding> names,
    bool slideWideLink,
    Map<String, String> fragmentTexts,
  ) {
    final text =
        fragmentTexts['${finding.field}:${finding.fragmentIndex}'] ?? '';
    final linked =
        slideWideLink ||
        names.any((name) => nameLinkReaches(name, finding, text));
    return linked ? _escalate(finding, text) : finding;
  }

  PrivacyFinding _escalate(PrivacyFinding finding, String text) {
    if (text.isEmpty) return finding;
    final span = statementSpan(text, finding.start, finding.end);
    return finding.escalated(start: span.start, end: span.end);
  }

  /// De tekst van elk fragment, opzoekbaar met dezelfde sleutel als de bevinding.
  Map<String, String> _textsOf(Iterable<_Fragment> fragments) => {
    for (final f in fragments) '${f.field}:${f.index}': f.text,
  };

  void _scanFragment(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    if (fragment.text.isEmpty) return;
    _scanEmail(fragment, slideIndex, out);
    _scanPhone(fragment, slideIndex, out);
    _scanIban(fragment, slideIndex, out);
    _scanBsn(fragment, slideIndex, out);
    _scanMrz(fragment, slideIndex, out);
    _scanDigital(fragment, slideIndex, out);
    _scanBirthdate(fragment, slideIndex, out);
    _scanGeo(fragment, slideIndex, out);
    _scanPlateAndIntlPostcode(fragment, slideIndex, out);
    _scanSecrets(fragment, slideIndex, out);
    _scanEuIdentifiers(fragment, slideIndex, out);
    _scanSpecialCategories(fragment, slideIndex, out);
    _scanAddress(fragment, slideIndex, out);
    _scanName(fragment, slideIndex, out);
    _scanStructural(fragment, slideIndex, out);
  }

  // ── contact.address / contact.postcode_nl ─────────────────────────────────

  /// Straat-met-huisnummer en Nederlandse postcode.
  ///
  /// Elk voor zich blijft `possible`: een postcode is vaak een kantooradres, een
  /// straat-met-nummer kan een verwijzing zijn. Staan ze binnen
  /// [kAddressLocationWindow] tekens van elkaar, dan wijzen ze samen één woonadres
  /// aan — postcode plus huisnummer is in Nederland vrijwel uniek identificerend —
  /// en gaan beide naar `certain`. Zie `privacy_contact_rules.dart`.
  void _scanAddress(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    final text = fragment.text;
    final addresses = streetAddressPattern.allMatches(text).toList();
    final postcodes = [
      for (final m in dutchPostcodePattern.allMatches(text))
        if (postcodeBoundaryOk(text, m.start) &&
            isPlausibleDutchPostcode(m.group(0)!))
          m,
    ];
    if (addresses.isEmpty && postcodes.isEmpty) return;

    for (final address in addresses) {
      final confirmed = postcodes.any((p) => _within(address, p));
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          address,
          ruleId: 'contact.address',
          family: PrivacyFamily.contact,
          confidence: confirmed
              ? PrivacyConfidence.certain
              : PrivacyConfidence.possible,
        ),
      );
    }
    for (final postcode in postcodes) {
      final confirmed = addresses.any((a) => _within(a, postcode));
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          postcode,
          ruleId: 'contact.postcode_nl',
          family: PrivacyFamily.contact,
          confidence: confirmed
              ? PrivacyConfidence.certain
              : PrivacyConfidence.possible,
        ),
      );
    }
  }

  /// Staan twee treffers binnen [kAddressLocationWindow] tekens van elkaar?
  bool _within(Match a, Match b) {
    final gap = a.start >= b.end
        ? a.start - b.end
        : (b.start >= a.end ? b.start - a.end : 0);
    return gap <= kAddressLocationWindow;
  }

  // ── contact.name ──────────────────────────────────────────────────────────

  /// Een persoonsnaam die de structuur aanwijst — nooit via NER.
  ///
  /// Vier poorten, en geen ervan kijkt naar de naam zélf: een woord met een
  /// hoofdletter blijft een woord met een hoofdletter. Wat telt is wat eromheen
  /// staat.
  ///
  ///   * een **label** (`naam:`, `contactpersoon:`) of een **aanhef** (`dhr.`,
  ///     `Dr.`) → `likely`. De auteur schrijft er letterlijk bij dat dit een
  ///     persoon is; dat is een structurele uitspraak, geen gok;
  ///   * een **persoonspredicaat** ("wordt verdacht van", "meldde zich ziek") →
  ///     `likely`. Dit is de formulering waar artikel 10 over gaat en die geen
  ///     label draagt;
  ///   * een **bevestigend e-mailadres** ("Marieke de Vries" naast
  ///     `m.devries@acme.nl`) → `certain`. Twee onafhankelijke structuren die
  ///     elkaar bevestigen is het sterkste bewijs dat deze familie kent.
  ///
  /// `certain` blijft daarmee voorbehouden aan gevallen met een tweede,
  /// onafhankelijke bevestiging — precies zoals een checksum dat elders doet.
  /// De kale naam zonder één van deze structuren valt hier buiten; daarvoor is de
  /// handmatige `[[…]]`-markering.
  void _scanName(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    final text = fragment.text;
    final seen = <int>{};

    void emitName(int start, int end, PrivacyConfidence confidence) {
      final name = text.substring(start, end);
      if (name.isEmpty) return;
      if (isPlaceholderPerson(name)) return;
      if (ownIdentity.covers(name)) return;
      if (!seen.add(start)) return;
      out.add(
        PrivacyFinding(
          ruleId: 'contact.name',
          family: PrivacyFamily.contact,
          confidence: confidence,
          slideIndex: slideIndex,
          field: fragment.field,
          fragmentIndex: fragment.index,
          start: start,
          end: end,
          maskedSample: maskValue(name),
        ),
      );
    }

    // De e-mailbevestiging eerst: die levert de hoogste zekerheid, en `seen`
    // zorgt dat een label eromheen hem daarna niet terugzet naar `likely`.
    _scanEmailConfirmedNames(text, emitName);

    for (final pattern in [nameLabelPattern, nameSalutationPattern]) {
      for (final match in pattern.allMatches(text)) {
        final name = match.group(1);
        if (name == null || name.isEmpty) continue;
        // De naam staat aan het eind van de match; daaruit volgt zijn positie
        // zonder dat we een groepsoffset nodig hebben (die Dart niet los geeft).
        emitName(match.end - name.length, match.end, PrivacyConfidence.likely);
      }
    }

    // Bij het predicaat staat de naam juist vooraan: `match.start`.
    for (final match in namePredicatePattern.allMatches(text)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) continue;
      emitName(
        match.start,
        match.start + name.length,
        PrivacyConfidence.likely,
      );
    }
  }

  /// Namen die door een e-mailadres in dezelfde tekst bevestigd worden.
  ///
  /// Dit is de enige plek waar het kandidaat-naampatroon losgelaten wordt op
  /// vrije tekst, en dat mag alleen omdat er meteen een harde bevestiging
  /// tegenover staat: het lokale deel van een adres in dezelfde tekst moet de
  /// naam terugzeggen. Zonder dat adres komt er niets uit — het patroon matcht
  /// namelijk ook het eerste woord van elke zin.
  void _scanEmailConfirmedNames(
    String text,
    void Function(int start, int end, PrivacyConfidence confidence) emit,
  ) {
    if (!text.contains('@')) return;
    final emails = [
      for (final m in _reEmail.allMatches(text))
        if (!isPlaceholderEmail(m.group(0)!)) m.group(0)!,
    ];
    if (emails.isEmpty) return;

    for (final candidate in nameCandidatePattern.allMatches(text)) {
      final name = candidate.group(0)!;
      if (!name.contains(' ')) continue; // één token bevestigt niets
      if (emails.any((email) => emailConfirmsName(email, name))) {
        emit(candidate.start, candidate.end, PrivacyConfidence.certain);
      }
    }
  }

  // ── Structurele lekken ────────────────────────────────────────────────────

  /// Gebruikerspaden, tokens in URL's, deellinks, mailto's, data-URI's.
  ///
  /// De familie die generieke PII-scanners missen: dit zijn geen persoonsgegevens
  /// in de tekst, maar ze lekken er wel. Een gebruikerspad in een
  /// afbeeldingsverwijzing verraadt gewoon een naam.
  void _scanStructural(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final rule in structuralRules) {
      for (final match in rule.pattern.allMatches(fragment.text)) {
        if (rule.validate != null && !rule.validate!(match)) {
          continue;
        }
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: rule.id,
            family: PrivacyFamily.structural,
            confidence: rule.confidence,
          ),
        );
      }
    }

    // Een data-URI kunnen we niet inkijken. Dat is geen bevinding maar een
    // eerlijke mededeling: dit stuk deck is voor ons onzichtbaar, en de gebruiker
    // mag niet in de waan blijven dat we alles hebben gezien.
    for (final match in dataUriPattern.allMatches(fragment.text)) {
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'struct.data_uri',
          family: PrivacyFamily.structural,
          confidence: PrivacyConfidence.possible,
        ),
      );
    }
  }

  // ── Europese identificatienummers ─────────────────────────────────────────

  /// De landpakketten (`privacy_eu_rules.dart`).
  ///
  /// Ruim twintig van de dertig Europese nummers zijn zelfvalidereend, en een
  /// checksum kóst geen precisie — hij wínt precisie. Daarom mogen ze allemaal
  /// aan staan. De handvol zonder bruikbare checksum draagt een contextwoordeis,
  /// precies zoals het BSN, en komt nooit hoger dan `likely`.
  void _scanEuIdentifiers(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final rule in euIdentifierRules) {
      for (final match in rule.pattern.allMatches(fragment.text)) {
        final value = match.group(0)!;
        if (rule.validate != null && !rule.validate!(value)) continue;

        // Vraagt de regel om context, dan is die verplicht. Dat geldt voor de
        // nummers zonder bruikbare checksum (Brits NINO) en voor de nummers
        // waarvan de checksum te zwak is om alleen op af te gaan — tien cijfers
        // met een Luhn is óók een klantnummer.
        if (rule.contextWords.isNotEmpty &&
            !_hasContextWord(fragment.text, match.start, rule.contextWords)) {
          continue;
        }

        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: rule.id,
            family: PrivacyFamily.identifier,
            confidence: rule.confidence,
          ),
        );
      }
    }
  }

  // ── secret.* ──────────────────────────────────────────────────────────────

  /// Leverancierstokens (prefix = bewijs), private keys, JWT's, connection
  /// strings, en wachtwoorden in klare taal.
  ///
  /// Data-gedreven: de regels staan in `privacy_secret_rules.dart`, zodat een
  /// nieuwe leverancier één regel in een tabel is en niet een tak in deze functie.
  void _scanSecrets(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final rule in secretRules) {
      for (final match in rule.pattern.allMatches(fragment.text)) {
        final value = match.group(0)!;
        if (isPlaceholderSecret(value)) continue;
        if (rule.validate != null && !rule.validate!(value)) continue;
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: rule.id,
            family: PrivacyFamily.secret,
            confidence: PrivacyConfidence.certain,
          ),
        );
      }
    }

    // Een wachtwoord in klare taal. De waarde erachter beslist: een slide die
    // uitlegt hóé je een sleutel invult (`api_key: <your-key>`) mag niet afgaan.
    for (final match in secretAssignment.allMatches(fragment.text)) {
      final value = match.group(1)!;
      if (isPlaceholderSecret(value)) continue;
      // Een al gevonden leverancierstoken niet dubbel melden.
      if (out.any(
        (f) =>
            f.family == PrivacyFamily.secret &&
            f.field == fragment.field &&
            f.fragmentIndex == fragment.index &&
            f.start >= match.start &&
            f.end <= match.end,
      )) {
        continue;
      }
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'secret.password_plain',
          family: PrivacyFamily.secret,
          confidence: PrivacyConfidence.likely,
        ),
      );
    }
  }

  // ── contact.email ─────────────────────────────────────────────────────────

  void _scanEmail(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    if (!fragment.text.contains('@')) return;
    for (final match in _reEmail.allMatches(fragment.text)) {
      final address = match.group(0)!;
      if (isPlaceholderEmail(address)) continue;
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'contact.email',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }
  }

  // ── contact.phone ─────────────────────────────────────────────────────────

  /// Drie poorten, van streng naar soepel — zie `privacy_phone_rules.dart`.
  ///
  /// Alleen de internationale vorm wordt `certain`: een tóégekend landnummer plus
  /// een geldige E.164-lengte is een structurele validatie, niet een gok. De
  /// nationale vorm mist dat bewijs en blijft `likely`; een kale cijferreeks
  /// vuurt zonder contextwoord helemaal niet, want dan is ze niet te
  /// onderscheiden van een oud bankrekeningnummer.
  ///
  /// `contact.phone` telt bewust **niet** mee voor [identifiesAPerson]. Een
  /// telefoonnummer identificeert een persoon net zo goed als een e-mailadres,
  /// maar het staat vaker op een slide als *organisatienummer* — en dan zou een
  /// HR-slide met het centrale nummer en het woord "ziekteverzuim" onterecht
  /// escaleren tot een bijzonder persoonsgegeven.
  void _scanPhone(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final match in e164Pattern.allMatches(fragment.text)) {
      if (!isValidE164(match.group(0)!)) continue;
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'contact.phone',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }

    for (final match in nationalPhonePattern.allMatches(fragment.text)) {
      final raw = match.group(0)!;
      if (!isPlausibleNationalPhone(raw)) continue;
      if (!hasPhoneSeparator(raw) &&
          !_hasContextWord(fragment.text, match.start, phoneContextWords)) {
        continue;
      }
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'contact.phone',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.likely,
        ),
      );
    }
  }

  // ── fin.iban ──────────────────────────────────────────────────────────────

  void _scanIban(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    for (final match in _reIban.allMatches(fragment.text)) {
      final candidate = match.group(0)!;
      if (!isValidIban(candidate)) continue;
      if (isExampleIban(candidate)) continue;
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'fin.iban',
          family: PrivacyFamily.financial,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }
  }

  // ── doc.mrz ───────────────────────────────────────────────────────────────

  /// De machine-readable zone van een paspoort of identiteitskaart.
  ///
  /// Geen contextpoort, geen nabijheidseis, meteen `certain`: vier
  /// controlecijfers waarvan er één over de andere heen ligt, laten gewone tekst
  /// niet door. En de betekenis rechtvaardigt het — dit is geen los
  /// persoonsgegeven maar een gescand identiteitsbewijs, met documentnummer,
  /// nationaliteit, geboortedatum en vervaldatum in één blok.
  void _scanMrz(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    for (final zone in findMrzZones(fragment.text)) {
      final value = fragment.text.substring(zone.start, zone.end);
      if (ownIdentity.covers(value)) continue;
      out.add(
        PrivacyFinding(
          ruleId: 'doc.mrz',
          family: PrivacyFamily.identifier,
          confidence: PrivacyConfidence.certain,
          slideIndex: slideIndex,
          field: fragment.field,
          fragmentIndex: fragment.index,
          start: zone.start,
          end: zone.end,
          // Alleen de eerste en laatste letter, net als elke andere waarde: een
          // melding met de naam uit de MRZ erin verplaatst het probleem.
          maskedSample: maskValue(value),
        ),
      );
    }
  }

  // ── nl.bsn ────────────────────────────────────────────────────────────────

  /// Een BSN-treffer is pas een waarschuwing als er óók context is.
  ///
  /// De 11-proef laat ongeveer één op de elf willekeurige 9-cijferige getallen
  /// door (vastgelegd in `privacy_checksums_test.dart`). Zouden we daarop alleen
  /// afgaan, dan vuurt de scanner op elk elfde ordernummer, factuurnummer en
  /// klantnummer — en dan zet de gebruiker hem uit. Dus:
  ///
  ///   * checksum + contextwoord  → `certain`, een echte melding;
  ///   * checksum zonder context  → `possible`, informatief.
  ///
  /// Testnummers en betekenisloze reeksen vallen sowieso af.
  void _scanBsn(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    for (final match in _reNineDigits.allMatches(fragment.text)) {
      final digits = match.group(0)!;
      if (!passesElevenProof(digits)) continue;
      if (isNonPersonalBsn(digits)) continue;

      final hasContext = _hasContextWord(
        fragment.text,
        match.start,
        bsnContextWords,
      );
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'nl.bsn',
          family: PrivacyFamily.identifier,
          confidence: hasContext
              ? PrivacyConfidence.certain
              : PrivacyConfidence.possible,
        ),
      );
    }
  }

  /// Staat een van [words] binnen [kContextWindow] tekens vóór de treffer?
  bool _hasContextWord(String text, int matchStart, List<String> words) {
    final from = (matchStart - kContextWindow).clamp(0, text.length);
    final window = text.substring(from, matchStart).toLowerCase();
    return words.any(window.contains);
  }

  /// Voegt een bevinding toe, tenzij hij is onderdrukt (`null`).
  void _emit(List<PrivacyFinding> out, PrivacyFinding? finding) {
    if (finding != null) out.add(finding);
  }

  /// Bouwt een bevinding, of `null` wanneer de waarde bij de gebruiker zelf
  /// hoort.
  ///
  /// De controle zit hier, op één plek, en niet in elke regel apart: elke regel
  /// die een waarde uit de tekst haalt, loopt hierdoorheen, dus een nieuwe regel
  /// erft de onderdrukking gratis.
  PrivacyFinding? _finding(
    _Fragment fragment,
    int slideIndex,
    Match match, {
    required String ruleId,
    required PrivacyFamily family,
    required PrivacyConfidence confidence,
  }) {
    if (ownIdentity.covers(match.group(0)!)) return null;
    return PrivacyFinding(
      ruleId: ruleId,
      family: family,
      confidence: confidence,
      slideIndex: slideIndex,
      field: fragment.field,
      fragmentIndex: fragment.index,
      start: match.start,
      end: match.end,
      // Nooit de volledige waarde: een privacycontrole die de gevonden BSN's
      // in haar eigen meldingen zet, heeft het probleem verplaatst.
      maskedSample: maskValue(match.group(0)!),
    );
  }

  // ── Welke velden gescand worden ───────────────────────────────────────────

  /// De deckvelden die in de documentmetadata belanden (en dus meereizen in
  /// PDF-properties en PPTX-docProps, leesbaar, ook al staat er op geen enkele
  /// slide iets van te zien).
  Iterable<_Fragment> _deckFragments(Deck deck) sync* {
    yield (field: 'deckTitle', index: 0, text: deck.title);
    yield (field: 'author', index: 0, text: deck.author);
    yield (field: 'organization', index: 0, text: deck.organization);
    yield (field: 'description', index: 0, text: deck.description);
    yield (field: 'keywords', index: 0, text: deck.keywords);
  }

  /// Elk tekstdragend veld van een slide.
  ///
  /// `notes` staat er nadrukkelijk bij: sprekersnotities zijn onzichtbaar in de
  /// preview, maar gaan als platte tekst mee in de PPTX-notitiepagina's. Het is
  /// in de praktijk het vuilste veld van allemaal.
  Iterable<_Fragment> _slideFragments(Slide slide) sync* {
    yield (field: 'title', index: 0, text: slide.title);
    yield (field: 'subtitle', index: 0, text: slide.subtitle);
    yield (field: 'columnTitle1', index: 0, text: slide.columnTitle1);
    yield (field: 'columnTitle2', index: 0, text: slide.columnTitle2);
    yield (field: 'imageCaption', index: 0, text: slide.imageCaption);
    yield (field: 'imageCaption2', index: 0, text: slide.imageCaption2);
    yield (field: 'imageAltText', index: 0, text: slide.imageAltText);
    yield (field: 'imageAltText2', index: 0, text: slide.imageAltText2);
    yield (field: 'quote', index: 0, text: slide.quote);
    yield (field: 'quoteAuthor', index: 0, text: slide.quoteAuthor);
    yield (field: 'customMarkdown', index: 0, text: slide.customMarkdown);
    yield (field: 'notes', index: 0, text: slide.notes);

    // De mediapaden. Een `/Users/jan.jansen/…` in een afbeeldingsverwijzing
    // verraadt gewoon een naam, en dat pad reist mee in de markdown en dus in de
    // HTML-export.
    //
    // De projectie lakt hier geen tekens in weg — een pad met blokjes erin is
    // een kapotte verwijzing, en de auteur hernoemt het bestand of verplaatst
    // het. Maar op een slide die op `redact` staat verdwijnt de hele
    // mediaverwijzing (zie `_projectMedia`), dus dáár komt het pad ook niet meer
    // in de export terecht. Dat was eerder wél zo, en dan reisde een
    // gedetecteerde `/Users/jan.jansen/…` gewoon mee.
    yield (field: 'imagePath', index: 0, text: slide.imagePath);
    yield (field: 'imagePath2', index: 0, text: slide.imagePath2);
    yield (field: 'videoPath', index: 0, text: slide.videoPath);
    yield (field: 'audioPath', index: 0, text: slide.audioPath);

    for (var i = 0; i < slide.bullets.length; i++) {
      yield (field: 'bullets', index: i, text: slide.bullets[i]);
    }
    for (var i = 0; i < slide.bullets2.length; i++) {
      yield (field: 'bullets2', index: i, text: slide.bullets2[i]);
    }
    // Tabelcellen krijgen een doorlopende index (rij * kolommen + kolom), zodat
    // één int volstaat om de cel terug te vinden.
    for (var r = 0; r < slide.tableRows.length; r++) {
      final row = slide.tableRows[r];
      for (var c = 0; c < row.length; c++) {
        yield (field: 'tableRows', index: r * row.length + c, text: row[c]);
      }
    }
  }
}
