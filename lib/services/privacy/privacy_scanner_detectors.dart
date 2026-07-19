part of 'privacy_scanner.dart';

// De detectoren voor de families die ná de eerste oplevering zijn bijgekomen:
// digitale identificatoren, de machine-readable zone, de geboortedatum en
// coördinaten.
//
// Ze staan in een `part of`-extensie om `privacy_scanner.dart` onder de
// duizend-regelgrens te houden — dezelfde reden als bij `deck_provider`. Omdat
// het dezelfde library is, houden ze gewoon toegang tot `_finding`, `_emit`,
// `_hasContextWord` en `ownIdentity`; er is dus niets doorgegeven of
// gedupliceerd, alleen verplaatst.
extension PrivacyScannerDetectors on PrivacyScanner {
  // ── contact.birthdate ─────────────────────────────────────────────────────

  /// Een geboortedatum: een datum mét een contextwoord ervoor.
  ///
  /// Het contextwoord is niet onderhandelbaar. Een datum is de meest
  /// voorkomende getalsvorm in een zakelijk deck — releases, deadlines,
  /// kwartalen, vergaderingen — en een regel die ze allemaal meldt, meldt de
  /// agenda. Met de poort erop blijft er precies over wat de auteur zélf als
  /// geboortedatum heeft opgeschreven.
  ///
  /// Blijft `likely`: een datum heeft geen checksum, en "geboren in Utrecht op
  /// 3 maart" kan ook over een organisatie gaan.
  void _scanBirthdate(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final match in birthdatePattern.allMatches(fragment.text)) {
      final parsed = parseNumericDate(match.group(0)!);
      if (parsed == null) continue;
      if (!isPlausibleBirthdate(parsed.year, parsed.month, parsed.day)) {
        continue;
      }
      if (!_hasContextWord(fragment.text, match.start, birthdateContextWords)) {
        continue;
      }
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'contact.birthdate',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.likely,
        ),
      );
    }

    for (final match in birthdateWordPattern.allMatches(fragment.text)) {
      if (!_hasContextWord(fragment.text, match.start, birthdateContextWords)) {
        continue;
      }
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'contact.birthdate',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.likely,
        ),
      );
    }
  }

  // ── contact.geo ───────────────────────────────────────────────────────────

  /// Coördinaten: een decimaal paar, een `geo:`-URI, een plus-code of
  /// what3words.
  ///
  /// Anders dan de geboortedatum eist deze regel géén contextwoord, en dat kan
  /// omdat de vorm het werk doet: twee kommagetallen met minstens vier decimalen
  /// binnen het bereik van de aardbol komen in gewone tekst niet voor. Vier
  /// decimalen is ongeveer elf meter — met minder wijst het paar een dorp aan en
  /// geen deur, en dan is het geen persoonsgegeven.
  ///
  /// Grafiekvelden vallen erbuiten: een dataset ís een reeks getallenparen.
  void _scanGeo(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    if (chartDataFields.contains(fragment.field)) return;

    // De genoteerde vormen eerst. Die dragen hun betekenis in het formaat zelf —
    // `geo:` en `///` zeggen letterlijk "dit is een plaats" — en zijn daarmee
    // zekerder dan een kaal getallenpaar.
    //
    // De volgorde is niet vrijblijvend: een `geo:`-URI *bevat* een
    // coördinatenpaar, dus zonder deze voorrang meldt de zwakkere regel hem
    // eerst en verliest de melding haar zekerheid.
    final notated = <({int start, int end})>[];
    for (final pattern in [
      geoUriPattern,
      whatThreeWordsPattern,
      plusCodePattern,
    ]) {
      for (final match in pattern.allMatches(fragment.text)) {
        notated.add((start: match.start, end: match.end));
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: 'contact.geo',
            family: PrivacyFamily.contact,
            confidence: pattern == plusCodePattern
                // Een plus-code is base-20 over een beperkt alfabet en kan dus
                // botsen met een productcode. De andere twee niet.
                ? PrivacyConfidence.possible
                : PrivacyConfidence.certain,
          ),
        );
      }
    }

    for (final match in coordinatePairPattern.allMatches(fragment.text)) {
      if (notated.any((n) => match.start >= n.start && match.end <= n.end)) {
        continue;
      }
      final latitude = double.tryParse(match.group(1)!);
      final longitude = double.tryParse(match.group(2)!);
      if (latitude == null || longitude == null) continue;
      if (!isPlausibleCoordinate(latitude, longitude)) continue;
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'contact.geo',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.likely,
        ),
      );
    }
  }

  // ── digital.* ─────────────────────────────────────────────────────────────

  /// IP-adressen, MAC's, IMEI's, handles en device-ID's.
  ///
  /// Het werk zit niet in de patronen maar in de poorten erachter: een
  /// versienummer is vier getallen met punten, een git-hash is hex, en een kale
  /// UUID is net zo goed een primaire sleutel. Zie `privacy_digital_rules.dart`.
  ///
  /// Een privé-adres uit RFC 1918 zakt naar `possible`. Het is interne
  /// infrastructuur en geen persoonsgegeven — de melding hoort er te zijn (een
  /// intern adresplan in een publieke slide blijft een lek) maar mag niemand
  /// onderbreken.
  void _scanDigital(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final rule in digitalRules) {
      for (final match in rule.pattern.allMatches(fragment.text)) {
        if (rule.validate != null && !rule.validate!(match, fragment.text)) {
          continue;
        }
        final value = match.group(0)!;
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: rule.id,
            family: PrivacyFamily.digital,
            confidence: rule.id == 'digital.ipv4' && isPrivateIpv4(value)
                ? PrivacyConfidence.possible
                : rule.confidence,
          ),
        );
      }
    }

    // De regels zonder checksum. Zonder hun contextwoord vuren ze niet: vijftien
    // cijfers zijn ook een transactienummer, en een UUID is ook een bestandsnaam.
    for (final entry in contextualDigitalRules) {
      for (final match in entry.rule.pattern.allMatches(fragment.text)) {
        if (!_hasContextWord(fragment.text, match.start, entry.contextWords)) {
          continue;
        }
        if (entry.rule.validate != null &&
            !entry.rule.validate!(match, fragment.text)) {
          continue;
        }
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: entry.rule.id,
            family: PrivacyFamily.digital,
            confidence: entry.rule.confidence,
          ),
        );
      }
    }
  }

  // ── nl.plate en <land>.postcode ───────────────────────────────────────────

  /// Kenteken en buitenlandse postcode — de twee regiogebonden contactregels.
  ///
  /// Hun regel-id's dragen de landcode vooraan (`nl.plate`, `de.postcode`),
  /// zodat de regiopoort ze herkent zonder een tweede koppellijst. Zie
  /// `privacy_plate_rules.dart` voor waarom beide een contextwoord eisen waar de
  /// Nederlandse postcode dat niet hoeft.
  void _scanPlateAndIntlPostcode(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final match in dutchPlatePattern.allMatches(fragment.text)) {
      if (isForbiddenPlate(match.group(0)!)) continue;
      // Verplicht, niet aanbevolen: `XX-99-99` is ook een artikelcode, en het
      // patroon sluit op zichzelf bijna niets uit.
      if (!_hasContextWord(fragment.text, match.start, plateContextWords)) {
        continue;
      }
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'nl.plate',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.likely,
        ),
      );
    }

    for (final rule in intlPostcodeRules) {
      // De regiopoort filtert achteraf op regel-id, maar hier al overslaan
      // scheelt het scannen van zeven patronen die toch wegvallen.
      if (!regions.contains(rule.region)) continue;
      final needsContext = postcodeNeedsContext.contains(rule.region);
      for (final match in rule.pattern.allMatches(fragment.text)) {
        if (rule.validate != null && !rule.validate!(match.group(0)!)) continue;
        if (needsContext &&
            !_hasContextWord(
              fragment.text,
              match.start,
              postcodeContextWords,
            )) {
          continue;
        }
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: rule.ruleId,
            family: PrivacyFamily.contact,
            // Een postcode alleen wijst een straat aan, geen persoon. Net als
            // de Nederlandse blijft hij informatief tot er meer bij staat.
            confidence: PrivacyConfidence.possible,
          ),
        );
      }
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

    // Eén melding per familie per fragment: tien synoniemen in één zin leveren
    // geen tien meldingen op. Wélke van die tien de melding draagt, is sinds
    // fase 12 niet meer "de eerste in de lijst" maar de meest specifieke — het
    // gewicht uit het lexicon. Dat is het verschil tussen een melding die
    // "diagnose" aanwijst (een woord dat in elke projectvergadering valt) en één
    // die "ziekteverzuim" aanwijst, in dezelfde zin.
    final best = <String, ({PrivacyLexiconEntry entry, int at})>{};
    for (final entry in bundledPrivacyLexicon) {
      final at = findPrivacyTermIn(lower, entry.term, entry.effectiveMatch);
      if (at < 0) continue;
      final current = best[entry.category];
      if (current == null || entry.weight > current.entry.weight) {
        best[entry.category] = (entry: entry, at: at);
      }
    }
    // De gebundelde bronnen (§13.3). Draaien naast de vloer en niet ervoor: de
    // vloer levert de *aanwijzingen* ("diagnose", "geloofsovertuiging"), de bulk
    // de *waarden* — een aandoeningsnaam uit Orphanet, een religie of ideologie
    // uit EuroVoc. Vandaar het hogere gewicht: staat er in hetzelfde fragment
    // een signaalwoord én een waarde, dan wijst de melding de waarde aan.
    //
    // Per categorie de eerste treffer; de index geeft ze in tekstvolgorde.
    for (final hit in PrivacyBulkLexicon.instance.findIn(lower)) {
      final current = best[hit.category];
      if (current != null && current.entry.weight >= _kBulkTermWeight) continue;
      best[hit.category] = (
        entry: PrivacyLexiconEntry(
          term: lower.substring(hit.start, hit.end),
          category: hit.category,
          // De bulk is meertalig en de term draagt zijn taal niet mee; `mul` is
          // de ISO 639-2-code voor "meerdere talen".
          lang: 'mul',
          match: PrivacyTermMatch.word,
          weight: _kBulkTermWeight,
          role: PrivacyLexiconRole.value,
        ),
        at: hit.start,
      );
    }

    for (final hit in best.values) {
      _emit(
        out,
        _keywordFinding(
          fragment,
          slideIndex,
          hit.entry.category,
          hit.at,
          hit.entry.term.length,
          // De rol komt nu uit het lexicon in plaats van uit een aanname per
          // familie. Binnen één familie komen namelijk beide voor: "diagnose"
          // wijst naar het gegeven, "diabetes" ís het — en dat verschil bepaalt
          // of redactie werkelijk iets weghaalt.
          role: hit.entry.role == PrivacyLexiconRole.value
              ? PrivacyTermRole.value
              : PrivacyTermRole.indicator,
          // Alleen bij artikel 10 heeft "wiens rol is dit" betekenis. Een
          // diagnose kent geen verdachte.
          personRole: hit.entry.category == 'special.criminal'
              ? personRoleFor(
                  fragment.text,
                  hit.at,
                  hit.at + hit.entry.term.length,
                )
              : PrivacyPersonRole.unknown,
        ),
      );
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

    // ICD-10 en ATC. Contextwoord verplicht: `A12` is ook een tabelverwijzing,
    // een zaalnummer en een vitamine.
    for (final rule in medicalCodePatterns) {
      for (final match in rule.pattern.allMatches(fragment.text)) {
        if (!_hasContextWord(fragment.text, match.start, rule.contextWords)) {
          continue;
        }
        _emit(
          out,
          _finding(
            fragment,
            slideIndex,
            match,
            ruleId: rule.id,
            family: PrivacyFamily.specialCategory,
            confidence: PrivacyConfidence.likely,
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
    int length, {
    PrivacyTermRole role = PrivacyTermRole.indicator,
    PrivacyPersonRole personRole = PrivacyPersonRole.unknown,
  }) => PrivacyFinding(
    ruleId: ruleId,
    family: PrivacyFamily.specialCategory,
    confidence: PrivacyConfidence.possible,
    slideIndex: slideIndex,
    field: fragment.field,
    fragmentIndex: fragment.index,
    start: start,
    end: start + length,
    maskedSample: maskValue(fragment.text.substring(start, start + length)),
    // Meestal wijst een trefwoord naar het gegeven en ís het het niet — zie
    // [PrivacyTermRole] voor waarom dat verschil bij redactie telt. Maar niet
    // altijd: "diabetes" en "strafblad" zíjn het gegeven. Het lexicon zegt
    // welke van de twee, en de standaard blijft de voorzichtige.
    role: role,
    personRole: personRole,
  );

  // ── fin.pan en fin.cvv ────────────────────────────────────────────────────

  /// Creditcardnummers, en de beveiligingscode als die erbij staat.
  ///
  /// De PAN staat op zichzelf: Luhn plus een bestaand IIN-bereik met de juiste
  /// lengte is bewijs genoeg. De CVV niet — `123` betekent niets, en drie
  /// cijfers achter het woord `cvv` betekenen alleen iets als er ook een
  /// kaartnummer in hetzelfde fragment staat. Dán betekenen ze meteen veel,
  /// want nummer plus code is een bruikbare betaalinstructie.
  ///
  /// Het ontwerp (§3-C, §5.6) wil voor die combinatie `error`. Dat kan nog niet:
  /// beslissing §11.3 houdt `zeker` bewust op *waarschuwing*, omdat een fout
  /// `qualityBlockExportOnErrors` bij bestaande gebruikers onbedoeld scherp zou
  /// zetten. De combinatie is daarom zichtbaar in de melding en niet in de
  /// ernst; de strengere variant hoort bij `privacyStrictSeverity` (§7), en die
  /// bestaat nog niet.
  void _scanCard(_Fragment fragment, int slideIndex, List<PrivacyFinding> out) {
    final pans = <Match>[];
    for (final match in cardNumberPattern.allMatches(fragment.text)) {
      final digits = cardDigits(match.group(0)!);
      if (isTestCardNumber(digits)) continue;
      if (!isPlausibleCardNumber(digits)) continue;
      pans.add(match);
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'fin.pan',
          family: PrivacyFamily.financial,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }
    if (pans.isEmpty) return;

    // Alleen in gezelschap van een kaartnummer.
    for (final match in cvvPattern.allMatches(fragment.text)) {
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'fin.cvv',
          family: PrivacyFamily.financial,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }
  }

  // ── fin.us_routing ────────────────────────────────────────────────────────

  /// Het Amerikaanse ABA routing number.
  ///
  /// Zit in de financiële familie en niet in het VS-landpakket, en dat is een
  /// bewuste keuze: een Amerikaans rekeningnummer in een Nederlands deck hoort
  /// niet stil te blijven omdat de auteur het VS-pakket uit had staan. Zo staat
  /// `fin.iban` er ook in — die geldt voor negenentachtig landen tegelijk.
  ///
  /// De mod-10 draagt hier het bewijs, anders dan bij de rest van §15. Vandaar
  /// de contextpoort: negen cijfers halen de controle één op de tien keer, en
  /// een bankrekening zonder het woord erbij is meestal een ordernummer.
  void _scanAbaRouting(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
  ) {
    for (final match in _reAbaRouting.allMatches(fragment.text)) {
      if (!isValidAbaRouting(match.group(0)!)) continue;
      if (!_hasContextWord(fragment.text, match.start, _abaContextWords)) {
        continue;
      }
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          match,
          ruleId: 'fin.us_routing',
          family: PrivacyFamily.financial,
          confidence: PrivacyConfidence.likely,
        ),
      );
    }
  }

  // ── contact.address: de twee ankers ───────────────────────────────────────

  /// De twee adresankers die geen straatnamenlijst nodig hebben.
  ///
  /// Levert per anker één span over het hele adres, en schrijft die spans in
  /// [spans] zodat [_scanAddress] weet wat er al gedekt is. Zie de kop van
  /// `privacy_contact_rules.dart` voor waarom een adres in stukjes redigeren
  /// geen adres redigeert.
  void _scanAnchoredAddresses(
    _Fragment fragment,
    int slideIndex,
    List<PrivacyFinding> out,
    List<({int start, int end})> spans,
  ) {
    final text = fragment.text;

    // Anker 1: de postcode staat er direct achter. Dat is in Nederland vrijwel
    // uniek identificerend, dus dit is `certain` zonder verdere bevestiging.
    for (final m in fullAddressPattern.allMatches(text)) {
      final postcode = dutchPostcodePattern.firstMatch(m.group(0)!);
      if (postcode == null || !isPlausibleDutchPostcode(postcode.group(0)!)) {
        continue;
      }
      spans.add((start: m.start, end: m.end));
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          m,
          ruleId: 'contact.address',
          family: PrivacyFamily.contact,
          confidence: PrivacyConfidence.certain,
        ),
      );
    }

    // Anker 2: de auteur schrijft er zelf "adres" boven.
    for (final m in addressLabelPattern.allMatches(text)) {
      final label = m.group(1)!;
      final raw = m.group(2)!;
      final value = raw.trimRight();
      if (value.isEmpty) continue;
      // De waarde is gulzig tot het regeleinde, dus ze eindigt op `m.end`; het
      // afgeknipte staartje wit schuift het einde naar links.
      final end = m.end - (raw.length - value.length);
      final start = end - value.length;
      if (spans.any((s) => start >= s.start && end <= s.end)) continue;

      // Een woonadres is per definitie van een persoon. Een kaal `Adres:` kan
      // het kantoor zijn en blijft daarom een hint — tenzij er een huisnummer
      // of postcode in staat, want dan wijst het een pand aan.
      final specific =
          isResidentialAddressLabel(label) ||
          dutchPostcodePattern.hasMatch(value) ||
          streetAddressPattern.hasMatch(value);
      spans.add((start: start, end: end));
      _emit(
        out,
        _finding(
          fragment,
          slideIndex,
          m,
          ruleId: 'contact.address',
          family: PrivacyFamily.contact,
          confidence: specific
              ? PrivacyConfidence.certain
              : PrivacyConfidence.possible,
          spanStart: start,
          spanEnd: end,
          value: value,
        ),
      );
    }
  }
}

/// Negen kale cijfers; de mod-10 en de contextpoort doen het echte werk.
final _reAbaRouting = RegExp(r'(?<!\d)\d{9}(?!\d)');

const _abaContextWords = ['routing', 'aba', 'ach', 'wire', 'bank'];
