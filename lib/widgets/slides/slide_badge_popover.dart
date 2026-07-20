// Wat er achter een badge zit, en hoe je erop antwoordt.
//
// Een badge die alleen kleurt, vertelt dat er iets is en niet wát. Dat was de
// klacht: "er zouden zaken op slide 5 staan die gevoelig zijn, maar mij is niet
// duidelijk welke informatie dat betreft." De popover is het antwoord — één klik
// op de badge, en de meldingen van díe slide staan er, met de regel, het veld en
// een gemaskeerd fragment.
//
// En omdat je ze dan tóch leest, staat de beslissing er meteen bij.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../models/markdown_validation.dart';
import '../../models/privacy_disposition.dart';
import '../../models/privacy_finding.dart';
import '../../models/quality_disposition.dart';
import '../../models/slide.dart';
import '../../models/slide_quality.dart';
import '../../services/privacy/privacy_quality_bridge.dart';
import '../../state/deck_provider.dart';
import '../../state/deck_quality_provider.dart';
import '../../state/image_contrast_provider.dart';
import '../../state/image_privacy_provider.dart';
import '../../state/privacy_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import 'slide_badge_tone.dart';

/// Welke familie meldingen een badge vertegenwoordigt.
enum SlideBadgeFamily { quality, privacy }

