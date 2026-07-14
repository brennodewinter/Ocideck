import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/privacy_finding.dart';
import '../models/slide_quality.dart';
import '../services/privacy/privacy_quality_bridge.dart';
import '../services/privacy/privacy_scanner.dart';
import 'deck_provider.dart';
import 'settings_provider.dart';

/// De scanner zelf: stateloos, het deck komt bij de aanroep binnen.
final privacyScannerProvider = Provider<PrivacyScanner>(
  (_) => const PrivacyScanner(),
);

/// De privacyscan van het huidige deck.
///
/// Draait volledig op dit apparaat: de inhoud van de slides gaat er niet voor
/// het geheugen uit, er worden geen bevindingen bijgehouden buiten deze sessie,
/// en er gaat geen statistiek naar buiten.
///
/// Staat de controle uit, dan is het resultaat leeg — en dat is geen verbergen:
/// de scan draait dan werkelijk niet.
final privacyScanProvider = Provider<PrivacyScanResult>(computePrivacyScan);

/// De privacybevindingen als kwaliteitsmeldingen, zodat ze verschijnen wáár de
/// gebruiker al kijkt: in het kwaliteitspaneel, op de thumbnails, in de
/// export-gate.
final privacyQualityIssuesProvider = Provider<List<SlideQualityIssue>>(
  computePrivacyQualityIssues,
);

/// Top-level, zodat `AppShell` dezelfde berekening per tab kan overriden.
///
/// Beide providers lezen het gescopede deck. Zonder die override lossen ze op in
/// de root-container, zien ze een leeg deck en doen ze stilletjes niets — precies
/// hoe `imageContrastIssuesProvider` ooit stukging. `provider_scope_test.dart`
/// bewaakt dat.
PrivacyScanResult computePrivacyScan(Ref ref) {
  final enabled = ref.watch(
    settingsProvider.select((s) => s.privacyChecksEnabled),
  );
  if (!enabled) return PrivacyScanResult.empty;

  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return PrivacyScanResult.empty;

  return ref.watch(privacyScannerProvider).scan(deck);
}

List<SlideQualityIssue> computePrivacyQualityIssues(Ref ref) {
  return privacyIssuesFrom(ref.watch(privacyScanProvider));
}
