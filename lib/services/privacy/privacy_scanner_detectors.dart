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
}
