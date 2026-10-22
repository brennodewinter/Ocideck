import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/module_registry.dart';
import '../../../state/transcription_provider.dart';
import '../../../theme/app_theme.dart';
import 'card_titles.dart';
import 'module_card.dart';

/// De modulekaart voor Transcriptie en opname op Instellingen → Uitbreidingen
/// (docs/design/TRANSCRIPTION.md §1, #2510).
///
/// Standaard uit. De tekst is bewust eerlijk over de rijpheid: de sessiegrens
/// en de bewaarregels zijn er, de bronnen en engines zelf volgen per platform
/// in latere deeltickets — de schakelaar zet de grens klaar, geen
/// beloofde opnameknop.
class TranscriptionModuleCard extends ConsumerWidget {
  const TranscriptionModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(transcriptionModuleProvider);
    return ModuleCard(
      child: SwitchListTile(
        value: state.enabled,
        onChanged: state.loading
            ? null
            : ref.read(transcriptionModuleProvider.notifier).setEnabled,
        title: Text(
          moduleCardTitle(ModuleId.transcription, l10n),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          l10n.d(
            'Maak een transcript van een opname of van een bestaand audiobestand — als bewerkbaar Markdown-document, met een duidelijke keuze of het origineel bewaard blijft. Lokaal waar mogelijk; een eigen server alleen als u die kiest. De opnamebronnen en engines volgen in volgende versies.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        secondary: const Icon(Icons.transcribe_outlined),
      ),
    );
  }
}
