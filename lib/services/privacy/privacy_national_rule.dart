// De beschrijving van één nationaal identificatienummer.
//
// Dit stond eerst in `privacy_eu_rules.dart` en heette `EuIdentifierRule`, maar
// er is nooit iets Europees aan geweest: `country`, `pattern`, `validate`,
// `contextWords` en `confidence` beschrijven een persoonsnummer, niet een
// werelddeel. Toen de VS en Canada erbij kwamen (§15) zou de naam gaan liegen —
// een Amerikaans SSN in een klasse met `Eu` ervoor. Vandaar deze verhuizing:
// de vorm hier, de landenlijsten in `privacy_eu_rules.dart` en
// `privacy_world_rules.dart`.

import '../../models/privacy_finding.dart';

/// Eén nationaal identificatienummer.
class NationalIdentifierRule {
  final String id;

  /// ISO-landcode. Bepaalt of de regel meedraait bij het gekozen regiopakket.
  final String country;

  final RegExp pattern;

  /// De checksum. Null = er ís er geen, en dan is een contextwoord verplicht.
  final bool Function(String)? validate;

  /// Woorden die in de buurt moeten staan wanneer er geen checksum is, of
  /// wanneer de checksum te zwak is om alleen op af te gaan.
  final List<String> contextWords;

  /// Zonder checksum is het formaat geen bewijs: dan hooguit `likely`.
  final PrivacyConfidence confidence;

  const NationalIdentifierRule({
    required this.id,
    required this.country,
    required this.pattern,
    this.validate,
    this.contextWords = const [],
    this.confidence = PrivacyConfidence.certain,
  });
}
