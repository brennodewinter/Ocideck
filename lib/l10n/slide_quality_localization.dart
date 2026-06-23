import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/markdown_validation.dart';
import '../models/slide_quality.dart';

String formatSlideQualityCountSummary(
  AppLocalizations l10n,
  SlideQualityResult result,
) {
  if (!result.hasIssues) {
    return l10n.d('Geen kwaliteitsproblemen gevonden');
  }
  final parts = <String>[];
  if (result.errorCount > 0) {
    parts.add('${result.errorCount} ${l10n.d('fout(en)')}');
  }
  if (result.warningCount > 0) {
    parts.add('${result.warningCount} ${l10n.d('waarschuwing(en)')}');
  }
  if (result.infoCount > 0) {
    parts.add('${result.infoCount} ${l10n.d('tip(s)')}');
  }
  return parts.join(', ');
}

/// Localized summary used when export is blocked or needs acknowledgement.
String formatQualityExportReason(
  AppLocalizations l10n,
  SlideQualityResult result,
) {
  final parts = <String>[];
  if (result.errorCount > 0) {
    parts.add('${result.errorCount} ${l10n.d('ernstige probleem(en)')}');
  }
  if (result.warningCount > 0) {
    parts.add('${result.warningCount} ${l10n.d('waarschuwing(en)')}');
  }
  return '${l10n.d('De presentatie heeft kwaliteitsproblemen (')}'
      '${parts.join(', ')}).';
}

Color slideQualitySeverityColor(MarkdownValidationSeverity severity) {
  return switch (severity) {
    MarkdownValidationSeverity.error => const Color(0xFFB91C1C),
    MarkdownValidationSeverity.warning => const Color(0xFF92400E),
    MarkdownValidationSeverity.informational => const Color(0xFF475569),
  };
}

IconData slideQualitySeverityIcon(MarkdownValidationSeverity severity) {
  return switch (severity) {
    MarkdownValidationSeverity.error => Icons.error_outline,
    MarkdownValidationSeverity.warning => Icons.warning_amber_outlined,
    MarkdownValidationSeverity.informational => Icons.info_outline,
  };
}

String slideQualitySeverityLabel(
  AppLocalizations l10n,
  MarkdownValidationSeverity severity,
) {
  return switch (severity) {
    MarkdownValidationSeverity.error => l10n.d('Fouten'),
    MarkdownValidationSeverity.warning => l10n.d('Waarschuwingen'),
    MarkdownValidationSeverity.informational => l10n.d('Tips'),
  };
}

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
    SlideQualityIssueKind.footerContrast => _formatThemeContrast(l10n, issue),
    SlideQualityIssueKind.checklistContrast => _formatThemeContrast(
      l10n,
      issue,
    ),
    SlideQualityIssueKind.slideContrast => _formatSlideContrast(l10n, issue),
    SlideQualityIssueKind.imageContrastUnverified => l10n.d(
      'Contrast van tekst op of over een afbeelding kan niet automatisch worden gecontroleerd — controleer visueel.',
    ),
    SlideQualityIssueKind.titleImageContrast =>
      '${l10n.d('Titeltekst heeft te weinig contrast met de achtergrondafbeelding')} '
          '(${issue.args['ratio']}:1).',
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
    SlideQualityIssueKind.quoteDensityHigh =>
      '${l10n.d('Lange quote (')}${issue.args['chars']}'
          '${l10n.d(' tekens) — de tekst wordt verkleind om te passen.')}',
    SlideQualityIssueKind.bulletCountHigh =>
      '${l10n.d('Veel bullets op deze slide')} (${issue.args['count']} '
          'bullets). ${l10n.d('Overweeg de inhoud te splitsen.')}',
    SlideQualityIssueKind.bulletCountCritical =>
      '${l10n.d('Erg veel bullets op deze slide')} (${issue.args['count']} '
          'bullets). ${l10n.d('Splits deze inhoud over meerdere slides.')}',
    SlideQualityIssueKind.bulletWordCountHigh =>
      '${l10n.d('Veel woorden in bullets')} (${issue.args['words']} '
          '${l10n.d('woorden')}). ${l10n.d('Maak bullets korter of splits de slide.')}',
    SlideQualityIssueKind.bulletWordCountCritical =>
      '${l10n.d('Erg veel woorden in bullets')} (${issue.args['words']} '
          '${l10n.d('woorden')}). ${l10n.d('Splits deze inhoud over meerdere slides.')}',
    SlideQualityIssueKind.bulletAverageLengthHigh =>
      '${l10n.d('Gemiddeld lange bullets')} (${issue.args['average']} '
          '${l10n.d('woorden per bullet')}). ${l10n.d('Maak elke bullet kernachtiger.')}',
    SlideQualityIssueKind.bulletMultiSentence => l10n.d(
      'Bullet met meerdere zinnen gevonden. Maak bullets kernachtiger of splits de inhoud.',
    ),
    SlideQualityIssueKind.bulletNestingDeep =>
      '${l10n.d('Diepe bulletniveaus gevonden')} (${l10n.d('niveau')} '
          '${issue.args['level']}). ${l10n.d('Beperk nesting voor betere leesbaarheid.')}',
    SlideQualityIssueKind.bulletColumnImbalance =>
      '${l10n.d('Twee kolommen zijn sterk uit balans')} '
          '(${issue.args['left']} ${l10n.d('tegenover')} '
          '${issue.args['right']} bullets). '
          '${l10n.d('Verdeel of splits de inhoud.')}',
    SlideQualityIssueKind.missingMediaFile =>
      '${label('label')}${l10n.d(': bestand niet gevonden (')}'
          '${issue.args['path'] ?? ''}).',
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
  if (match.any((i) => i.severity == MarkdownValidationSeverity.warning)) {
    return MarkdownValidationSeverity.warning;
  }
  return MarkdownValidationSeverity.informational;
}
