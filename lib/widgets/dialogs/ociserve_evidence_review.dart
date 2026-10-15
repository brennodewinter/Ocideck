import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_evidence.dart';
import '../../models/ociserve_evidence_item.dart';

/// Het bewijsstuk dat bij een upload hoort, als de cursist het heeft ingediend.
OciServeEvidenceItem? evidenceItemFor(
  EvidenceUpload upload,
  List<OciServeEvidenceItem> items,
) {
  for (final item in items) {
    if (item.uploadId == upload.id) return item;
  }
  return null;
}

/// De titel van de bewijssoort, of `null` als de soort niet (meer) bekend is.
String? evidenceTypeTitle(
  OciServeEvidenceItem item,
  List<OciServeEvidenceType> types,
) {
  for (final type in types) {
    if (type.id == item.evidenceTypeId) return type.title;
  }
  return null;
}

/// Label en kleur van de beoordelingsstatus van een bewijsstuk.
(String, Color) evidenceItemLabel(
  AppLocalizations l10n,
  ThemeData theme,
  OciServeEvidenceContentStatus status,
) => switch (status) {
  OciServeEvidenceContentStatus.ingediend => (
    l10n.d('Ingediend'),
    theme.colorScheme.tertiary,
  ),
  OciServeEvidenceContentStatus.inBehandeling => (
    l10n.d('In behandeling'),
    theme.colorScheme.tertiary,
  ),
  OciServeEvidenceContentStatus.geaccepteerd => (
    l10n.d('Geaccepteerd'),
    theme.colorScheme.primary,
  ),
  OciServeEvidenceContentStatus.aanvullingGevraagd => (
    l10n.d('Aanvulling gevraagd'),
    theme.colorScheme.error,
  ),
  OciServeEvidenceContentStatus.afgewezen => (
    l10n.d('Afgekeurd'),
    theme.colorScheme.error,
  ),
  OciServeEvidenceContentStatus.ingetrokken => (
    l10n.d('Ingetrokken'),
    theme.colorScheme.error,
  ),
  OciServeEvidenceContentStatus.verlopen => (
    l10n.d('Verlopen'),
    theme.colorScheme.error,
  ),
};

/// Wat er met het bewijsstuk gebeurt, in gewone taal. Een negatieve uitkomst
/// noemt de opmerking van de beoordelaar als die er is.
String evidenceItemMessage(AppLocalizations l10n, OciServeEvidenceItem item) {
  final note = item.reviewNote;
  final hasNote = note != null && note.isNotEmpty;
  return switch (item.status) {
    OciServeEvidenceContentStatus.ingediend => l10n.d(
      'Ingediend. Een beoordelaar kijkt ernaar.',
    ),
    OciServeEvidenceContentStatus.inBehandeling => l10n.d(
      'In behandeling bij een beoordelaar.',
    ),
    OciServeEvidenceContentStatus.geaccepteerd => l10n.d(
      'Geaccepteerd. Het bewijsstuk is goedgekeurd.',
    ),
    OciServeEvidenceContentStatus.aanvullingGevraagd =>
      hasNote
          ? l10n
                .d('Aanvulling gevraagd: {opmerking}')
                .replaceAll('{opmerking}', note)
          : l10n.d('Aanvulling gevraagd.'),
    OciServeEvidenceContentStatus.afgewezen =>
      hasNote
          ? l10n.d('Afgekeurd: {reden}').replaceAll('{reden}', note)
          : l10n.d('Afgekeurd. De beoordelaar heeft geen reden opgegeven.'),
    OciServeEvidenceContentStatus.ingetrokken => l10n.d(
      'Het bewijsstuk is ingetrokken.',
    ),
    OciServeEvidenceContentStatus.verlopen => l10n.d(
      'Het bewijsstuk is verlopen.',
    ),
  };
}
