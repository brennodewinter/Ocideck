import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../l10n/slide_quality_navigation.dart';
import '../../models/markdown_validation.dart';
import '../../models/slide.dart';
import '../../models/slide_quality.dart';
import '../../services/privacy/privacy_lexicon_data.dart';
import '../../services/quality_autofix.dart';
import '../../state/deck_provider.dart';
import '../../state/deck_quality_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/image_contrast_provider.dart';
import '../../state/image_privacy_provider.dart';
import '../../state/improvement_provider.dart';
import '../../state/privacy_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/theme_logo_provider.dart';
import '../privacy_badge.dart' show privacyKatSvg;
import '../dialogs/slide_quality_details_dialog.dart';
import 'slide_quality_actions.dart';
import '../../theme/app_theme.dart';

/// Het gecombineerde kwaliteitsresultaat: de synchrone analyse plus de
/// asynchrone titel-afbeelding-contrastcheck. Gedeeld door het paneel en de
/// compacte samenvattingschip zodat beide dezelfde tellingen tonen. Gebruik
/// `.value` (niet `.asData?.value`) zodat de vorige uitslag blijft staan
/// terwijl de FutureProvider herlaadt — anders knippert de melding weg.
/// Privacybevindingen worden er als eigen categorie in gemengd (OCIWACHT
/// §2.1): een eigen paneel zou een tweede plek zijn om te kijken, en de
/// gebruiker kijkt hier al.
SlideQualityResult combinedSlideQualityResult(WidgetRef ref) {
  final syncResult = ref.watch(deckQualityProvider);
  final imageIssues = ref.watch(imageContrastIssuesProvider).value ?? const [];
  final logoIssues = ref.watch(themeLogoIssuesProvider).value ?? const [];
  final privacyIssues = ref.watch(privacyQualityIssuesProvider);
  final improvementIssues = ref.watch(improvementQualityIssuesProvider);
  // De beeldcontrole is asynchroon en mag de rest niet ophouden: zolang ze
  // draait toont het paneel gewoon de tekstbevindingen.
  final imagePrivacy = ref.watch(imagePrivacyIssuesProvider).value ?? const [];
  if (imageIssues.isEmpty &&
      logoIssues.isEmpty &&
      privacyIssues.isEmpty &&
      improvementIssues.isEmpty &&
      imagePrivacy.isEmpty) {
    return syncResult;
  }
  // `deckQualityProvider` filtert de geaccepteerde slides al weg, maar de
  // asynchrone contrastcheck komt langs die filter heen binnen. Zonder deze
  // regel zou een slide waarvan de auteur de kwaliteit accepteert tóch blijven
  // melden — precies één check lang, en dat is het soort gat waar het
  // vertrouwen in de hele acceptatie op stukloopt.
  final deck = ref.watch(deckProvider.select((state) => state.deck));
  return SlideQualityResult([
    ...syncResult.issues,
    for (final issue in imageIssues)
      if (deck == null || !isQualityAccepted(deck, issue.slideIndex)) issue,
    // Deckbreed: een stijlprofiel-logo hoort bij geen enkele slide en is dus
    // nooit geaccepteerd — net als de privacy- en verbeteringsmeldingen.
    ...logoIssues,
    ...privacyIssues,
    ...improvementIssues,
    ...imagePrivacy,
  ]);
}

/// De achtergrond- en voorgrondkleur horend bij de ernst van [result].
({Color bg, Color fg}) slideQualityColors(SlideQualityResult result) {
  final hasErrors = result.errorCount > 0;
  final hasWarnings = result.warningCount > 0;
  final bg = !result.hasIssues
      ? AppTheme.successBg
      : hasErrors
      ? AppTheme.dangerBg
      : hasWarnings
      ? AppTheme.warningBg
      : AppTheme.infoBg;
  final fg = !result.hasIssues
      ? AppTheme.successFg
      : hasErrors
      ? AppTheme.dangerFg
      : hasWarnings
      ? AppTheme.warningFg
      : AppTheme.slate600;
  return (bg: bg, fg: fg);
}

