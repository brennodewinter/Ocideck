import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/slide_quality_localization.dart';
import '../../../state/settings_provider.dart';
import '../../../theme/app_theme.dart';

/// De uitgezette detectieregels, als chips die je weer aanzet.
///
/// Dit is de tegenkant van de "nooit meer melden"-knop in het kwaliteitspaneel:
/// wat je daar wegklikt, kun je hier terugzetten. Zonder die tegenkant is
/// uitzetten een eenrichtingsstraat, en dan durft niemand het te doen.
///
/// Standaard staan hier de drie zwaarste art. 9-categorieën in — politiek,
/// etniciteit en seksuele geaardheid. Niet omdat ze onbelangrijk zijn, maar
/// omdat hun trefwoorden op gewone zakelijke slides te vaak voorkomen. Wie in
/// die hoek werkt, zet ze hier met één tik aan.
class DisabledPrivacyRules extends ConsumerWidget {
  const DisabledPrivacyRules({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final disabled = ref.watch(
      settingsProvider.select((s) => s.privacyDisabledRules),
    );
    if (disabled.isEmpty) return const SizedBox.shrink();

    final sorted = disabled.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'Regels die nu uit staan. Deze worden niet gemeld en niet geredigeerd. Drie ervan staan standaard uit — hun trefwoorden komen op gewone zakelijke slides te vaak voor. Tik om er een aan te zetten.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final rule in sorted)
                InputChip(
                  label: Text(
                    privacyRuleLabel(l10n, rule),
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add, size: 14),
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .setPrivacyRuleEnabled(rule, true),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
