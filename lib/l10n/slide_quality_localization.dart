import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';

import '../l10n/app_localizations.dart';
import '../models/markdown_validation.dart';
import '../models/slide.dart';
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

/// Waar op de slide een melding zit, in leesbare vorm: `Opsomming 3`, `Notities`.
///
/// Dit is het antwoord op de vraag die een melding zonder plaatsaanduiding
/// oproept: *waar dan?* Een privacybevinding weet dat allang — veldnaam en
/// fragmentindex zitten in het model — maar tot nu toe kwam die kennis niet
/// verder dan de scanner. Op een slide met veertig regels tekst is "persoonsnaam
/// (B…r)" zonder plaats geen melding maar een zoekopdracht.
///
/// Geeft `null` voor een veld dat we niet kennen: liever geen aanduiding dan een
/// verkeerde.
///
/// [slide] is de dia waar de melding op zit, als de aanroeper hem heeft. Alleen
/// een tabel heeft hem nodig — zie [_tableCellLabel] — en zonder blijft de
/// aanduiding bij het kale "Tabel".
String? slideQualityFieldLabel(
  AppLocalizations l10n,
  SlideQualityIssue issue, {
  Slide? slide,
}) {
  final field = issue.field;
  if (field == null || field.isEmpty) return null;
  if (field == 'tableRows') return _tableCellLabel(l10n, issue, slide);
  final label = switch (field) {
    'title' => l10n.d('Titel'),
    'subtitle' => l10n.d('Ondertitel'),
    'bullets' => l10n.d('Opsomming'),
    'bullets2' => l10n.d('Tweede opsomming'),
    'columnTitle1' => l10n.d('Kop kolom 1'),
    'columnTitle2' => l10n.d('Kop kolom 2'),
    'quote' => l10n.d('Citaat'),
    'quoteAuthor' => l10n.d('Bron citaat'),
    'imageCaption' => l10n.d('Bijschrift'),
    'imageCaption2' => l10n.d('Tweede bijschrift'),
    'imageAltText' || 'imageAltText2' => l10n.d('Alt-tekst'),
    'customMarkdown' => l10n.d('Inhoud'),
    'notes' => l10n.d('Notities'),
    'imagePath' || 'imagePath2' => l10n.d('Afbeelding'),
    'videoPath' => l10n.d('Video'),
    'audioPath' => l10n.d('Audio'),
    'deckTitle' => l10n.d('Titel'),
    'author' => l10n.d('Auteur'),
    'organization' => l10n.d('Organisatie'),
    'description' => l10n.d('Beschrijving'),
    'keywords' => l10n.d('Trefwoorden'),
    // De overige frontmatter-velden ontbraken hier, waardoor een bevinding op
    // bijvoorbeeld het versieveld zonder plaatsaanduiding in het paneel kwam —
    // "Presentatiegegevens · Privacy" en verder zoeken maar.
    'version' => l10n.d('Versie'),
    'date' => l10n.d('Datum'),
    'standardsUsed' => l10n.d('Gebruikte standaarden'),
    'toolsUsed' => l10n.d('Gebruikte hulpmiddelen'),
    'miauwWaivers' => l10n.d('Motivering van een uitsluiting'),
    'miauwConfirmations' => l10n.d('Motivering van een bevestiging'),
    _ => null,
  };
  if (label == null) return null;

  // Een samengesteld veld krijgt het volgnummer erbij: `Opsomming 3` wijst aan,
  // `Opsomming` laat nog steeds zoeken. Enkelvoudige velden hebben altijd
  // fragment 0 en krijgen dus vanzelf niets.
  final fragment = issue.span?.fragmentIndex ?? 0;
  if (fragment == 0) return label;
  return '$label ${fragment + 1}';
}

