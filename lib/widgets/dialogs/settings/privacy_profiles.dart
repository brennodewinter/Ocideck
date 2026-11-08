import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/privacy_disposition.dart';
import '../../../state/settings_provider.dart';
import '../../../utils/log.dart';

/// Profielen veranderen alleen de hoofdcontrole en het exportgedrag.
/// Eigen uitzonderingen, landen en beeldcontrole blijven bewuste losse keuzes.
class PrivacyProfiles extends ConsumerStatefulWidget {
  const PrivacyProfiles({super.key});
  @override
  ConsumerState<PrivacyProfiles> createState() => _PrivacyProfilesState();
}

class _PrivacyProfilesState extends ConsumerState<PrivacyProfiles> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final current = !settings.privacyChecksEnabled
        ? 'off'
        : settings.privacyStrictSeverity &&
              settings.privacyExportGate == PrivacyExportGate.block
        ? 'strict'
        : !settings.privacyStrictSeverity &&
              settings.privacyExportGate == PrivacyExportGate.warn
        ? 'warn'
        : 'custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'Kies het exportgedrag. Landen, beeldcontrole en uitzonderingen blijven behouden.',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.d('Waarschuwen vóór export')),
              selected: current == 'warn',
              onSelected: _busy ? null : (_) => _apply(false),
            ),
            ChoiceChip(
              label: Text(l10n.d('Export blokkeren')),
              selected: current == 'strict',
              onSelected: _busy ? null : (_) => _apply(true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(switch (current) {
            'off' =>
              'De privacycontrole staat uit; het exportbeleid beschermt dan niet.',
            'strict' =>
              'Zekere vondsten blokkeren export totdat u ze afhandelt.',
            'warn' =>
              'Bij onafgehandelde vondsten waarschuwen; bewust doorgaan blijft mogelijk.',
            _ =>
              'Aangepast: controleer hieronder de hoofdcontrole en het exportgedrag.',
          }),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Geen garantie: uitzonderingen en uitgeschakelde regels blijven gelden.',
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _apply(bool strict) async {
    setState(() => _busy = true);
    try {
      final settings = ref.read(settingsProvider.notifier);
      // De setters zetten de staat vóór hun eerste await. Start ze samen,
      // zodat de sleutelbos de exportkeuze niet halverwege laat wachten.
      unawaited(settings.setPrivacyChecksEnabled(true));
      await Future.wait([
        settings.setPrivacyStrictSeverity(strict),
        settings.setPrivacyExportGate(
          strict ? PrivacyExportGate.block : PrivacyExportGate.warn,
        ),
      ]);
      logInfo('DLP profile: ${strict ? 'strict' : 'warn'}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
