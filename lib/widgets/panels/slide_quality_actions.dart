import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_navigation.dart';
import '../../models/slide_quality.dart';
import '../../state/deck_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/editor_provider.dart';
import '../../utils/bullet_fixes.dart';
import '../../utils/title_contrast.dart';

/// Eén concrete vervolgactie bij een kwaliteitsmelding: het "doen"-knopje
/// naast de melding, zodat de assistent niet alleen signaleert maar ook
/// meteen de oplossing aanbiedt ("Splits deze slide", "Verhoog contrast",
/// "Voeg alt-tekst toe", …).
class SlideQualityAction {
  final String label;
  final IconData icon;
  final VoidCallback run;

  const SlideQualityAction({
    required this.label,
    required this.icon,
    required this.run,
  });
}

/// Meegetrokken door een overvolle pagina in dezelfde split-run: haal die pagina
/// uit de reeks, dan komt deze slide terug op zijn eigen grootte. De overvolle
/// pagina zelf houdt zijn eigen meldingen en acties — losmaken zegt alleen dat
/// hij niet bij de lijst hoort, het maakt hem niet korter.
///
/// `null` wanneer deze melding er niet over gaat.
///
/// Publiek omdat dezelfde actie op twee plekken zit: in het kwaliteitspaneel
/// naast de melding, en als knop naast de Kwaliteit-chip in de editor-kopregel
/// (waar je hem nodig hebt zónder eerst het paneel open te klappen).
SlideQualityAction? detachSplitPageAction({
  required AppLocalizations l10n,
  required WidgetRef ref,
  required SlideQualityIssue issue,
}) {
  if (issue.kind != SlideQualityIssueKind.splitRunDragged) return null;
  final offender = int.tryParse(issue.args['offender'] ?? '');
  if (offender == null) return null;
  return SlideQualityAction(
    label: l10n.d('Haal volle pagina uit de reeks'),
    icon: Icons.link_off,
    run: () => ref.read(deckProvider.notifier).detachSplitPage(offender),
  );
}

