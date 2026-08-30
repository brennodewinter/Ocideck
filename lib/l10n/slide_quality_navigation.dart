import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/slide_quality.dart';
import '../state/deck_provider.dart';
import '../state/editor_provider.dart';
import '../widgets/dialogs/presentation_info_dialog.dart';
import '../widgets/dialogs/settings_dialog.dart';
import '../widgets/editors/callout_editor.dart';

/// De deckbrede velden die in de front matter staan en dus in het venster
/// *Presentatiegegevens* worden bewerkt — niet in de kleurinstellingen.
///
/// Deckbreed betekende ooit vanzelf "thema", want alleen de contrastcontroles
/// meldden zich op dat niveau. Sinds de privacyscanner ook de front matter
/// leest, is dat niet meer waar: een e-mailadres in het auteursveld is
/// deckbreed én heeft niets met kleur te maken. De navigatie stuurde die
/// melding naar de kleurinstellingen, zocht daar een veld dat niet bestaat,
/// markeerde dus niets, en liet de gebruiker achter tussen kleurkiezers.
///
/// De lijst volgt `_deckFragments` in `privacy_scanner_fragments.dart`.
const Set<String> kDeckInfoFields = {
  'deckTitle',
  'author',
  'organization',
  'description',
  'keywords',
  'version',
  'date',
  'standardsUsed',
  'toolsUsed',
  'miauwWaivers',
  'miauwConfirmations',
};

/// Of deze melding in het venster Presentatiegegevens thuishoort in plaats van
/// in de kleurinstellingen. Publiek en puur, zodat de keuze los van de
/// dialogen te toetsen is — ook door het label van de actieknop.
bool issueBelongsToDeckInfo(SlideQualityIssue issue) =>
    issue.isDeckWide && kDeckInfoFields.contains(issue.field);

/// Navigate from a quality issue to the relevant editor field or theme colour.
void navigateToSlideQualityIssue({
  required BuildContext context,
  required WidgetRef ref,
  required SlideQualityIssue issue,
}) {
  if (issueBelongsToDeckInfo(issue)) {
    editPresentationInfo(context, ref);
    return;
  }
  if (issue.isDeckWide) {
    SettingsDialog.show(
      context,
      initialSection: SettingsSection.presentation,
      highlightThemeField: issue.field,
    );
    return;
  }
  // #1861: callout-meldingen openen de verwijzingeneditor in plaats van alleen
  // de dia te selecteren — de reparatie zit in die dialoog, niet op de regel.
  if (issue.category == SlideQualityCategory.callout) {
    final deck = ref.read(deckProvider).deck;
    if (deck != null &&
        issue.slideIndex >= 0 &&
        issue.slideIndex < deck.slides.length) {
      showDialog<void>(
        context: context,
        builder: (ctx) => CalloutEditorDialog(
          slide: deck.slides[issue.slideIndex],
          projectPath: deck.projectPath,
          onUpdate: (updated) =>
              ref.read(deckProvider.notifier).updateSlide(issue.slideIndex, updated),
        ),
      );
      return;
    }
  }
  ref
      .read(editorProvider.notifier)
      .selectWithQualityField(issue.slideIndex, issue.field, span: issue.span);
}
