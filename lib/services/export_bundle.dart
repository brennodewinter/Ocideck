// Alles wat een export nodig heeft, voor één doelgroepprofiel.
//
// Dit bestaat om een spanning op te lossen die anders niet op te lossen was. De
// gebruiker moet in het exportdialoog kunnen kiezen vóór wie de export bedoeld is
// — de opdrachtgever krijgt alles, de bredere kring krijgt het geredigeerde
// exemplaar. Maar het dialoog mág de bron niet hebben: dat is de hele
// projectiegrens (`PrivacyProjection`).
//
// De oplossing is een fabriek. Het dialoog krijgt een functie die per profiel een
// bundel oplevert, en die functie sluit in de shell om de bron heen. Het dialoog
// kan er dus alleen `AudienceDeck`s uit halen — nooit het origineel — en de grens
// blijft staan terwijl de keuze toch in het dialoog ligt.

import '../models/redaction_manifest.dart';
import 'privacy/privacy_export_policy.dart';
import 'privacy/privacy_projection.dart';

/// Eén doelgroepprofiel, uitgewerkt.
class ExportBundle {
  /// Het geprojecteerde deck: pixels, notities, metadata.
  final AudienceDeck audience;

  /// De markdown voor de HTML-export. Uit hetzelfde geprojecteerde deck — de
  /// HTML zet de markdown letterlijk in het bestand.
  final String markdown;

  /// Het redactiemanifest van dít profiel. Bevat de salts; het exemplaar dat
  /// meereist met het geredigeerde rapport is `manifest.withoutSalts`.
  final RedactionManifest manifest;

  /// Wat er in het deck zit, geteld naar wat de auteur ermee heeft gedaan.
  final PrivacyExportSummary privacySummary;

  const ExportBundle({
    required this.audience,
    required this.markdown,
    required this.manifest,
    required this.privacySummary,
  });
}
