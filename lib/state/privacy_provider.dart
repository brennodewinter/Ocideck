import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deck.dart';
import '../models/privacy_disposition.dart';
import '../models/privacy_finding.dart';
import '../models/slide_quality.dart';
import '../services/privacy/privacy_export_policy.dart';
import '../services/privacy/privacy_quality_bridge.dart';
import '../services/privacy/privacy_own_identity.dart';
import '../services/privacy/privacy_scanner.dart';
import 'deck_provider.dart';
import 'settings_provider.dart';

/// De scanner, geconfigureerd met de regels die de gebruiker heeft uitgezet.
final privacyScannerProvider = Provider<PrivacyScanner>(
  (ref) => PrivacyScanner(
    disabledRules: ref.watch(
      settingsProvider.select((s) => s.privacyDisabledRules),
    ),
    ownIdentity: OwnIdentity.fromLines(
      ref.watch(settingsProvider.select((s) => s.privacyOwnIdentity)),
    ),
    regions: ref.watch(settingsProvider.select((s) => s.privacyRegions)),
  ),
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

/// De ruwe scan: álle bevindingen, óók die op een al afgehandelde slide.
///
/// [privacyScanProvider] filtert die laatste eruit — precies goed voor het
/// paneel, precies fout voor een gate. Een gate moet weten hoevéél er is
/// afgehandeld om te kunnen zeggen dat er niets meer openstaat; een scan waaruit
/// het afgehandelde al verdwenen is, kan dat verschil niet meer maken.
///
/// Beide leiden hieruit af, zodat de scanner één keer per deckwijziging draait
/// in plaats van twee keer.
final privacyRawScanProvider = Provider<PrivacyScanResult>(
  computePrivacyRawScan,
);

/// De export-samenvatting voor de statusbalk: hoeveel bevindingen staan er nog
/// open, en hoeveel zijn er geaccepteerd, geshield of geredigeerd.
final privacyExportSummaryProvider = Provider<PrivacyExportSummary>(
  computePrivacyExportSummary,
);

/// Top-level, zodat `AppShell` dezelfde berekening per tab kan overriden.
///
/// Beide providers lezen het gescopede deck. Zonder die override lossen ze op in
/// de root-container, zien ze een leeg deck en doen ze stilletjes niets — precies
/// hoe `imageContrastIssuesProvider` ooit stukging. `provider_scope_test.dart`
/// bewaakt dat.
PrivacyScanResult computePrivacyRawScan(Ref ref) {
  final enabled = ref.watch(
    settingsProvider.select((s) => s.privacyChecksEnabled),
  );
  if (!enabled) return PrivacyScanResult.empty;

  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return PrivacyScanResult.empty;

  return ref.watch(privacyScannerProvider).scan(deck);
}

PrivacyScanResult computePrivacyScan(Ref ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return PrivacyScanResult.empty;

  final scan = ref.watch(privacyRawScanProvider);

  // Bevindingen op een slide die de auteur al heeft afgehandeld (accept, shield
  // of redact) verdwijnen uit het paneel. Blijven melden over een beslissing die
  // al genomen is, leert de gebruiker precies één ding: dat hij deze meldingen
  // kan negeren.
  //
  // Let op: dit onderdrukt de MELDING, niet de redactie. Die zit in
  // PrivacyProjection, die zijn eigen scan draait en deze instelling negeert.
  return PrivacyScanResult([
    for (final finding in scan.findings)
      if (!_isResolved(deck, finding)) finding,
  ]);
}

PrivacyExportSummary computePrivacyExportSummary(Ref ref) {
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  if (deck == null) return PrivacyExportSummary.empty;
  return summarisePrivacyForExport(deck, ref.watch(privacyRawScanProvider));
}

bool _isResolved(Deck deck, PrivacyFinding finding) {
  final slide = finding.isDeckWide || finding.slideIndex >= deck.slides.length
      ? null
      : deck.slides[finding.slideIndex];
  return effectivePrivacyDisposition(
    deck: deck.privacy,
    slide: slide?.privacy,
  ).isResolved;
}

List<SlideQualityIssue> computePrivacyQualityIssues(Ref ref) {
  return privacyIssuesFrom(
    ref.watch(privacyScanProvider),
    strictSeverity: ref.watch(
      settingsProvider.select((s) => s.privacyStrictSeverity),
    ),
  );
}
