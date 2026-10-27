import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/module_registry.dart';
import '../../../state/transcription_provider.dart';
import '../../../theme/app_theme.dart';
import 'card_titles.dart';
import 'module_card.dart';
import 'transcription_models_section.dart';
import 'transcription_server_section.dart';
import 'transcription_status_section.dart';

/// De modulekaart voor Transcriptie en opname op Instellingen → Uitbreidingen
/// (docs/design/TRANSCRIPTION.md §1, #2510; instellingsoppervlak #2514).
///
/// Standaard uit, en de inhoud blijft óók uitgeschakeld zichtbaar: de
/// statusmatrix, modelbeheer (opruimen mag altijd) en het serverprofiel
/// zijn juist dan de plek om te zien wát aan- of wegklikken betekent.
/// De schakelaar zet alleen de werkzame kant aan — detectie hieronder
/// opent geen apparaat en raakt geen netwerk. De modelscan (#2601) leest
/// een vaste lijst gangbare plekken op schijf; op macOS kan dat de eerste
/// keer de maptoegang-vraag van het systeem geven — een afwijzing laat
/// de scan gewoon leeg.
class TranscriptionModuleCard extends ConsumerWidget {
  const TranscriptionModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(transcriptionModuleProvider);
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
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
                'Maak een transcript van een opname of van een bestaand audiobestand — als bewerkbaar Markdown-document, met een duidelijke keuze of het origineel bewaard blijft. Lokaal waar mogelijk; een eigen server alleen als u die kiest.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.transcribe_outlined),
          ),
          if (!state.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.d(
                  'Module staat uit — geen downloads, geen microfoon, geen achtergrondtaken. De instellingen hieronder blijven vindbaar voor overzicht en opruimen.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate600),
              ),
            ),
          _RouteChoice(),
          const TranscriptionStatusSection(),
          TranscriptionModelsSection(moduleEnabled: state.enabled),
          const TranscriptionServerSection(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// De verwerkingsroute: lokaal (standaard) of het eigen serverprofiel.
/// De keuze bepaalt welke engine `transcriptionEngineProvider` bouwt —
/// hij valt nooit stil de andere kant op (§4.3).
class _RouteChoice extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final route = ref.watch(transcriptionRouteProvider);
    return RadioGroup<String>(
      groupValue: route,
      onChanged: (v) {
        if (v != null) {
          ref.read(transcriptionRouteProvider.notifier).set(v);
        }
      },
      child: Column(
        children: [
          RadioListTile<String>(
            dense: true,
            value: 'local',
            title: Text(
              l10n.d('Lokaal — op dit apparaat'),
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              l10n.d('Standaard: er vertrekt geen audio'),
              style: TextStyle(fontSize: 11, color: AppTheme.slate600),
            ),
          ),
          RadioListTile<String>(
            dense: true,
            value: 'server',
            title: Text(
              l10n.d('Eigen ASR-server'),
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              l10n.d(
                'Alleen het bewaarde, actieve profiel hieronder — per taak vraagt hij opnieuw toestemming',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate600),
            ),
          ),
        ],
      ),
    );
  }
}