/// De plaatsaanduiding van een tabelcel: rij en kolom, zoals de auteur ze telt.
///
/// De scanner bewaart één doorlopende celindex (`rij × staplengte + kolom`),
/// want daar heeft de redactie genoeg aan. Getoond als volgnummer werd dat
/// "Tabel 14" — een getal dat nergens op de slide staat en dat je zonder de
/// tabelbreedte niet eens kunt terugrekenen. Dat is geen plaatsaanduiding maar
/// een tweede raadsel bovenop het eerste.
///
/// De staplengte is de breedste rij, precies zoals bij het scannen: alleen dan
/// komt de cel weer op zijn eigen plek terug, ook bij een tabel met ongelijke
/// rijen. Zonder de dia kan die berekening niet, en dan blijft het bij "Tabel" —
/// liever geen aanduiding dan een verkeerde.
String _tableCellLabel(
  AppLocalizations l10n,
  SlideQualityIssue issue,
  Slide? slide,
) {
  final label = l10n.d('Tabel');
  final index = issue.span?.fragmentIndex ?? 0;
  final rows = slide?.tableRows;
  if (rows == null || rows.isEmpty) return label;
  final stride = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  if (stride == 0) return label;
  final row = index ~/ stride;
  final column = index % stride;
  if (row >= rows.length) return label;
  // De koprij heeft geen nummer op het scherm — de editor noemt hem "Koprij" —
  // dus krijgt hij hier ook geen nummer. De rijen daaronder tellen mee vanaf de
  // bovenkant, zoals het oog ze telt.
  return _fillParams(
    row == 0
        ? l10n.d('Tabel koprij, kolom {kolom}')
        : l10n.d('Tabel rij {rij}, kolom {kolom}'),
    {'rij': row + 1, 'kolom': column + 1},
  );
}

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

/// De controles die de slidekwaliteit-analyse uitvoert, met per controle een
/// korte verantwoording ([detail]) en de geldende parameters ([params],
/// opgebouwd uit de echte drempelconstanten). Getoond bij een groene balk zodat
/// duidelijk is wat er is gecontroleerd, hoe en met welke grenzen. Houd in lijn
/// met de checks in [SlideQualityAnalyzer.analyzeSlides].
///
/// De privacycontrole staat er alleen in als hij ook echt heeft gedraaid
/// ([privacyEnabled]). De kop boven deze lijst zegt "uitgevoerde controles", en
/// een controle die uitstaat opvoeren onder die kop is precies de leugen die een
/// groene balk gevaarlijk maakt: dan leest "niets gevonden" als "er zit niets
/// in". Staat hij uit, dan zegt het paneel dát in plaats hiervan — zie
/// [SlideQualityPanel].
List<({String title, String detail, String params})>
slideQualityPerformedChecks(
  AppLocalizations l10n, {
  required bool privacyEnabled,
}) {
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
    if (privacyEnabled)
      (
        title: l10n.d(
          'Persoonsgegevens, bijzondere gegevens en geheimen in de tekst',
        ),
        detail: l10n.d(
          'Slides, notities, tabellen, code, bestandspaden en URL\'s worden op dit apparaat doorzocht op identificerende nummers, financiële gegevens, contactgegevens, digitale identificatoren, geheimen, bijzondere persoonsgegevens (AVG art. 9/10), massagegevens en metadatalekken.',
        ),
        params:
            '${l10n.d('Alleen een zekere treffer waarschuwt; waarschijnlijk en mogelijk blijven informatief. Een uitgezette regel vuurt nergens.')} '
            '${l10n.d('De controle garandeert niet dat alles wordt gevonden; ze verkleint de kans dat er persoonsgegevens onbedoeld uitlekken.')}',
      ),
  ];
}

Color slideQualitySeverityColor(MarkdownValidationSeverity severity) {
  return switch (severity) {
    // Het kwaliteitspaneel is chrome, dus de mode-afhankelijke variant. De
    // andere twee waren dat al.
    MarkdownValidationSeverity.error => AppTheme.dangerFg,
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
    SlideQualityCategory.privacy => l10n.d('Privacy'),
    SlideQualityCategory.improvement => l10n.d('Procesverbetering'),
    SlideQualityCategory.callout => l10n.d('Afbeeldingsverwijzingen'),
  };
}

