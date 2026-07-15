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

  // Deck-wijd = thema: de oplossing zit in de kleurinstellingen.
  if (issue.isDeckWide) {
    actions.add(
      SlideQualityAction(
        label: l10n.d('Open kleurinstellingen'),
        icon: Icons.palette_outlined,
        run: navigate,
      ),
    );
    return actions;
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
      issue.kind != SlideQualityIssueKind.missingMediaFile) {
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
  // "Splits slide" en "Zinnen naar losse bullets", die beide álle tekst laten
  // staan — deze haalt tekst wég.
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
