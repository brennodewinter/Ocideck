import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/integration_registry.dart';
import '../../../state/openkat_provider.dart';
import '../../../theme/app_theme.dart';
import 'openkat_integration_panel.dart';
import 'settings_section_title.dart';

/// Het tabblad Integraties: koppelingen met andere systemen, elk met een eigen
/// schakelaar, plus een bediening om ze allemaal tegelijk aan of uit te zetten
/// (#1158).
///
/// De secties komen letterlijk uit [availableIntegrationsProvider]: de volgorde
/// dáár is de volgorde hier, en een integratie die dit platform niet aankan valt
/// vanzelf weg. Een tweede integratie erbij zetten is één regel in
/// `integration_registry.dart` — dit paneel en de "alles aan/uit"-knoppen lopen
/// dan mee.
///
/// Een losse widget en geen `part` van het instellingenvenster (#631): die
/// klasse zit tegen haar plafond, en dit paneel leest alleen het
/// integratieregister.
class IntegrationsPanel extends ConsumerWidget {
  const IntegrationsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final integrations = ref.watch(availableIntegrationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.d('Integraties')),
        Text(
          l10n.d(
            'Koppelingen met andere systemen. Elke koppeling staat standaard uit en blijft inactief tot u haar inschakelt.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        const SizedBox(height: 16),
        const _BulkControls(),
        for (final entry in integrations) ...[
          const SizedBox(height: 12),
          _IntegrationCard(entry: entry),
        ],
      ],
    );
  }
}

/// De "alles aan/uit"-bediening. Twee knoppen en geen tweede grote schakelaar:
/// met één integratie zou een master-switch een verwarrende kopie van de
/// schakelaar eronder zijn, terwijl twee bulkknoppen leesbaar een handeling-op-
/// alles zijn. "Alles inschakelen" is uit zodra alles al aan staat, "Alles
/// uitschakelen" zodra alles al uit staat — zo zegt de knop zelf of er nog iets
/// te doen valt.
class _BulkControls extends ConsumerWidget {
  const _BulkControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final integrations = ref.watch(availableIntegrationsProvider);
    final allOn = ref.watch(allIntegrationsEnabledProvider);
    final anyOn = ref.watch(anyIntegrationEnabledProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.iceBlue),
      ),
      // Een [Wrap]: bij 200% interface-tekst passen het opschrift en de twee
      // knoppen niet meer op één regel, dan vallen ze netjes onder elkaar in
      // plaats van de rij te laten overlopen.
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.d('Alle integraties'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: allOn ? null : () => _setAll(ref, integrations, true),
            child: Text(l10n.d('Alles inschakelen')),
          ),
          TextButton(
            onPressed: anyOn ? () => _setAll(ref, integrations, false) : null,
            child: Text(l10n.d('Alles uitschakelen')),
          ),
        ],
      ),
    );
  }

  void _setAll(WidgetRef ref, List<IntegrationEntry> integrations, bool value) {
    for (final entry in integrations) {
      entry.setEnabled(ref, value);
    }
  }
}

/// Eén integratie als schakelkaart: de schakelaar met kop bovenaan, en de
/// instellingen eronder zodra de koppeling aan staat of er al inhoud is.
class _IntegrationCard extends ConsumerWidget {
  const _IntegrationCard({required this.entry});

  final IntegrationEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(entry.enabled);
    final revealed = ref.watch(entry.revealed);
    final web = isWebPlatform;
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
            value: !web && enabled,
            onChanged: web ? null : (v) => entry.setEnabled(ref, v),
            title: Text(
              _title(l10n),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _subtitle(l10n),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: _logo(),
          ),
          if (!web && revealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _body(),
            )
          else if (!web && _hasContent(ref))
            // Uit, maar er is al inhoud: de vaste regel van dit project in beeld.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                _contentNote(l10n),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasContent(WidgetRef ref) => switch (entry.id) {
    IntegrationId.openKat => ref.watch(openKatHasContentProvider),
  };

  String _title(AppLocalizations l10n) => switch (entry.id) {
    IntegrationId.openKat => l10n.d('OpenKAT'),
  };

  String _subtitle(AppLocalizations l10n) {
    if (isWebPlatform) {
      return l10n.d(
        'De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.',
      );
    }
    return switch (entry.id) {
      IntegrationId.openKat => l10n.d(
        'Lees OpenKAT-rapportages in als één managementoverzicht — vanuit een map of vanaf een server.',
      ),
    };
  }

  String _contentNote(AppLocalizations l10n) => switch (entry.id) {
    IntegrationId.openKat => l10n.d(
      'Er staat al een OpenKAT-bron ingesteld; de koppeling blijft daarom bereikbaar, zodat een bestaand OpenKAT-deck bij te werken blijft.',
    ),
  };

  Widget _logo() => switch (entry.id) {
    // Keiko, het logo van OpenKAT: in één oogopslag duidelijk over welk systeem
    // deze sectie gaat. `contain` en niet `cover`: dit is lijnwerk met witruimte
    // eromheen, en bijsnijden zou er oren af halen.
    IntegrationId.openKat => Image.asset(
      'assets/images/openkat-logo.png',
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  };

  Widget _body() => switch (entry.id) {
    IntegrationId.openKat => const OpenKatIntegrationBody(),
  };
}
