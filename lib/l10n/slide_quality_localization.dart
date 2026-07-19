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
String? slideQualityFieldLabel(AppLocalizations l10n, SlideQualityIssue issue) {
  final field = issue.field;
  if (field == null || field.isEmpty) return null;
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
    'tableRows' => l10n.d('Tabel'),
    'imagePath' || 'imagePath2' => l10n.d('Afbeelding'),
    'videoPath' => l10n.d('Video'),
    'audioPath' => l10n.d('Audio'),
    'deckTitle' => l10n.d('Titel'),
    'author' => l10n.d('Auteur'),
    'organization' => l10n.d('Organisatie'),
    'description' => l10n.d('Beschrijving'),
    'keywords' => l10n.d('Trefwoorden'),
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
    SlideQualityCategory.privacy => l10n.d('Privacy'),
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
  };
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
    'fin.iban' => l10n.d('bankrekeningnummer (IBAN)'),
    'contact.email' => l10n.d('e-mailadres'),
    'contact.phone' => l10n.d('telefoonnummer'),
    'contact.address' => l10n.d('adres'),
    'contact.postcode_nl' => l10n.d('postcode'),
    'contact.name' => l10n.d('persoonsnaam'),
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
    'special.criminal' => l10n.d('strafrechtelijk gegeven'),
    'special.religion' => l10n.d('religie of levensovertuiging'),
    'special.union' => l10n.d('vakbondslidmaatschap'),
    'special.biometric' => l10n.d('biometrisch gegeven'),
    'special.politics' => l10n.d('politieke opvatting'),
    'special.ethnicity' => l10n.d('etnische afkomst'),
    'special.sexlife' => l10n.d('seksuele geaardheid'),
    'special.genetic' => l10n.d('genetisch gegeven'),
    'nl.parketnummer' => l10n.d('parketnummer'),
    'bulk.table_column' => l10n.d(
      'tabel met persoonsgegevens (rijen×kolommen)',
    ),
    'bulk.repeat' => l10n.d('massa-persoonsgegevens op één slide'),
    'struct.user_path' => l10n.d('gebruikerspad met een naam erin'),
    'struct.url_token' => l10n.d('toegangstoken in een link'),
    'struct.url_pii' => l10n.d('persoonsgegeven in een link'),
    'struct.share_link' => l10n.d('deellink met ingebakken toegang'),
    'struct.mailto' => l10n.d('e-mailadres in een link'),
    'struct.data_uri' => l10n.d(
      'ingesloten afbeelding — wij kunnen er niet in kijken',
    ),
    _ when _euNumberNames.containsKey(ruleId) =>
      '${l10n.d('nationaal identificatienummer')} (${_euNumberNames[ruleId]})',
    'secret.private_key' => l10n.d('private sleutel'),
    'secret.jwt' => l10n.d('toegangstoken (JWT)'),
    'secret.connection_string' => l10n.d('databaseverbinding met wachtwoord'),
    'secret.password_plain' => l10n.d('wachtwoord in klare tekst'),
    _ when ruleId.startsWith('secret.') =>
      '${l10n.d('sleutel of token')} (${_secretVendors[ruleId] ?? ruleId})',
    _ => ruleId,
  };
}

/// De naam van een nationaal nummer. Eigennamen — die vertalen we niet: een
/// PESEL heet in elke taal een PESEL.
const Map<String, String> _euNumberNames = {
  'be.rijksregister': 'rijksregisternummer',
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