/// De meldingen waar een stuk tekst van de auteur in staat — een pad, een
/// bloklabel, een sectienaam. Die vullen we rechtstreeks in en nooit via
/// `l10n.d()`: het is geen bronstring maar inhoud van de gebruiker.
///
/// Samen in één helper omdat ze dezelfde vorm delen, en omdat de switch in
/// [formatSlideQualityIssue] anders over de methodegrens loopt.
String _formatWithAuthorText(
  AppLocalizations l10n,
  SlideQualityIssue issue,
) => switch (issue.kind) {
  // Deckbreed: het logo wijst naar niets. Het pad staat erbij omdat de
  // gebruiker juist dan wil weten waar de app zocht — zonder blijft "logo
  // ontbreekt" een raadsel bovenop een lege hoek (#1298).
  SlideQualityIssueKind.themeLogoMissing =>
    l10n
        .d(
          'Het logo van dit stijlprofiel is niet gevonden en wordt niet getoond (pad: {pad}). Kies een logo in de presentatie-instellingen.',
        )
        .replaceAll('{pad}', issue.args['path'] ?? ''),
  SlideQualityIssueKind.themeLogoDarkMissing => l10n.d(
    'De dia-achtergrond is donker, maar het logo heeft geen donkere variant. Het logo is op de dia vrijwel onzichtbaar. Stel een donker logo in de presentatie-instellingen.',
  ),
  // Non-lineaire navigatie (#1162): het label van het blok dat nergens meer
  // uitkomt.
  SlideQualityIssueKind.danglingJump =>
    l10n
        .d(
          'De sprong "{doel}" wijst naar een dia die niet meer bestaat; tijdens het presenteren gebeurt er niets. Kies een andere doeldia.',
        )
        .replaceAll('{doel}', issue.args['label'] ?? ''),
  // De vier standaardkoppen blijven onvertaald — het zijn de
  // taalonafhankelijke ankers die in de `.md` staan.
  _ =>
    l10n
        .d(
          'De sectie "{sectie}" is geen standaardsectie van een bevinding en wordt niet getoond of geëxporteerd (de inhoud blijft wel in het bronbestand). Hernoem de kop naar Description, Confirmation (reproduction), Possible impact of Recommendation.',
        )
        .replaceAll('{sectie}', issue.args['section'] ?? ''),
};

