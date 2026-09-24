import 'app_localizations.dart';
import '../models/markdown_validation.dart';

/// Localiseert een headless Marp-bevinding pas aan de rand van de interface.
/// De service retourneert stabiele codes, zodat tests en opslaglogica niet van
/// één interfacetaal afhankelijk zijn.
String localizeMarpCompatibilityIssue(
  AppLocalizations l10n,
  MarkdownValidationIssue issue,
) => switch (issue.code) {
  'marp.frontMatter' || 'marp.yaml' => l10n.d(
    'Markdown kon niet worden verwerkt. Controleer de syntax.',
  ),
  'marp.theme' => '${l10n.d('Thema')}: ${l10n.d('Niet beschikbaar')}',
  'marp.layout' => '${l10n.d('Indeling')}: ${l10n.d('Niet overgenomen')}',
  'marp.ocideckFeature' => l10n.d('Niet overgenomen'),
  'marp.media' => l10n.d('Niet beschikbaar'),
  'marp.privacy' => l10n.d('Mogelijk persoonsgegevens'),
  'marp.tlpExposure' => l10n.d(
    'Achtergehouden: strenger geclassificeerd dan de presentatie',
  ),
  'marp.skip' => l10n.d('Overgeslagen'),
  _ => issue.message,
};
