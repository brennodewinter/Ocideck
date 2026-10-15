part of 'dossier_overview.dart';

enum _EntryAction {
  verify,
  refresh,
  history,
  details,
  number,
  up,
  down,
  remove,
}

(IconData, String, Color) _status(
  BuildContext context,
  DossierIntegrityStatus? status,
  AppPalette palette,
) {
  final l10n = context.l10n;
  return switch (status) {
    DossierIntegrityStatus.matches => (
      Icons.check_circle_rounded,
      l10n.d('SHA-256 klopt'),
      palette.panelText,
    ),
    DossierIntegrityStatus.changed => (
      Icons.error_rounded,
      l10n.d('Document gewijzigd'),
      AppTheme.amberVivid,
    ),
    DossierIntegrityStatus.missing => (
      Icons.error_outline_rounded,
      l10n.d('Document ontbreekt'),
      AppTheme.amberVivid,
    ),
    DossierIntegrityStatus.unreadable => (
      Icons.warning_rounded,
      l10n.d('Document niet leesbaar'),
      AppTheme.amberVivid,
    ),
    DossierIntegrityStatus.unsafe => (
      Icons.warning_rounded,
      l10n.d('Onveilige bestandsverwijzing'),
      AppTheme.amberVivid,
    ),
    null => (
      Icons.shield_outlined,
      l10n.d('Nog niet gecontroleerd'),
      palette.panelText.withValues(alpha: 0.82),
    ),
  };
}