String formatSlideQualityIssue(AppLocalizations l10n, SlideQualityIssue issue) {
  String label(String key) => l10n.d(issue.args[key] ?? key);

  final message = switch (issue.kind) {
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
          '${issue.args['percent']}${l10n.d(' van de ontwerpgrootte). Overweeg de inhoud te splitsen.')}',
    // Eén hele zin met plaatshouders in plaats van aan elkaar geplakte
    // fragmenten: de woordvolgorde verschilt per taal, dus een vertaler moet de
    // getallen kunnen verplaatsen.
    SlideQualityIssueKind.splitRunDragged =>
      '${l10n.d('Deze slide rendert op {klein} van de ontwerpgrootte in plaats van {eigen}, omdat hij een gesplitste reeks deelt met de veel vollere slide {pagina}.').replaceAll('{klein}', issue.args['percent'] ?? '').replaceAll('{eigen}', issue.args['own'] ?? '').replaceAll('{pagina}', issue.args['page'] ?? '')} '
          '${l10n.d('Niet de tekst op deze slide is het probleem, maar de reeks.')}',
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
          '${l10n.d('bullets')}). ${l10n.d('Overweeg de inhoud te splitsen.')}',
    SlideQualityIssueKind.bulletCountCritical =>
      '${l10n.d('Erg veel bullets op deze slide')} (${issue.args['count']} '
          '${l10n.d('bullets')}). '
          '${l10n.d('Splits deze inhoud over meerdere slides.')}',
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
          '${issue.args['right']} ${l10n.d('bullets')}). '
          '${l10n.d('Verdeel of splits de inhoud.')}',
    SlideQualityIssueKind.questionAnswerCountHigh =>
      l10n
          .d(
            'Vraag is niet speelbaar: {aantal} antwoorden, terwijl deze vraagsoort er maximaal {maximum} toestaat.',
          )
          .replaceAll('{aantal}', issue.args['count'] ?? '')
          .replaceAll('{maximum}', issue.args['maximum'] ?? ''),
    SlideQualityIssueKind.missingMediaFile =>
      '${label('label')}${l10n.d(': bestand niet gevonden (')}'
          '${issue.args['path'] ?? ''}).',
    SlideQualityIssueKind.externalMediaFile =>
      '${label('label')}${l10n.d(': ligt buiten de presentatie en gaat niet mee (')}'
          '${issue.args['path'] ?? ''}). '
          '${l10n.d('Sla de presentatie op om een kopie te maken.')}',
    SlideQualityIssueKind.themeLogoMissing ||
    SlideQualityIssueKind.themeLogoDarkMissing ||
    SlideQualityIssueKind.danglingJump ||
    SlideQualityIssueKind.findingUnknownSection => _formatWithAuthorText(
      l10n,
      issue,
    ),
    SlideQualityIssueKind.questionNotAnswerable => l10n.d(
      'Vraag is niet speelbaar: geef minstens één goed én één fout antwoord op.',
    ),
    SlideQualityIssueKind.emptySlide => l10n.d(
      'Deze dia is leeg: hij toont niets op het scherm en in de export.',
    ),
    SlideQualityIssueKind.privacyIdentifier ||
    SlideQualityIssueKind.privacyFinancial ||
    SlideQualityIssueKind.privacyContact ||
    SlideQualityIssueKind.privacyDigital ||
    SlideQualityIssueKind.privacySecret ||
    SlideQualityIssueKind.privacySpecialCategory ||
    SlideQualityIssueKind.privacyBulk ||
    SlideQualityIssueKind.privacyStructural => _formatPrivacy(l10n, issue),
    SlideQualityIssueKind.privacyImage => _formatImagePrivacy(l10n, issue),
    SlideQualityIssueKind.privacyImageUnreadable => l10n.d(
      'Deze afbeelding kon niet worden nagekeken op gezichten. Het formaat wordt niet ondersteund (HEIC bijvoorbeeld). Dat betekent niet dat er niemand op staat — er is niet gekeken.',
    ),
    SlideQualityIssueKind.improvementOrphanId =>
      '${l10n.d('Golden-thread-id')} ${issue.args['id'] ?? ''} '
          '${l10n.d('wordt ergens genoemd maar staat niet op een boom-dia — definieer hem op een CTQ- of Ishikawa-boom.')}',
    SlideQualityIssueKind.improvementUnusedId =>
      '${l10n.d('Golden-thread-id')} ${issue.args['id'] ?? ''} '
          '${l10n.d('staat op een boom-dia maar wordt nergens anders gebruikt — koppel hem aan een matrix, stroom of andere dia.')}',
    SlideQualityIssueKind.calloutInvalidGeometry =>
      '${l10n.d('Afbeeldingsverwijzing')} ${issue.args['ref'] ?? ''} '
          '${l10n.d('heeft ongeldige coördinaten en wordt niet getekend — pas de doelpositie aan in de verwijzingeneditor.')}',
    SlideQualityIssueKind.calloutOrphanReference =>
      '${l10n.d('Afbeeldingsverwijzing')} ${issue.args['ref'] ?? ''} '
          '${l10n.d('verwijst naar een (A)-markering die niet in de tekst staat, of omgekeerd — zet de letter in de tekst of verwijder de verwijzing.')}',
    SlideQualityIssueKind.calloutDuplicateReference =>
      '${l10n.d('Afbeeldingsverwijzing')} ${issue.args['ref'] ?? ''} '
          '${l10n.d('komt twee keer voor op deze dia — elke markering (A), (B) … mag maar één verwijzing hebben.')}',
    SlideQualityIssueKind.calloutMissingAnchor => l10n.d(
      'Deze dia heeft afbeeldingsverwijzingen maar geen anker — de verwijzingen kunnen niet aan de dia worden gekoppeld. Geef de dia een anker in de editor.',
    ),
    SlideQualityIssueKind.calloutCrossingArrows => l10n.d(
      'Pijlen kruisen elkaar op deze dia — overweeg pinmarkeringen in plaats van pijlen voor leesbaarheid.',
    ),
    SlideQualityIssueKind.calloutTargetOutOfView =>
      '${l10n.d('Afbeeldingsverwijzing')} ${issue.args['ref'] ?? ''} '
          '${l10n.d('valt buiten het zichtbare deel van de afbeelding — pas het focuspunt, zoom of doelpositie aan, of de markering verschijnt niet op de dia.')}',
  };

  // Een over meerdere split-pagina's samengevatte dichtheidsmelding (#1289):
  // zeg er eerlijk bij op hoeveel pagina's van de reeks hij staat, zodat de ene
  // regel niet als een enkele-pagina-probleem leest.
  final runPages = issue.args['runPages'];
  if (runPages == null) return message;
  return '$message '
      '${l10n.d('Geldt voor {n} slides van deze gesplitste reeks.').replaceAll('{n}', runPages)}';
}

/// De tekst van een privacybevinding.
///
/// `args['sample']` is een gemaskeerd fragment (`j…l`), nooit de volledige
/// waarde: deze melding belandt in een paneel en een tooltip, en een
/// privacycontrole die de gevonden BSN's in haar eigen meldingen zet, heeft het
/// probleem verplaatst in plaats van opgelost.
String _formatPrivacy(AppLocalizations l10n, SlideQualityIssue issue) {
  final rule = privacyRuleLabel(l10n, issue.args['rule'] ?? '');
  final sample = issue.args['sample'] ?? '';
  final suffix = issue.severity == MarkdownValidationSeverity.informational
      ? l10n.d(
          ' Zonder context in de tekst is dit mogelijk geen persoonsgegeven.',
        )
      : l10n.d(' Overweeg dit te redigeren met [[dubbele blokhaken]].');
  // Een API-sleutel is geen persoonsgegeven maar een geheim, en een diagnose is
  // geen gewoon persoonsgegeven maar een bijzonder. Ze allemaal hetzelfde noemen
  // maakt de melding onbegrijpelijk voor precies wie hem moet lezen.
  final prefix = switch (issue.kind) {
    SlideQualityIssueKind.privacySecret => l10n.d('Mogelijk geheim'),
    SlideQualityIssueKind.privacySpecialCategory => l10n.d(
      'Bijzonder persoonsgegeven (AVG art. 9/10)',
    ),
    _ => l10n.d('Mogelijk persoonsgegeven'),
  };
  return '$prefix — $rule ($sample).${_privacySuffix(l10n, issue, suffix)}';
}

/// De staart van de melding.
///
/// Bij een geëscaleerd bijzonder gegeven zegt hij *waarom* de melding zwaarder
/// is: er staat iemand op de slide om het aan te koppelen. Zonder die uitleg
/// leest de gebruiker een willekeurige verzwaring in plaats van een reden.
String _privacySuffix(
  AppLocalizations l10n,
  SlideQualityIssue issue,
  String fallback,
) {
  if (issue.kind == SlideQualityIssueKind.privacySpecialCategory &&
      issue.severity != MarkdownValidationSeverity.informational) {
    return l10n.d(
      ' Op deze slide staat ook een identificerend gegeven, dus dit is herleidbaar tot een persoon.',
    );
  }
  return fallback;
}

/// De tekst van een beeldbevinding.
///
/// Zegt bewust "gezicht" en niet "persoon". De detector vindt gezichten, en
/// mist dus iemand van achteren, in profiel, of met het hoofd buiten de
/// uitsnede. Een melding die "persoon" belooft, belooft meer dan er gekeken is.
String _formatImagePrivacy(AppLocalizations l10n, SlideQualityIssue issue) {
  final count = int.tryParse(issue.args['sample'] ?? '') ?? 1;
  // Twee complete zinnen in plaats van losse woorden aan elkaar geplakt: de
  // woordvolgorde van "toont N gezichten" verschilt per taal, en een vertaler
  // die alleen `herkenbare gezichten` te zien krijgt kan er niets mee.
  // "Minstens", omdat de detector structureel ondertelt en nooit overtelt: hij
  // vindt gezichten, dus iemand van achteren of met het hoofd buiten de uitsnede
  // ontbreekt per definitie. Voor de waarschuwing maakt het niets uit — één
  // gezicht is al een persoonsgegeven — maar een exact klinkend getal zou meer
  // beloven dan er gekeken is.
  final lead = count == 1
      ? l10n.d('Deze afbeelding toont minstens één herkenbaar gezicht.')
      : _fillParams(
          l10n.d(
            'Deze afbeelding toont minstens {count} herkenbare gezichten.',
          ),
          {'count': count},
        );
  return '$lead ${l10n.d('Een afbeelding waarop iemand herkenbaar staat is een persoonsgegeven, ook zonder naam erbij.')}';
}

/// Het leesbare label van een detectieregel.
///
/// Acroniemen blijven onvertaald; die zijn in elke taal hetzelfde.
String privacyRuleLabel(AppLocalizations l10n, String ruleId) {
  return switch (ruleId) {
    'nl.bsn' => l10n.d('burgerservicenummer (BSN)'),
    'nl.btw_id_legacy' => l10n.d('oud btw-nummer (bevat een BSN)'),
    'nl.vnummer' => l10n.d('vreemdelingennummer (V-nummer)'),
    'nl.anummer' => l10n.d('administratienummer (A-nummer)'),
    'nl.big' => l10n.d('BIG-nummer van een zorgverlener'),
    'nl.agb' => l10n.d('AGB-code'),
    'nl.pv_nummer' => l10n.d('proces-verbaalnummer'),
    'fin.iban' => l10n.d('bankrekeningnummer (IBAN)'),
    // Zelfde begrip voor de gebruiker als een IBAN: er staat een
    // bankrekening op de slide. Het onderscheid tussen de twee notaties is
    // een detail van de regel, niet van de melding.
    'fin.us_routing' => l10n.d('bankrekeningnummer (IBAN)'),
    'fin.pan' => l10n.d('creditcardnummer'),
    'fin.cvv' => l10n.d('beveiligingscode van een creditcard'),
    'contact.email' => l10n.d('e-mailadres'),
    'contact.phone' => l10n.d('telefoonnummer'),
    'contact.address' => l10n.d('adres'),
    'contact.postcode_nl' => l10n.d('postcode'),
    'nl.plate' => l10n.d('kenteken'),
    // De buitenlandse postcodes dragen hun landcode in het regel-id (`de.postcode`)
    // omdat de regiopoort daaraan hangt. Voor de gebruiker is dat één begrip: er
    // staat een postcode. De landcode zit al in de melding via de tekst eromheen.
    _ when ruleId.endsWith('.postcode') => l10n.d('postcode'),
    'contact.name' => l10n.d('persoonsnaam'),
    'contact.birthdate' => l10n.d('geboortedatum'),
    'contact.geo' => l10n.d('locatiecoördinaten'),
    'doc.mrz' => l10n.d('machineleesbare zone van een paspoort of ID'),
    'digital.ipv4' || 'digital.ipv6' => l10n.d('IP-adres'),
    'digital.mac' => l10n.d('MAC-adres van een apparaat'),
    'digital.imei' => l10n.d('IMEI van een toestel'),
    'digital.iccid' => l10n.d('ICCID van een simkaart'),
    'digital.imsi' => l10n.d('IMSI van een abonnee'),
    'digital.handle' => l10n.d('sociale-mediaprofiel'),
    'digital.deviceid' => l10n.d('advertentie- of apparaat-ID'),
    'image.face' => l10n.d('herkenbaar gezicht op een afbeelding'),
    'special.health' => l10n.d('gezondheidsgegeven'),
    // De rol reist mee in het regel-label, want dát is de plek waar de melding
    // hem laat zien. "Strafrechtelijk gegeven" zegt niet wie er in beeld is, en
    // juist dat verschil is het punt van fase 14: een aangeefster is geen
    // verdachte. Zonder herkende rol blijft het bij de neutrale formulering —
    // liever niets zeggen dan het verkeerde.
    'special.criminal.suspect' => l10n.d('strafrechtelijk gegeven (verdachte)'),
    'special.criminal.reporter' => l10n.d(
      'strafrechtelijk gegeven (aangever of slachtoffer)',
    ),
    'special.criminal.witness' => l10n.d('strafrechtelijk gegeven (getuige)'),
    'special.criminal' => l10n.d('strafrechtelijk gegeven'),
    'special.religion' => l10n.d('religie of levensovertuiging'),
    'special.union' => l10n.d('vakbondslidmaatschap'),
    'special.biometric' => l10n.d('biometrisch gegeven'),
    'special.politics' => l10n.d('politieke opvatting'),
    'special.ethnicity' => l10n.d('etnische afkomst'),
    'special.sexlife' => l10n.d('seksuele geaardheid'),
    'special.genetic' => l10n.d('genetisch gegeven'),
    'special.icd10' => l10n.d('diagnosecode (ICD-10)'),
    'special.atc' => l10n.d('geneesmiddelcode (ATC)'),
    'nl.parketnummer' => l10n.d('parketnummer'),
    'bulk.table_column' => l10n.d(
      'tabel met persoonsgegevens (rijen×kolommen)',
    ),
    'bulk.repeat' => l10n.d('massa-persoonsgegevens op één slide'),
    'bulk.quasi_combo' => l10n.d(
      'geboortedatum, postcode en geslacht samen — die drie wijzen meestal één persoon aan, ook zonder naam',
    ),
    'struct.user_path' => l10n.d('gebruikerspad met een naam erin'),
    'struct.url_token' => l10n.d('toegangstoken in een link'),
    'struct.url_pii' => l10n.d('persoonsgegeven in een link'),
    'struct.share_link' => l10n.d('deellink met ingebakken toegang'),
    'struct.mailto' => l10n.d('e-mailadres in een link'),
    'struct.notes_leak' => l10n.d(
      'gegevens in de sprekersnotities — onzichtbaar op de slide, wél in de export',
    ),
    'struct.data_uri' => l10n.d(
      'ingesloten afbeelding — wij kunnen er niet in kijken',
    ),
    'us.ein' => l10n.d('werkgeversnummer (EIN)'),
    'us.npi' => l10n.d('zorgverlenersnummer (NPI)'),
    'us.medicare_mbi' => l10n.d('Medicare-nummer (MBI) — een zorggegeven'),
    'us.ssn_last4' => l10n.d('laatste vier cijfers van een SSN'),
    'ca.ramq' => l10n.d('zorgverzekeringsnummer (RAMQ) — een zorggegeven'),
    'ca.ohip' => l10n.d('zorgverzekeringsnummer (OHIP) — een zorggegeven'),
    'ca.bn' => l10n.d('bedrijfsnummer (BN)'),
    'au.medicare' => l10n.d('Medicare-nummer — een zorggegeven'),
    'au.abn' || 'br.cnpj' => l10n.d('bedrijfsnummer'),
    _ when _nationalNumberNames.containsKey(ruleId) =>
      '${l10n.d('nationaal identificatienummer')} (${_nationalNumberNames[ruleId]})',
    'secret.private_key' => l10n.d('private sleutel'),
    'secret.jwt' => l10n.d('toegangstoken (JWT)'),
    'secret.azure' => l10n.d('Azure-sleutel of SAS-token'),
    'secret.hash' => l10n.d('wachtwoordhash'),
    'secret.totp' => l10n.d('TOTP-seed (tweede factor)'),
    'secret.entropy' => l10n.d('mogelijk een sleutel of wachtwoord'),
    'secret.connection_string' => l10n.d('databaseverbinding met wachtwoord'),
    'secret.password_plain' => l10n.d('wachtwoord in klare tekst'),
    _ when ruleId.startsWith('secret.') =>
      '${l10n.d('sleutel of token')} (${_secretVendors[ruleId] ?? ruleId})',
    _ => ruleId,
  };
}

/// De naam van een nationaal nummer. Eigennamen — die vertalen we niet: een
/// PESEL heet in elke taal een PESEL.
const Map<String, String> _nationalNumberNames = {
  'us.ssn': 'Social Security Number',
  'ca.sin': 'Social Insurance Number',
  'au.tfn': 'Tax File Number',
  'in.aadhaar': 'Aadhaar',
  'in.pan': 'PAN',
  'za.id': 'ID Number',
  'cw.sedula': 'sedula',
  'aw.persoonsnummer': 'persoonsnummer',
  'br.cpf': 'CPF',
  'us.itin': 'ITIN',
  'us.dea': 'DEA-nummer',
  'be.rijksregister': 'rijksregisternummer',
  'at.svnr': 'Sozialversicherungsnummer',
  'ch.ahv': 'AHV-Nummer',
  'cz.rodne_cislo': 'rodné číslo',
  'dk.cpr': 'CPR-nummer',
  'gr.amka': 'AMKA',
  'hu.taj': 'TAJ-szám',
  'ie.pps': 'PPS Number',
  'no.fodselsnummer': 'fødselsnummer',
  'si.emso': 'EMŠO',
  'de.steuer_id': 'Steuer-ID',
  'fr.nir': 'NIR',
  'es.dni': 'DNI/NIE',
  'pt.nif': 'NIF',
  'pl.pesel': 'PESEL',
  'it.codice_fiscale': 'codice fiscale',
  'hr.oib': 'OIB',
  'bg.egn': 'ЕГН',
  'ro.cnp': 'CNP',
  'se.personnummer': 'personnummer',
  'fi.hetu': 'henkilötunnus',
  'ee.isikukood': 'isikukood',
  'is.kennitala': 'kennitala',
  'lv.pk': 'personas kods',
  'lu.matricule': 'matricule',
  'cy.tic': 'TIC',
  'mt.id': 'ID Card Number',
  'li.peid': 'PEID',
  'uk.nhs': 'NHS',
  'uk.nino': 'NINO',
};

/// De leveranciersnaam bij een sleutelregel. Eigennamen — die vertalen we niet.
const Map<String, String> _secretVendors = {
  'secret.aws': 'AWS',
  'secret.gcp': 'Google',
  'secret.github': 'GitHub',
  'secret.gitlab': 'GitLab',
  'secret.slack': 'Slack',
  'secret.stripe': 'Stripe',
  'secret.llm': 'OpenAI / Anthropic',
  'secret.huggingface': 'Hugging Face',
  'secret.sendgrid': 'SendGrid',
  'secret.npm': 'npm',
};

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
