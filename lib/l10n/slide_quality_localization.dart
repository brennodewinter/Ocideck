import '../l10n/app_localizations.dart';
import '../models/markdown_validation.dart';
import '../models/slide_quality.dart';

String slideQualityCategoryLabel(
  AppLocalizations l10n,
  SlideQualityCategory category,
) {
  return switch (category) {
    SlideQualityCategory.altText => l10n.d('Alt-tekst'),
    SlideQualityCategory.contrast => l10n.d('Contrast'),
    SlideQualityCategory.textDensity => l10n.d('Tekstdichtheid'),
  };
}

String formatSlideQualityIssue(AppLocalizations l10n, SlideQualityIssue issue) {
  String label(String key) => l10n.d(issue.args[key] ?? key);

  return switch (issue.kind) {
    SlideQualityIssueKind.missingAltCaption =>
      '${label('label')} ${l10n.d('heeft geen bijschrift/alt-tekst.')}',
    SlideQualityIssueKind.themeContrast => _formatThemeContrast(l10n, issue),
    SlideQualityIssueKind.slideContrast => _formatSlideContrast(l10n, issue),
    SlideQualityIssueKind.imageContrastUnverified => l10n.d(
      'Contrast van tekst op of over een afbeelding kan niet automatisch worden gecontroleerd — controleer visueel.',
    ),
    SlideQualityIssueKind.chartMissingDescription => l10n.d(
      'Grafiek heeft geen titel of beschrijvende data — voeg een titel of seriesnamen toe.',
    ),
    SlideQualityIssueKind.mediaMissingDescription =>
      '${label('label')} ${l10n.d('heeft geen titel of sprekernotities die de inhoud beschrijven.')}',
    SlideQualityIssueKind.textDensityWarning =>
      '${l10n.d('Veel tekst op deze slide: het lettertype wordt verkleind tot ')}'
      '${issue.args['percent']}${l10n.d(' van de ontwerpgrootte.')}',
    SlideQualityIssueKind.textDensityCritical =>
      '${l10n.d('Veel tekst op deze slide: het lettertype wordt sterk verkleind (')}'
      '${issue.args['percent']}${l10n.d('van de ontwerpgrootte). Overweeg de inhoud te splitsen.')}',
    SlideQualityIssueKind.tableDensityMinimum =>
      '${l10n.d('Grote tabel (')}${issue.args['rows']}${l10n.d(' rijen, ')}'
      '${issue.args['cols']}${l10n.d(' kolommen): celtekst staat op het minimumformaat.')}',
    SlideQualityIssueKind.codeDensityHigh =>
      '${l10n.d('Veel broncode (')}${issue.args['lines']}'
      '${l10n.d(' regels) — de tekst wordt sterk verkleind om te passen.')}',
    SlideQualityIssueKind.freeMarkdownDensityHigh =>
      '${l10n.d('Veel vrije markdown (')}${issue.args['lines']}'
      '${l10n.d(' regels) — controleer of alles leesbaar blijft op de slide.')}',
    SlideQualityIssueKind.titleDensityHigh =>
      '${l10n.d('Lange titelpagina (')}${issue.args['chars']}'
      '${l10n.d(' tekens) — de tekst wordt verkleind om te passen.')}',
  };
}

String _formatThemeContrast(AppLocalizations l10n, SlideQualityIssue issue) {
  final large = issue.args['largeText'] == 'true';
  final suffix = large
      ? l10n.d(':1 voor grote tekst).')
      : l10n.d(':1 voor normale tekst).');
  return '${l10n.d(issue.args['label'] ?? '')}: ${l10n.d('contrastverhouding')} '
      '${issue.args['ratio']}:1 ${l10n.d('(minimaal ')}${issue.args['threshold']}$suffix';
}

String _formatSlideContrast(AppLocalizations l10n, SlideQualityIssue issue) {
  return '${l10n.d(issue.args['label'] ?? '')}: ${l10n.d('contrastverhouding')} '
      '${issue.args['ratio']}:1 ${l10n.d('(minimaal ')}${issue.args['threshold']}${l10n.d(':1).')}';
}

MarkdownValidationSeverity? slideQualitySeverityForField({
  required SlideQualityResult result,
  required int slideIndex,
  required String field,
}) {
  final match = result.issues.where(
    (i) => i.slideIndex == slideIndex && i.field == field,
  );
  if (match.isEmpty) return null;
  if (match.any((i) => i.severity == MarkdownValidationSeverity.error)) {
    return MarkdownValidationSeverity.error;
  }
  return MarkdownValidationSeverity.warning;
}
