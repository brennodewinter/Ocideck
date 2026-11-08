import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/settings_provider.dart';
import '../../../theme/app_theme.dart';

/// Uitzonderingen op de lokale privacycontrole, met hun gevolgen erbij.
class PrivacyOwnIdentityField extends ConsumerWidget {
  const PrivacyOwnIdentityField({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.d('Je eigen gegevens'), style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 2),
        Text(
          l10n.d(
            'Eén per regel: je naam, e-mailadres, telefoonnummer of het domein van je organisatie. Wat hier staat wordt niet gemeld en niet geredigeerd — het is de afzender, geen bevinding. Een domein (example.org) dekt elk adres eronder.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.d(
            'Een uitgezonderd domein verbergt ook gegevens van collega’s. Kies uitzonderingen zorgvuldig.',
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: ref.read(settingsProvider).privacyOwnIdentity,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: l10n.d('naam@example.org\nexample.org'),
            hintStyle: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setPrivacyOwnIdentity(value),
        ),
      ],
    );
  }
}