/// De acties die deze melding direct kunnen oplossen (of de gebruiker naar
/// de juiste plek brengen), in volgorde van voorkeur. Leeg wanneer er niets
/// beters is dan de gewone tik-navigatie van de melding zelf.
List<SlideQualityAction> buildSlideQualityActions({
  required BuildContext context,
  required WidgetRef ref,
  required SlideQualityIssue issue,
}) {
  final l10n = context.l10n;
  final actions = <SlideQualityAction>[];
  final deck = ref.read(deckProvider).deck;
  final slide =
      (deck != null &&
          !issue.isDeckWide &&
          issue.slideIndex >= 0 &&
          issue.slideIndex < deck.slides.length)
      ? deck.slides[issue.slideIndex]
      : null;

  void navigate() =>
      navigateToSlideQualityIssue(context: context, ref: ref, issue: issue);

  // Privacy: de ontsnappingsklep. Wie één regel te luid vindt, moet chirurgisch
  // kunnen ingrijpen — anders is "de hele controle uitzetten" de enige uitweg, en
  // dat is in de praktijk onomkeerbaar: wie hem eenmaal uit heeft, zet hem niet
  // meer aan.
  final rule = issue.args['rule'];
  if (issue.category == SlideQualityCategory.privacy && rule != null) {
    actions.add(
      SlideQualityAction(
        label: l10n.d('Deze regel nooit meer melden'),
        icon: Icons.notifications_off_outlined,
        run: () => ref
            .read(settingsProvider.notifier)
            .setPrivacyRuleEnabled(rule, false),
      ),
    );
  }

  if (issue.isDeckWide) {
    return [...actions, _deckWideAction(l10n, issue, navigate)];
  }

  // Titeltekst over een achtergrondafbeelding: pas de aanbevolen
  // contrast-fix uit de melding toe (overlay en/of tekstkleur).
  if (issue.kind == SlideQualityIssueKind.titleImageContrast && slide != null) {
    final fix = TitleContrastFix.values.firstWhere(
      (f) => f.name == issue.args['fix'],
      orElse: () => TitleContrastFix.none,
    );
    if (fix != TitleContrastFix.none) {
      actions.add(
        SlideQualityAction(
          label: l10n.d('Verhoog contrast'),
          icon: Icons.auto_fix_high,
          run: () => ref
              .read(deckProvider.notifier)
              .updateSlide(issue.slideIndex, applyTitleContrastFix(slide, fix)),
        ),
      );
    }
  }

  // Ontbrekende alt-tekst of beschrijving: spring naar het juiste veld.
  if (issue.category == SlideQualityCategory.altText &&
      issue.kind != SlideQualityIssueKind.missingMediaFile &&
      issue.kind != SlideQualityIssueKind.externalMediaFile) {
    actions.add(
      SlideQualityAction(
        label: issue.kind == SlideQualityIssueKind.missingAltCaption
            ? l10n.d('Voeg alt-tekst toe')
            : l10n.d('Voeg beschrijving toe'),
        icon: Icons.edit_note,
        run: navigate,
      ),
    );
  }

  // Te volle slides: splitsen lost het in één klik op.
  if (issue.category == SlideQualityCategory.textDensity &&
      slide != null &&
      canSplitSlide(slide)) {
    final index = issue.slideIndex;
    actions.add(
      SlideQualityAction(
        label: l10n.d('Splits slide'),
        icon: Icons.call_split,
        run: () {
          ref.read(deckProvider.notifier).splitSlide(index);
          ref.read(editorProvider.notifier).select(index + 1);
        },
      ),
    );
  }

  final detach = detachSplitPageAction(l10n: l10n, ref: ref, issue: issue);
  if (detach != null) actions.add(detach);

  // Meerzinnige bullets: knip ze op zinsgrenzen in losse bullets.
  if (issue.kind == SlideQualityIssueKind.bulletMultiSentence &&
      slide != null &&
      canSplitSentenceBullets(slide)) {
    actions.add(
      SlideQualityAction(
        label: l10n.d('Zinnen naar losse bullets'),
        icon: Icons.format_list_bulleted,
        run: () => ref
            .read(deckProvider.notifier)
            .updateSlide(
              issue.slideIndex,
              splitSentenceBullets(slide),
              bumpRevision: true,
            ),
      ),
    );
  }

  // Overvolle bullets van de vorm "label : uitleg": haal de uitleg van de slide
  // af naar de notities, zodat alleen het label overblijft. De aanvulling op
  // "Splits slide" en "Zinnen naar losse bullets", die beide álle tekst op de
  // slide laten staan — deze haalt tekst wég.
  if (issue.category == SlideQualityCategory.textDensity &&
      slide != null &&
      canTrimBulletExplanations(slide)) {
    actions.add(
      SlideQualityAction(
        label: l10n.d('Uitleg naar notities'),
        icon: Icons.notes,
        run: () => ref
            .read(deckProvider.notifier)
            .updateSlide(
              issue.slideIndex,
              trimBulletExplanations(slide),
              bumpRevision: true,
            ),
      ),
    );
  }

  return actions;
}

/// De handeling bij een deckbrede melding.
///
/// Deckbreed is twee dingen. Een contrastmelding gaat over het thema en wordt in
/// de kleurinstellingen opgelost; een privacybevinding op de front matter
/// (auteur, organisatie, trefwoorden) hoort in de presentatiegegevens thuis.
/// Beide "Open kleurinstellingen" noemen stuurde de tweede soort de verkeerde
/// kant op, met een knop die de verkeerde belofte deed.
SlideQualityAction _deckWideAction(
  AppLocalizations l10n,
  SlideQualityIssue issue,
  VoidCallback navigate,
) {
  if (issueBelongsToDeckInfo(issue)) {
    return SlideQualityAction(
      label: l10n.d('Open presentatiegegevens'),
      icon: Icons.info_outline,
      run: navigate,
    );
  }
  return SlideQualityAction(
    label: l10n.d('Open kleurinstellingen'),
    icon: Icons.palette_outlined,
    run: navigate,
  );
}
