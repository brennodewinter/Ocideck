// Part of the settings_provider library — see ../settings_provider.dart.
// Split out for navigability (de privacy-instellingen); alle imports leven in het
// hoofdbestand. Verhuisd zonder gedragswijziging.
part of '../settings_provider.dart';

/// De schakelaars van de privacycontrole.
///
/// Drie soorten keuze, en het verschil ertussen is niet cosmetisch:
///
///   * setPrivacyChecksEnabled — "val me niet lastig". Geen oordeel over de
///     inhoud, dus redactie blijft gewoon werken;
///   * setPrivacyRuleEnabled — "deze regel heeft het mís over mijn inhoud". Dát
///     is een oordeel, dus de regel vuurt nergens meer, ook niet bij redactie;
///   * setPrivacyOwnIdentity — "dit ben ik zelf". De afzender is geen bevinding.
extension SettingsPrivacy on SettingsNotifier {
  Future<void> setPrivacyChecksEnabled(bool enabled) async {
    currentState = currentState.copyWith(privacyChecksEnabled: enabled);
    await _persist(
      'setPrivacyChecksEnabled',
      (prefs) => prefs.setBool('privacyChecksEnabled', enabled),
    );
  }

  /// Zet de beeldcontrole aan of uit.
  ///
  /// Los van de hoofdschakelaar, want dit is de duurste controle van allemaal:
  /// elke afbeelding wordt gedecodeerd en door een neuraal netwerk gehaald. Wie
  /// dat niet wil betalen, hoort daarvoor niet de tekstcontrole te hoeven
  /// opgeven.
  Future<void> setPrivacyImageFaceDetection(bool enabled) async {
    currentState = currentState.copyWith(privacyImageFaceDetection: enabled);
    await _persist(
      'setPrivacyImageFaceDetection',
      (prefs) => prefs.setBool('privacyImageFaceDetection', enabled),
    );
  }

  /// Laat een `zeker`-bevinding als fout tellen in plaats van als waarschuwing.
  ///
  /// De gevolgen reiken verder dan een kleurtje in het paneel: een fout activeert
  /// `qualityBlockExportOnErrors`, dus deze schakelaar kan een export tegenhouden
  /// die gisteren nog doorging. Daarom staat hij standaard uit en hoort er in de
  /// UI bij te staan wat hij aanricht.
  Future<void> setPrivacyStrictSeverity(bool enabled) async {
    currentState = currentState.copyWith(privacyStrictSeverity: enabled);
    await _persist(
      'setPrivacyStrictSeverity',
      (prefs) => prefs.setBool('privacyStrictSeverity', enabled),
    );
  }

  /// Zet één detectieregel aan of uit.
  ///
  /// De ontsnappingsklep uit de melding zelf ("deze regel nooit meer melden").
  /// Chirurgisch ingrijpen op één regel is oneindig veel beter dan de hele
  /// controle uitzetten, want dat laatste is onomkeerbaar in de praktijk: wie hem
  /// eenmaal uit heeft, zet hem niet meer aan.
  Future<void> setPrivacyExportGate(PrivacyExportGate gate) async {
    currentState = currentState.copyWith(privacyExportGate: gate);
    await _persist(
      'setPrivacyExportGate',
      (prefs) => prefs.setString('privacyExportGate', gate.key),
    );
  }

  /// De prefs-sleutel waar "je eigen gegevens" tot en met 0.1.0 stond. Blijft
  /// bestaan voor de eenmalige verhuizing naar de sleutelbos; zie
  /// [migratePrivacyOwnIdentity].
  static const legacyOwnIdentityKey = 'privacyOwnIdentity';

  /// Leg vast wie de gebruiker zelf is — naam, e-mailadres, telefoonnummer,
  /// domein.
  ///
  /// Gaat naar de sleutelbos van het besturingssysteem en niet naar prefs. Het
  /// is geen wachtwoord, maar het is wél het enige instellingenveld met
  /// persoonsgegevens van een natuurlijke persoon erin, en een app die decks
  /// nakijkt op precies zulke gegevens hoort ze zelf niet in klaartekst naast
  /// haar voorkeuren te zetten.
  ///
  /// Mislukt de sleutelbos, dan blijft de waarde wel in het geheugen staan (de
  /// scan blijft deze sessie werken) en meldt [_reportSecretFailure] het. Stil
  /// terugvallen op prefs zou de reden van deze verhuizing ongedaan maken.
  Future<void> setPrivacyOwnIdentity(String value) async {
    currentState = currentState.copyWith(privacyOwnIdentity: value);
    final ok = await _secrets.writePrivacyOwnIdentity(value);
    if (!ok) {
      _reportSecretFailure('setPrivacyOwnIdentity', 'keychain write failed');
      return;
    }
    // De oude plek moet leeg zijn, anders staat de klaartekst er nog.
    await _persist(
      'setPrivacyOwnIdentity',
      (prefs) => prefs.remove(legacyOwnIdentityKey),
    );
  }

  /// Haal "je eigen gegevens" op, en verhuis ze eenmalig uit prefs.
  ///
  /// Wordt bij het laden aangeroepen. De prefs-sleutel gaat pas weg wanneer de
  /// sleutelbos de waarde heeft aangenomen — anders kost een geweigerde
  /// keychain de gebruiker zijn hele uitzonderingslijst, en begint de scanner
  /// zijn eigen naam als bevinding te melden.
  Future<String> migratePrivacyOwnIdentity(SharedPreferences prefs) async {
    final legacy = prefs.getString(legacyOwnIdentityKey);
    if (legacy != null) {
      if (await _secrets.writePrivacyOwnIdentity(legacy)) {
        await prefs.remove(legacyOwnIdentityKey);
      }
      return legacy;
    }
    return await _secrets.readPrivacyOwnIdentity() ?? '';
  }

  /// Zet één landpakket aan of uit (OCIWACHT §5.7).
  ///
  /// Los van [setPrivacyRuleEnabled]: een uitgezet pakket zegt "deze regio is
  /// voor mij niet relevant", een uitgezette regel zegt "deze regel heeft het
  /// mis over mijn inhoud". Het eerste is een scopekeuze, het tweede een oordeel
  /// — en alleen het tweede hoort ook de redactie tegen te houden.
  Future<void> setPrivacyRegionEnabled(String region, bool enabled) async {
    final next = {...currentState.privacyRegions};
    if (enabled) {
      next.add(region);
    } else {
      next.remove(region);
    }
    currentState = currentState.copyWith(privacyRegions: next);
    await _persist(
      'setPrivacyRegionEnabled',
      (prefs) => prefs.setStringList('privacyRegions', next.toList()),
    );
  }

  Future<void> setPrivacyRuleEnabled(String ruleId, bool enabled) async {
    final next = {...currentState.privacyDisabledRules};
    if (enabled) {
      next.remove(ruleId);
    } else {
      next.add(ruleId);
    }
    currentState = currentState.copyWith(privacyDisabledRules: next);
    await _persist(
      'setPrivacyRuleEnabled',
      (prefs) => prefs.setStringList('privacyDisabledRules', next.toList()),
    );
  }
}
