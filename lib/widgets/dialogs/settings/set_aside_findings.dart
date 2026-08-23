import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/slide_quality_localization.dart';
import '../../../services/privacy/dismissal_codec.dart';
import '../../../services/privacy/privacy_scanner.dart';
import '../../../state/deck_provider.dart';
import '../../../theme/app_theme.dart';

/// De terzijdegelegde privacybevindingen, als chips die je terugzet (#651).
///
/// De tegenkant van "Deze is beoordeeld en mag blijven" in het kwaliteitspaneel,
/// precies zoals de lijst met uitgezette regels de tegenkant is van "Deze regel
/// nooit meer melden". Het ontwerp (FILE_FORMAT §6.7) zegt het scherper dan ik
/// het kan: **een terzijdelegging die je niet terugvindt is een verwijdering.**
///
/// Een eigen widget en geen methode op het instellingenvenster: die klasse zat
/// tegen haar plafond, en dit hoort er ook niet in — het leest het deck, niet de
/// instellingen.
///
/// Wat er per chip staat is de regel plus wáár je oordeelde — nooit de gevonden
/// waarde. Die staat hier niet en kán hier niet staan: de sidecar bewaart een
/// commitment, geen tekst.
class SetAsidePrivacyFindings extends ConsumerWidget {
  const SetAsidePrivacyFindings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final setAside = ref.watch(deckProvider.select((s) => s.deck?.dismissals));
    if (setAside == null) return const SizedBox.shrink();
    final active = [
      for (final d in setAside.dismissals)
        if (stillHidden(setAside, d)) d,
    ];
    if (active.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Bevindingen die je hebt beoordeeld en hebt laten staan. Ze worden niet meer gemeld, maar de scan blijft ze vinden en ze tellen niet als opgelost. Tik om er een terug te zetten.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final d in active)
                InputChip(
                  label: Text(
                    setAsideChipLabel(l10n, d),
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.undo, size: 14),
                  // Terugzetten verwijdert de terzijdelegging niet maar zet er
                  // een grafsteen bij. Weggooien zou hem bij de eerstvolgende
                  // samenvoeging laten terugkeren van de andere kant, en dan was
                  // de bevinding weer verborgen zonder dat iemand daarvoor koos.
                  onPressed: () => ref
                      .read(deckProvider.notifier)
                      .setDismissals(
                        withDismissalRevoked(setAside, d, DateTime.now()),
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Of [d] nu werkelijk iets verbergt, of al is teruggezet.
///
/// De lijst toont alleen wat nog actief is. Een teruggezette terzijdelegging
/// blijft in de sidecar staan — de grafsteen is wat het samenvoegen laat
/// werken — maar hoort niet meer in een lijst met "wat ik heb laten staan".
bool stillHidden(DeckDismissals set, PrivacyDismissal d) {
  DateTime? laatste(List<PrivacyDismissal> lijst) {
    DateTime? uit;
    for (final x in lijst) {
      if (x.key == d.key && (uit == null || x.at.isAfter(uit))) uit = x.at;
    }
    return uit;
  }

  final gezet = laatste(set.dismissals);
  final terug = laatste(set.revocations);
  return gezet != null && (terug == null || gezet.isAfter(terug));
}

/// Wat er op de chip staat: de regel, en waar je oordeelde.
///
/// Nooit de gevonden waarde — die staat niet in de sidecar en hoort ook niet
/// in een instellingenscherm. "Slide 5 · opsomming" is genoeg om je te herinneren
/// welk oordeel je terugzet.
String setAsideChipLabel(AppLocalizations l10n, PrivacyDismissal d) {
  final regel = privacyRuleLabel(l10n, d.ruleId);
  final slide = d.seenAtSlide;
  if (slide == null) return regel;
  return '$regel · ${l10n.d('Slide')} ${slide + 1}';
}
