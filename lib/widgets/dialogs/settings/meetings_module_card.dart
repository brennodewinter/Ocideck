import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../meetings/meeting_registry.dart';
import '../../../state/meeting_session_provider.dart';
import '../../../state/meetings_module_provider.dart';
import '../../../theme/app_theme.dart';

/// De modulekaart voor Onlinevergaderingen op het tabblad Uitbreidingen
/// (TEAMS_GUEST_CLIENT.md T13).
///
/// Eén schakelaar voor bellen als geheel en niet één per aanbieder: de
/// gebruiker beslist of hij vergaderingen vanuit OciDeck doet, niet welke
/// adapter hij wil. Welke aanbieders er zijn staat in
/// `lib/meetings/meeting_registry.dart`.
///
/// De kaart belooft niets wat er niet is. Zolang er geen aanbieder op
/// `experimental` of hoger staat, zegt de voettekst dat meedoen nog niet kan —
/// in plaats van een schakelaar aan te bieden die aan gaat en verder niets
/// doet. Dat is dezelfde eerlijkheid die de Procesverbetering-kaart in fase 0
/// aanhoudt.
class MeetingsModuleCard extends ConsumerWidget {
  const MeetingsModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(meetingsModuleEnabledProvider);
    final sessionActive = ref.watch(meetingSessionActiveProvider);
    return Material(
      color: AppTheme.paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.iceBlue),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: (v) =>
                ref.read(meetingsModuleProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('Onlinevergaderingen'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Meedoen aan een vergadering van een andere aanbieder, met uw presentatie als wat u deelt. Standaard uit; met de module uit neemt OciDeck met geen enkele vergaderdienst contact op. Er is nog geen aanbieder aangesloten, dus meedoen kan nog niet — dit legt de basis.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.videocam_outlined),
          ),
          _footer(l10n, enabled: enabled, sessionActive: sessionActive),
        ],
      ),
    );
  }

  Widget _footer(
    AppLocalizations l10n, {
    required bool enabled,
    required bool sessionActive,
  }) {
    // Uit, maar er loopt een gesprek: de vaste regel van dit project in beeld.
    // Bij de andere modules gaat die regel over bewaard werk; hier is hij
    // letterlijker — een gesprek mag niet stilvallen omdat iemand een
    // schakelaar omzet, en `Verlaten` moet bereikbaar blijven.
    if (!enabled && sessionActive) {
      return _note(
        l10n.d(
          'Er loopt een vergadering. Het gespreksvenster blijft daarom bereikbaar tot u die verlaat.',
        ),
      );
    }
    if (!enabled) return const SizedBox.shrink();
    if (offerableMeetingProviders.isEmpty) {
      return _note(
        l10n.d(
          'Er is nog geen vergaderdienst beschikbaar om aan mee te doen. Zolang dat zo is verandert deze schakelaar niets en gaat er niets naar buiten.',
        ),
      );
    }
    return _note(
      l10n.d(
        'Plak een vergaderlink om mee te doen. Wie er contact krijgt en wat die te zien krijgt, staat op het scherm voordat u meedoet.',
      ),
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    child: Text(text, style: TextStyle(fontSize: 11, color: AppTheme.slate500)),
  );
}
