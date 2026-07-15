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
import '../../models/slide.dart';
import 'privacy_allowlist.dart';
import 'privacy_bulk_rules.dart';
import 'privacy_checksums.dart';
import 'privacy_contact_rules.dart';
import 'privacy_eu_rules.dart';
import 'privacy_own_identity.dart';
import 'privacy_phone_rules.dart';
import 'privacy_special_rules.dart';
import 'privacy_structural_rules.dart';
import 'privacy_secret_rules.dart';

/// Eén tekstfragment van een slide, met de veldnaam waar het uit komt.
typedef _Fragment = ({String field, int index, String text});

/// Hoe ver een contextwoord vóór een treffer mag staan om nog te tellen.
///
/// Ruim genoeg voor "Het burgerservicenummer van betrokkene is 123456782", krap
/// genoeg dat een woord elders in de zin niet meetelt.
const int kContextWindow = 40;

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

  const PrivacyScanner({
    this.disabledRules = const {},
    this.ownIdentity = OwnIdentity.empty,
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

  /// Uitgezette regels eruit — vóór de escalatie, zodat een uitgezette
  /// identificator ook geen bijzonder gegeven meer omhoog trekt.
  List<PrivacyFinding> _enabled(List<PrivacyFinding> findings) {
    if (disabledRules.isEmpty) return findings;
    return [
      for (final f in findings)
        if (!disabledRules.contains(f.ruleId)) f,
    ];
  }

  /// De co-occurrence-escalator (OCIWACHT §5.6).
  ///
  /// Een trefwoord als "diagnose" of "verdachte" meldt op zichzelf niets dat de
  /// gebruiker onderbreekt — een slide *óver* de AVG noemt die woorden nu eenmaal,
  /// en een privacyles die alarm slaat is binnen een dag uitgezet.
  ///
  /// Staat er op dezelfde slide óók een gegeven dat één persoon aanwijst (BSN,
  /// nationaal nummer, e-mailadres), dan is het bijzondere gegeven herleidbaar tot
  /// een persoon — en dát is precies wat artikel 9 beschermt. Dán pas gaat de
  /// melding omhoog.
  ///
  /// En dan verbreedt ze ook het **bereik**, niet alleen de zekerheid.
  ///
  /// Zodra het bijzondere gegeven herleidbaar is tot een persoon, is het gegeven
  /// de hele mededeling — zie [statementSpan]. Daarom heeft deze functie de
  /// fragmenttekst nodig: zonder die tekst weet ze niet waar de mededeling begint
  /// en eindigt.
  List<PrivacyFinding> _escalateSpecialCategories(
    List<PrivacyFinding> findings,
    Map<String, String> fragmentTexts,
  ) {
    if (!findings.any(identifiesAPerson)) return findings;
    return [
      for (final f in findings)
        if (f.family == PrivacyFamily.specialCategory)
          _escalate(f, fragmentTexts['${f.field}:${f.fragmentIndex}'] ?? '')
        else
          f,
    ];
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

  /// Een persoonsnaam achter een aanhef of een label — nooit via NER.
  ///
  /// Blijft bewust `possible`: een naam heeft geen checksum, en een woord met een
  /// hoofdletter is ook het begin van een zin. De melding informeert dus, en
  /// onderbreekt niet. Bij redactie gaat de naam er wél uit, net als elke andere
  /// bevinding. De kale naam zonder label (een titel die enkel een naam is) valt
  /// hier buiten — daarvoor is de handmatige `[[…]]`-markering.
  void _scanName(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    final text = fragment.text;
    for (final pattern in [nameLabelPattern, nameSalutationPattern]) {
      for (final match in pattern.allMatches(text)) {
        final name = match.group(1);
        if (name == null || name.isEmpty) continue;
        if (isPlaceholderPerson(name)) continue;
        if (ownIdentity.covers(name)) continue;
        // De naam staat aan het eind van de match; daaruit volgt zijn positie
        // zonder dat we een groepsoffset nodig hebben (die Dart niet los geeft).
        final start = match.end - name.length;
        out.add(
          PrivacyFinding(
            ruleId: 'contact.name',
            family: PrivacyFamily.contact,
            confidence: PrivacyConfidence.possible,
            slideIndex: slideIndex,
            field: fragment.field,
            fragmentIndex: fragment.index,
            start: start,
            end: match.end,
            maskedSample: maskValue(name),
          ),
        );
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

  // ── Bijzondere persoonsgegevens (AVG art. 9/10) ───────────────────────────

  /// Trefwoorden, genetische notatie, en het parketnummer.
  ///
  /// De trefwoorden leveren bewust niet meer dan `possible` op. Ze worden pas een
  /// echte melding via de escalator, wanneer er op dezelfde slide iemand staat om
  /// ze aan te koppelen.
  void _scanSpecialCategories(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    final lower = fragment.text.toLowerCase();

    for (final rule in specialCategoryRules) {
      for (final word in rule.keywords) {
        final at = lower.indexOf(word);
        if (at < 0) continue;
        _emit(
          out,
          _keywordFinding(fragment, slideIndex, rule.id, at, word.length),
        );
        // Eén melding per familie per fragment: tien synoniemen in één zin
        // leveren geen tien meldingen op.
        break;
      }
    }

    for (final genetic in geneticPatterns) {
      for (final match in genetic.pattern.allMatches(fragment.text)) {
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: genetic.id,
            family: PrivacyFamily.specialCategory,
            confidence: PrivacyConfidence.possible,
          ),
        );
      }
    }

    for (final match in parketnummerPattern.allMatches(fragment.text)) {
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'nl.parketnummer',
          family: PrivacyFamily.specialCategory,
          // Geen checksum, maar een formaat dat in gewone tekst niet voorkomt.
          confidence: PrivacyConfidence.likely,
        ),
      );
    }
  }

  PrivacyFinding _keywordFinding(
    _Fragment fragment,
    int slideIndex,
    String ruleId,
    int start,
    int length,
  ) => PrivacyFinding(
    ruleId: ruleId,
    family: PrivacyFamily.specialCategory,
    confidence: PrivacyConfidence.possible,
    slideIndex: slideIndex,
    field: fragment.field,
    fragmentIndex: fragment.index,
    start: start,
    end: start + length,
    maskedSample: maskValue(fragment.text.substring(start, start + length)),
  );

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
    // Let op: `_projectSlide` in de projectie kent deze velden NIET, en dat is
    // met opzet. Een geredigeerd pad is een kapotte afbeelding. We melden het,
    // we redigeren het niet — de auteur hernoemt het bestand of verplaatst het.
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
