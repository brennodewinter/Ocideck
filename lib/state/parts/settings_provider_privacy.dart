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

  Future<void> setPrivacyOwnIdentity(String value) async {
    currentState = currentState.copyWith(privacyOwnIdentity: value);
    await _persist(
      'setPrivacyOwnIdentity',
      (prefs) => prefs.setString('privacyOwnIdentity', value),
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
