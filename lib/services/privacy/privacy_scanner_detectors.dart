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
    // De bulk uit Orphanet (§13.3). Draait naast de vloer en niet ervoor: de
    // vloer levert de *aanwijzingen* ("diagnose"), de bulk de *waarden*
    // (aandoeningsnamen). Gewicht 5, dus een aandoeningsnaam wint van een
    // signaalwoord in hetzelfde fragment — de melding wijst dan het gegeven aan
    // in plaats van het woord dat ernaar verwijst.
    for (final hit in PrivacyHealthLexicon.instance.findIn(lower)) {
      final current = best['special.health'];
      if (current != null && current.entry.weight >= _kBulkHealthWeight) break;
      best['special.health'] = (
        entry: PrivacyLexiconEntry(
          term: lower.substring(hit.start, hit.end),
          category: 'special.health',
          lang: 'mul',
          match: PrivacyTermMatch.word,
          weight: _kBulkHealthWeight,
          role: PrivacyLexiconRole.value,
        ),
        at: hit.start,
      );
      break;
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
}
