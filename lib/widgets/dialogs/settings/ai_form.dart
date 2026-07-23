// De invulstand van de AI-backend. Derde bron met hetzelfde geheimpatroon, en
// opnieuw met een eigen vorm: hier geen gebruiker of eigenaar maar een modus
// (lokaal of cloud) en een uitdrukkelijke cloudbevestiging, en de
// sleutelhangersleutel is de kale basis-URL. Zie [KeychainSecret] voor het deel
// dat de drie wél delen.
import 'package:flutter/widgets.dart';

import '../../../models/ai_settings.dart';
import '../../../state/settings_provider.dart';
import 'keychain_secret.dart';

/// Wat het AI-tabblad aan het bewerken is, tot Opslaan of Annuleren.
class AiForm {
  final TextEditingController baseUrl = TextEditingController();
  final TextEditingController model = TextEditingController();
  final KeychainSecret apiKey = KeychainSecret();

  bool enabled = false;
  AiBackendMode mode = AiBackendMode.local;
  bool trusted = false;

  /// Uitdrukkelijke bevestiging dat de gebruiker weet dat er naar een
  /// cloud-backend wordt gestuurd.
  bool cloudConfirmed = false;

  /// Uitslag van de verbindingstest: `null` = nog niet getest.
  bool? testOk;
  String? testMessage;
  bool testing = false;

  void adoptFrom(AiSettings ai) {
    enabled = ai.enabled;
    mode = ai.mode;
    trusted = ai.trustedInternal;
    cloudConfirmed = ai.cloudConfirmed;
    baseUrl.text = ai.baseUrl;
    model.text = ai.model;
    apiKey.rememberIdentity(ai.baseUrl);
  }

  /// Of er in dit formulier een backend staat, los van de schakelaar.
  ///
  /// Spiegelt [AiSettings.hasBackend], maar leest de velden zoals ze nú op het
  /// scherm staan: het tabblad en de modulekaart horen meteen te reageren, niet
  /// pas na Opslaan.
  bool get hasBackend =>
      mode != AiBackendMode.none && baseUrl.text.trim().isNotEmpty;

  /// Of het tabblad AI-assistentie zichtbaar hoort te zijn (#731).
  ///
  /// Aan zodra de module aan staat, óf er al een backend ligt: de vaste regel
  /// uit #648 — verbergen zolang er niets is, tónen zodra er wél iets is, want
  /// een schakelaar die je eigen werk onbereikbaar maakt is erger dan een
  /// tabblad te veel.
  ///
  /// Staat hier en niet drie keer los bij de aanroepers (zijbalk, zoekindex en
  /// het tabblad zelf). Die drie moeten hetzelfde antwoord geven; als ze het
  /// elk voor zich uitrekenen, verschuift er ooit één mee en de andere twee
  /// niet — en dan is het tabblad zichtbaar terwijl zoeken zegt dat het er niet
  /// is.
  bool get revealsTab => enabled || hasBackend;

  /// De instellingen zoals ze nu in de velden staan (zonder API-sleutel).
  AiSettings get settings {
    var url = baseUrl.text.trim();
    // Zonder schema is loopback de meest waarschijnlijke bedoeling; vul http://
    // aan. De veiligheidsgate valideert daarna alsnog scheme én host.
    if (url.isNotEmpty && !url.contains('://')) url = 'http://$url';
    return AiSettings(
      enabled: enabled,
      mode: mode,
      baseUrl: url,
      model: model.text.trim(),
      trustedInternal: trusted,
      cloudConfirmed: cloudConfirmed,
    );
  }

  void save(SettingsNotifier notifier) {
    final current = settings;
    notifier.setAiSettings(current);
    // Anders dan bij de twee andere bronnen ook een leegtecontrole: zonder
    // basis-URL is er geen sleutelhangersleutel om onder te schrijven.
    if (current.baseUrl.trim().isEmpty) return;
    if (apiKey.shouldWrite(current.baseUrl)) {
      notifier.setAiApiKey(current.baseUrl, apiKey.field.text);
    }
  }

  void dispose() {
    baseUrl.dispose();
    model.dispose();
    apiKey.dispose();
  }
}
