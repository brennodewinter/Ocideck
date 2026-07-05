import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../l10n/app_localizations.dart';
import '../models/markdown_validation.dart';
import '../models/slide_quality.dart';
import '../services/slide_layout_metrics.dart'
    show kTextDensityCriticalScale, kTextDensityWarningScale;
import '../services/slide_quality_analyzer.dart'
    show
        kAverageBulletWordWarningCount,
        kBulletDisplayLevelWarning,
        kChecklistBulletWarningCount,
        kQuoteDensityCharThreshold,
        kSingleColumnBulletCriticalCount,
        kSingleColumnBulletWarningCount,
        kSingleColumnWordWarningCount,
        kTitleDensityCharThreshold,
        kTwoColumnBulletCriticalCount,
        kTwoColumnBulletWarningCount,
        kTwoColumnWordWarningCount;
import '../utils/color_contrast.dart' show kWcagCriticalBodyText;

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

/// Vervangt `{sleutel}`-plaatshouders in een vertaalde template door de echte
/// drempelwaarden. Zo blijven de cijfers één bron (de constanten) en hoeft de
/// vertaling alleen de tekst eromheen te dekken.
String _fillParams(String template, Map<String, Object> values) {
  var out = template;
  values.forEach((key, value) => out = out.replaceAll('{$key}', '$value'));
  return out;
}

/// De controles die de slidekwaliteit-analyse altijd uitvoert, met per controle
/// een korte verantwoording ([detail]) en de geldende parameters ([params],
/// opgebouwd uit de echte drempelconstanten). Getoond bij een groene balk zodat
/// duidelijk is wat er is gecontroleerd, hoe en met welke grenzen. Houd in lijn
/// met de checks in [SlideQualityAnalyzer.analyzeSlides].
List<({String title, String detail, String params})>
slideQualityPerformedChecks(AppLocalizations l10n) {
  // De tekstkrimp-grenzen worden als percentage getoond.
  final warnPct = (kTextDensityWarningScale * 100).round();
  final critPct = (kTextDensityCriticalScale * 100).round();
  // Elke d()-string is één enkele literal: de l10n-volledigheidstest leest per
  // .d(...) maar één string, dus geen aaneengeschakelde literals gebruiken.
  return [
    (
      title: l10n.d('Contrast en leesbaarheid van tekstkleuren'),
      detail: l10n.d(
        'Thema, slides, footer, checklist en titels over afbeeldingen, getoetst aan WCAG AA (4,5:1 voor tekst, 3:1 voor grote tekst).',
      ),
      params: _fillParams(
        l10n.d(
          'Bodytekst met contrast onder {crit}:1 telt als fout; daarboven tot de AA-norm als waarschuwing.',
        ),
        {'crit': kWcagCriticalBodyText.toStringAsFixed(1)},
      ),
    ),
    (
      title: l10n.d(
        'Alt-teksten en bijschriften van afbeeldingen, grafieken en media',
      ),
      detail: l10n.d(
        'Elke afbeelding, grafiek, video en audio heeft een beschrijving nodig voor schermlezers en bijsluiters.',
      ),
      params: l10n.d(
        'Geen drempelwaarde: een niet-lege beschrijving is verplicht.',
      ),
    ),
    (
      title: l10n.d('Aanwezigheid van gekoppelde mediabestanden'),
      detail: l10n.d(
        'Verwijzingen naar afbeeldingen, video en audio worden gecontroleerd op een bestaand bestand in het project.',
      ),
      params: l10n.d(
        'Geen drempelwaarde: het gekoppelde bestand moet binnen de projectmap bestaan.',
      ),
    ),
    (
      title: l10n.d(
        'Tekstdichtheid: bullets, woorden, quotes, tabellen en code',
      ),
      detail: l10n.d(
        'Aantal en lengte van bullets, woorden, nesting, kolombalans en de dichtheid van quotes, titels, tabellen en code zodat alles leesbaar past.',
      ),
      params: _fillParams(
        l10n.d(
          'Waarschuwing boven {b1} bullets (1 kolom), {bcl} (checklist) of {b2} (2 kolommen); kritiek boven {bc1} of {bc2}. Woorden boven {w1}/{w2}, gemiddeld boven {avg} per bullet. Quote boven {q} tekens, titel boven {t} tekens. Nesting dieper dan niveau {lvl}. Tekst die tot onder {warn}% moet krimpen waarschuwt, onder {crit}% is kritiek.',
        ),
        {
          'b1': kSingleColumnBulletWarningCount,
          'bcl': kChecklistBulletWarningCount,
          'b2': kTwoColumnBulletWarningCount,
          'bc1': kSingleColumnBulletCriticalCount,
          'bc2': kTwoColumnBulletCriticalCount,
          'w1': kSingleColumnWordWarningCount,
          'w2': kTwoColumnWordWarningCount,
          'avg': kAverageBulletWordWarningCount,
          'q': kQuoteDensityCharThreshold,
          't': kTitleDensityCharThreshold,
          'lvl': kBulletDisplayLevelWarning,
          'warn': warnPct,
          'crit': critPct,
        },
      ),
    ),
  ];
}

Color slideQualitySeverityColor(MarkdownValidationSeverity severity) {
  return switch (severity) {
    MarkdownValidationSeverity.error => AppTheme.danger700,
    MarkdownValidationSeverity.warning => AppTheme.warningFg,
    MarkdownValidationSeverity.informational => AppTheme.slate600,
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
    SlideQualityCategory.content => l10n.d('Inhoud'),
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
    SlideQualityIssueKind.questionNotAnswerable => l10n.d(
      'Vraag is niet speelbaar: geef minstens één goed én één fout antwoord op.',
    ),
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