/// Opent het lijstje meldingen bij een badge, verankerd aan de badge zelf.
///
/// Verankerd en niet centraal in beeld: je klikt op een klein plaatje in een
/// smalle kolom, en een schermvullende dialoog voor drie regels tekst haalt je
/// uit de lijst waar je juist doorheen aan het lopen bent.
Future<void> showSlideBadgeFindings({
  required BuildContext context,
  required WidgetRef ref,
  required int slideIndex,
  required SlideBadgeFamily family,
  required SlideBadgeTone tone,
}) async {
  final anchor = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (anchor == null || overlay == null) return;

  final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = anchor.localToGlobal(
    anchor.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final position = RelativeRect.fromLTRB(
    topLeft.dx,
    bottomRight.dy,
    overlay.size.width - bottomRight.dx,
    overlay.size.height - bottomRight.dy,
  );

  await showMenu<void>(
    context: context,
    position: position,
    constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
    items: [
      PopupMenuItem<void>(
        // Niet aanklikbaar als geheel: de knop erin doet het werk, en een
        // menu-item dat bij elke muisbeweging oplicht suggereert een actie die
        // er niet is.
        enabled: false,
        padding: EdgeInsets.zero,
        child: _BadgeFindings(
          slideIndex: slideIndex,
          family: family,
          tone: tone,
        ),
      ),
    ],
  );
}

/// De inhoud van de popover: de meldingen, en de knop die erop antwoordt.
class _BadgeFindings extends ConsumerWidget {
  final int slideIndex;
  final SlideBadgeFamily family;
  final SlideBadgeTone tone;

  const _BadgeFindings({
    required this.slideIndex,
    required this.family,
    required this.tone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final issues = slideBadgeIssues(ref, slideIndex, family);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            family == SlideBadgeFamily.privacy
                ? l10n.d('Persoonsgegevens gevonden')
                : l10n.d('Kwaliteitsproblemen'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _FindingLine(issue: issue),
            ),
          if (issues.isEmpty)
            Text(
              l10n.d('Geen meldingen meer op deze slide.'),
              style: TextStyle(fontSize: 10, color: AppTheme.slate500),
            ),
          const Divider(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                toggleSlideBadgeAcceptance(ref, slideIndex, family);
                Navigator.of(context).pop();
              },
              icon: Icon(
                tone == SlideBadgeTone.accepted
                    ? Icons.undo
                    : Icons.check_circle_outline,
                size: 14,
              ),
              label: Text(
                tone == SlideBadgeTone.accepted
                    ? l10n.d('Ongedaan maken')
                    : l10n.d('Accepteren'),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eén melding: waar ze zit, en wat er staat.
class _FindingLine extends StatelessWidget {
  final SlideQualityIssue issue;

  const _FindingLine({required this.issue});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = slideQualitySeverityColor(issue.severity);
    final field = slideQualityFieldLabel(l10n, issue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (field != null)
          Text(
            field,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        Text(
          formatSlideQualityIssue(l10n, issue),
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }
}

/// De meldingen van één slide voor één familie, uit de **ruwe** uitslag.
///
/// Ruw, want dit lijstje bestaat juist om een geaccepteerde bevinding te kunnen
/// lézen. Uit de gefilterde uitslag zou de popover van een grijze badge leeg
/// zijn — en dan is grijs weer net zo nietszeggend als verdwenen.
List<SlideQualityIssue> slideBadgeIssues(
  WidgetRef ref,
  int slideIndex,
  SlideBadgeFamily family,
) {
  if (family == SlideBadgeFamily.privacy) {
    // Ook de onzekere treffers: die krijgen een eigen badge, dus horen ze ook
    // in het lijstje eronder te staan.
    final text = privacyIssuesFrom(
      PrivacyScanResult(
        ref.read(privacyRawScanProvider).forSlide(slideIndex).toList(),
      ),
      // Ook hier, anders toont de popover een waarschuwing waar het paneel een
      // fout meldt — over dezelfde bevinding.
      strictSeverity: ref.read(settingsProvider).privacyStrictSeverity,
    );
    // En de beeldtreffers, uit dezelfde ruwe uitslag die de badge kleurt. De
    // badge combineert tekst én beeld; las de popover alleen de tekstscan, dan
    // was hij van een dia met alléén een gezichtstreffer leeg — "geen meldingen
    // meer op deze slide" — terwijl de badge er wél stond. Die tegenstrijdigheid
    // maakt de melding ongeloofwaardig, en was precies de klacht.
    final image =
        (ref.read(imagePrivacyRawIssuesProvider).value ??
                const <SlideQualityIssue>[])
            .where((i) => i.slideIndex == slideIndex)
            .toList();
    return [...text, ...image];
  }
  final sync = ref
      .read(deckQualityRawProvider)
      .forSlide(slideIndex)
      .where((i) => i.severity != MarkdownValidationSeverity.informational);
  // Ook de titel-over-beeld-contrastmeldingen, uit dezelfde asynchrone provider
  // die de badge kleurt. Zonder deze regel was de popover van een dia met alléén
  // een contrastprobleem leeg, terwijl het overzicht het wél toont en de badge
  // er wél staat — dezelfde tegenstrijdigheid als bij de gezichtstreffers.
  final contrast =
      (ref.read(imageContrastIssuesProvider).value ??
              const <SlideQualityIssue>[])
          .where(
            (i) =>
                i.slideIndex == slideIndex &&
                i.severity != MarkdownValidationSeverity.informational,
          );
  return [...sync, ...contrast];
}

/// Zet de acceptatie van deze slide aan of uit.
///
/// Bij privacy draait dit **alleen** `accept` terug. Staat de slide op `redact`
/// of `shield`, dan blijft hij staan: die standen doen iets met de gegevens zelf
/// of met de ontvanger, en dat met een dubbelklik ongedaan maken zou zwart
/// gelakte persoonsgegevens weer in de export zetten zonder dat iemand erom
/// vroeg. Die keuze hoort in het instellingenpaneel van de slide thuis, waar je
/// ziet wat je kiest.
void toggleSlideBadgeAcceptance(
  WidgetRef ref,
  int slideIndex,
  SlideBadgeFamily family,
) {
  final deck = ref.read(deckProvider).deck;
  if (deck == null || slideIndex < 0 || slideIndex >= deck.slides.length) {
    return;
  }
  final slide = deck.slides[slideIndex];
  final notifier = ref.read(deckProvider.notifier);

  if (family == SlideBadgeFamily.quality) {
    notifier.updateSlide(
      slideIndex,
      slide.copyWith(
        quality: slide.quality.isResolved
            ? QualityDisposition.warn
            : QualityDisposition.accept,
      ),
    );
    return;
  }

  final effective = effectivePrivacyDisposition(
    deck: deck.privacy,
    slide: slide.privacy,
  );
  if (effective == PrivacyDisposition.shield ||
      effective == PrivacyDisposition.redact) {
    return;
  }
  notifier.updateSlide(
    slideIndex,
    _withPrivacy(slide, deck.privacy, accept: !effective.isResolved),
  );
}

/// Zet de privacystand van een slide, met zo min mogelijk in het bestand.
///
/// Terug naar "waarschuwen" kan op twee manieren, en welke goed is hangt van het
/// deck af. Erft de slide van een deck dat zelf al accepteert, dan moet de slide
/// `warn` expliciet neerzetten — anders erft hij de acceptatie meteen terug en
/// lijkt de dubbelklik niets te doen. Staat het deck op de standaard, dan is de
/// directive gewoon overbodig en gaat hij eruit.
Slide _withPrivacy(
  Slide slide,
  PrivacyDisposition deckPrivacy, {
  required bool accept,
}) {
  if (accept) {
    return slide.copyWith(privacy: PrivacyDisposition.accept);
  }
  return deckPrivacy.isResolved
      ? slide.copyWith(privacy: PrivacyDisposition.warn)
      : slide.copyWith(clearPrivacy: true);
}