class SlideQualityPanel extends ConsumerStatefulWidget {
  /// In [embedded]-modus rendert het paneel alleen de uitgeklapte inhoud
  /// (zonder eigen kopregel): de samenvatting/toggle staat dan als
  /// [SlideQualitySummaryChip] in de editor-kopregel.
  final bool embedded;

  const SlideQualityPanel({super.key, this.embedded = false});

  @override
  ConsumerState<SlideQualityPanel> createState() => _SlideQualityPanelState();
}

/// Compacte kwaliteits-samenvatting voor de editor-kopregel: statusicoon +
/// telling, klikbaar om het [SlideQualityPanel] (embedded) eronder te tonen.
class SlideQualitySummaryChip extends ConsumerWidget {
  final bool open;
  final VoidCallback onToggle;

  const SlideQualitySummaryChip({
    super.key,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final result = combinedSlideQualityResult(ref);
    final (:bg, :fg) = slideQualityColors(result);
    // Alleen het woord "Kwaliteit" met de statuskleur; de telling zit in de
    // tooltip en in het uitgeklapte paneel (zie [SlideQualityPanel]).
    return Tooltip(
      message: formatSlideQualityCountSummary(l10n, result),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                result.hasIssues
                    ? Icons.accessibility_new_outlined
                    : Icons.check_circle_outline,
                size: 14,
                color: fg,
              ),
              const SizedBox(width: 5),
              Text(
                l10n.d('Kwaliteit'),
                style: TextStyle(
                  fontSize: 11.5,
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 15,
                color: fg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// De repareerknop naast de Kwaliteit-chip, zichtbaar zodra de slide die je nu
/// bewerkt klein wordt gerenderd doordat hij een gesplitste reeks deelt met een
/// veel vollere pagina.
///
/// Staat hier en niet alleen in het paneel omdat dit de melding is die je juist
/// niet gaat zoeken: de slide op je scherm ziet er kapot uit terwijl er niets
/// mis is met zijn eigen tekst, en in het paneel staat hij ónder de meldingen
/// van de volle pagina. Verder niets: dit is geen tweede plek voor alle fixes,
/// alleen voor de melding waarvan de oorzaak niet op deze slide te zien is.
class SplitRunDetachChip extends ConsumerWidget {
  const SplitRunDetachChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(editorProvider).selectedIndex;
    final issue = combinedSlideQualityResult(ref).issues
        .where(
          (i) =>
              i.kind == SlideQualityIssueKind.splitRunDragged &&
              i.slideIndex == index,
        )
        .firstOrNull;
    if (issue == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final action = detachSplitPageAction(l10n: l10n, ref: ref, issue: issue);
    if (action == null) return const SizedBox.shrink();

    // De volledige uitleg zit in de tooltip: in de kopregel is geen ruimte voor
    // twee zinnen, maar zonder het waaróm is repareren een sprong in het duister
    // — en de knop noemt niet wat hij precies losmaakt.
    return Tooltip(
      message: '${action.label}\n\n${formatSlideQualityIssue(l10n, issue)}',
      child: InkWell(
        onTap: action.run,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 14, color: AppTheme.dangerFg),
              const SizedBox(width: 5),
              Text(
                l10n.d('Repareer slide'),
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.dangerFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideQualityPanelState extends ConsumerState<SlideQualityPanel> {
  var _expanded = false;
  MarkdownValidationSeverity? _severityFilter;

  void _handleIssueTap(SlideQualityIssue issue) {
    navigateToSlideQualityIssue(context: context, ref: ref, issue: issue);
  }

  /// De "wie niet wil nadenken"-knop (#915): werkt in één klik alle structureel
  /// en veilig oplosbare problemen weg, met steeds de veiligste keuze. Wat
  /// overblijft (zoals alt-tekst en privacy) vraagt om een menselijke keuze en
  /// blijft gewoon in de lijst staan — daarom een terugkoppeling die dat ook
  /// zegt in plaats van "alles opgelost".
  void _fixAllProblems() {
    final applied = ref.read(deckProvider.notifier).fixAllStructuralIssues();
    if (!mounted) return;
    final l10n = context.l10n;
    final message = applied > 0
        ? l10n.d(
            'Automatisch oplosbare problemen aangepakt. Wat overblijft vraagt om een keuze.',
          )
        : l10n.d(
            'Niets dat zich vanzelf laat oplossen — dit vraagt om een keuze.',
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// De assistent-acties die deze melding direct oplossen of de gebruiker
  /// naar de juiste plek brengen ("Splits slide", "Verhoog contrast",
  /// "Voeg alt-tekst toe", …).
  List<SlideQualityAction> _actionsFor(SlideQualityIssue issue) =>
      buildSlideQualityActions(context: context, ref: ref, issue: issue);

  /// De dia waar deze melding op zit, of null bij een deckbrede melding of een
  /// index die niet (meer) bestaat. Alleen de plaatsaanduiding van een tabelcel
  /// heeft hem nodig, en die mag nooit de reden zijn dat het paneel omvalt.
  Slide? _slideFor(SlideQualityIssue issue) {
    if (issue.isDeckWide) return null;
    final slides = ref.read(deckProvider).deck?.slides;
    if (slides == null) return null;
    if (issue.slideIndex < 0 || issue.slideIndex >= slides.length) return null;
    return slides[issue.slideIndex];
  }

  List<SlideQualityIssue> _filteredIssues(SlideQualityResult result) {
    if (_severityFilter == null) return result.issues;
    return result.issues
        .where((issue) => issue.severity == _severityFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = combinedSlideQualityResult(ref);
    final deck = ref.watch(deckProvider.select((state) => state.deck));
    final visibleIssues = _filteredIssues(result);
    final (:bg, :fg) = slideQualityColors(result);
    final iconColor = fg;
    // In embedded-modus staat de samenvatting/toggle in de kopregel; toon dan
    // meteen de inhoud zonder eigen kopregel.
    final expanded = widget.embedded || _expanded;
    final summary = formatSlideQualityCountSummary(l10n, result);

    return Material(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryHeader(l10n, result, iconColor, summary),
          if (!result.hasIssues && expanded)
            ..._performedChecksList(l10n, iconColor),
          if (result.hasIssues) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => showSlideQualityDetailsDialog(
                      context,
                      result: result,
                      onIssueTap: _handleIssueTap,
                      actionsFor: _actionsFor,
                    ),
                    icon: const Icon(Icons.list_alt_outlined, size: 13),
                    label: Text(l10n.d('Bekijk meldingen…')),
                    style: TextButton.styleFrom(
                      foregroundColor: iconColor,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  // Alleen aanbieden als de motor op dít deck werkelijk íets
                  // wegwerkt (#915, #1280): een deck met enkel alt-tekst- of
                  // privacymeldingen — of een woord-melding op een dia die te
                  // weinig bullets heeft om te splitsen — heeft geen toepasbare
                  // fix, en dan zou de knop een belofte doen die hij niet
                  // waarmaakt. Ook veilig corrigeerbaar themacontrast telt mee.
                  // [hasApplicableStructuralFix] spiegelt de echte
                  // motorpoort, zodat knop zichtbaar ⇔ er wordt ook echt gefixt.
                  if (deck != null && hasApplicableStructuralFix(deck))
                    TextButton.icon(
                      onPressed: _fixAllProblems,
                      icon: const Icon(Icons.auto_fix_high, size: 13),
                      label: Text(l10n.d('Los automatisch op wat kan')),
                      style: TextButton.styleFrom(
                        foregroundColor: iconColor,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (expanded && result.hasIssues) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: Text(l10n.d('Alle meldingen')),
                    selected: _severityFilter == null,
                    onSelected: (_) => setState(() => _severityFilter = null),
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 10),
                  ),
                  for (final severity in MarkdownValidationSeverity.values)
                    if (result.issuesWithSeverity(severity).isNotEmpty)
                      FilterChip(
                        label: Text(
                          '${slideQualitySeverityLabel(l10n, severity)} '
                          '(${result.issuesWithSeverity(severity).length})',
                        ),
                        selected: _severityFilter == severity,
                        onSelected: (selected) => setState(
                          () => _severityFilter = selected ? severity : null,
                        ),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 10),
                      ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: visibleIssues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final issue = visibleIssues[index];
                  return _QualityIssueTile(
                    issue: issue,
                    slide: _slideFor(issue),
                    onTap: () => _handleIssueTap(issue),
                    actions: _actionsFor(issue),
                    showThemeHint:
                        issue.isDeckWide && !issueBelongsToDeckInfo(issue),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// De kopregel met statusicoon en telling. Interactief (met chevron) in het
  /// standalone paneel; statisch in embedded-modus (daar is de toggle de
  /// compacte chip in de editor-kopregel).
  Widget _summaryHeader(
    AppLocalizations l10n,
    SlideQualityResult result,
    Color iconColor,
    String summary,
  ) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            result.hasIssues
                ? Icons.accessibility_new_outlined
                : Icons.check_circle_outline,
            size: 14,
            color: iconColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${l10n.d('Slidekwaliteit')}: $summary',
              style: TextStyle(fontSize: 11, color: iconColor),
            ),
          ),
          if (!widget.embedded)
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: iconColor,
            ),
        ],
      ),
    );
    if (widget.embedded) return row;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: row,
    );
  }

  List<Widget> _performedChecksList(AppLocalizations l10n, Color iconColor) {
    final privacyEnabled = ref.watch(
      settingsProvider.select((s) => s.privacyChecksEnabled),
    );
    // De taaldekking van het trefwoordlexicon (OCIWACHT §13.3). Alleen relevant
    // zolang de controle überhaupt draait — staat ze uit, dan is dát de melding.
    final deckLanguage = ref.watch(
      deckProvider.select((state) => state.deck?.language ?? ''),
    );
    final coverage = privacyEnabled && deckLanguage.isNotEmpty
        ? privacyLexiconCoverage(deckLanguage)
        : PrivacyLexiconCoverage.covered;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.d('Uitgevoerde controles')}:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
            for (final check in slideQualityPerformedChecks(
              l10n,
              privacyEnabled: privacyEnabled,
            ))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: 12, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            check.title,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: iconColor,
                            ),
                          ),
                          // Drie niveaus in dit blok, en ze zaten tot #780 in
                          // de dekking: 100 / 85 / 70 procent van `iconColor`.
                          // Dat las als "iets rustiger" maar is een kleur die
                          // niemand heeft nagerekend — en die de tokentoets
                          // niet ziet, want die meet het token en niet zijn
                          // verzwakking. In donkere modus zakte de foutstaat
                          // naar 3,68:1; in lichte modus zakten álle vier de
                          // staten op 70% naar 2,99-3,44:1. Uitgerekend in het
                          // paneel dat de gebruiker over contrast vertelt.
                          //
                          // De rangorde zit nu in het gewicht en de schuinte:
                          // vet - normaal - cursief. Die is even leesbaar en
                          // blijft op de gemeten verhouding van het paar staan.
                          Text(
                            check.detail,
                            style: TextStyle(fontSize: 10, color: iconColor),
                          ),
                          Text(
                            check.params,
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: iconColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // Staat de privacycontrole uit, dan zwijgen is het gevaarlijkste wat
            // dit paneel kan doen: de balk is groen, de lijst erboven ziet er
            // compleet uit, en "niets gevonden" leest als "er zit niets in".
            // Terwijl er niet eens gekeken is.
            if (!privacyEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.remove_circle_outline,
                      size: 12,
                      color: AppTheme.warningFg,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.d(
                          'Niet gecontroleerd: persoonsgegevens, bijzondere gegevens en geheimen. De privacycontrole staat uit bij Beveiliging.',
                        ),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warningFg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Draait de controle wél, maar is er voor de taal van dit deck geen
            // trefwoordenlijst, dan is de stilte over bijzondere gegevens net zo
            // misleidend. `Deck.language` valt voor meldingsteksten terug op
            // Engels — daar is dat goed — maar een lexicon dat terugvalt is
            // erger dan geen lexicon: Poolse tekst scannen met Engelse
            // triggerwoorden geeft bijna nul recall, en niemand merkt het.
            if (coverage != PrivacyLexiconCoverage.covered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.translate, size: 12, color: AppTheme.warningFg),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        coverage == PrivacyLexiconCoverage.none
                            ? l10n.d(
                                'Voor de taal van dit deck is er geen trefwoordenlijst voor bijzondere persoonsgegevens. Patronen met een controlegetal (BSN, IBAN, paspoort) werken wel; woorden als "diagnose" of "verdachte" worden niet herkend.',
                              )
                            : l10n.d(
                                'Voor de taal van dit deck ontbreken de ziekte- en aandoeningsnamen. Religie, politieke overtuiging en vakbondstermen worden wel herkend, en controlegetallen (BSN, IBAN, paspoort) werken altijd — maar reken er niet op dat een diagnose gevonden wordt.',
                              ),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warningFg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

class _QualityIssueTile extends StatelessWidget {
  final SlideQualityIssue issue;

  /// De dia waar de melding op zit, voor zover die er is — nodig om een
  /// tabelcel als rij en kolom te kunnen aanwijzen.
  final Slide? slide;

  final VoidCallback? onTap;

  /// Assistent-acties die deze melding in één klik oplossen (splitsen,
  /// contrast verhogen, alt-tekst toevoegen, …).
  final List<SlideQualityAction> actions;
  final bool showThemeHint;

  const _QualityIssueTile({
    required this.issue,
    this.slide,
    this.onTap,
    this.actions = const [],
    this.showThemeHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = slideQualitySeverityColor(issue.severity);
    // Deckbreed is niet vanzelf "thema": een privacybevinding op het auteurs- of
    // trefwoordenveld staat in de front matter. "Thema (hele presentatie)" boven
    // zo'n melding stuurt de blik naar de kleuren en dus naar de verkeerde plek.
    final location = issueBelongsToDeckInfo(issue)
        ? l10n.d('Presentatiegegevens')
        : issue.isDeckWide
        ? l10n.d('Thema (hele presentatie)')
        : '${l10n.d('Slide')} ${issue.slideIndex + 1}';
    // Het veld erbij, als we het kennen. "Slide 5 · Privacy" zegt dát er iets
    // is; "Slide 5 · Privacy · Opsomming 3" zegt waar je moet kijken.
    final field = slideQualityFieldLabel(l10n, issue, slide: slide);
    final heading = [
      location,
      slideQualityCategoryLabel(l10n, issue.category),
      ?field,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Een privacybevinding krijgt het eigen merkteken in plaats van het
            // generieke waarschuwingsicoon: zo is in één oogopslag te zien dat
            // een melding over persoonsgegevens gaat en niet over contrast of
            // tekstdichtheid. De ernst blijft in de kleur van de tekst zitten.
            if (issue.category == SlideQualityCategory.privacy)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SvgPicture.string(privacyKatSvg, width: 13, height: 13),
              )
            else
              Icon(
                slideQualitySeverityIcon(issue.severity),
                size: 13,
                color: color,
              ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    formatSlideQualityIssue(l10n, issue),
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final action in actions)
                            TextButton.icon(
                              onPressed: action.run,
                              icon: Icon(action.icon, size: 13),
                              label: Text(action.label),
                              style: TextButton.styleFrom(
                                foregroundColor: color,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                showThemeHint ? Icons.palette_outlined : Icons.arrow_forward,
                size: 12,
                // Om dezelfde reden als de regels hierboven niet op 70%: dit
                // pijltje is de enige aanwijzing dát de kaart aanklikbaar is,
                // en op 70% zat het in lichte modus op 3,35:1 (#780).
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}
