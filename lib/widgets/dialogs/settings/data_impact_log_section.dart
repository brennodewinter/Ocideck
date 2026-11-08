import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/data_impact_log.dart';

/// Dit log is ook in een browser zonder bestandslog bereikbaar.
class DataImpactLogSection extends StatelessWidget {
  const DataImpactLogSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ExpansionTile(
      title: Text(l10n.d('Toestemmingslogboek')),
      children: [
        FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, snapshot) {
            final lines = snapshot.data?.getStringList(DataImpactLog.key) ?? [];
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.d(
                      'Laatste 200 gebeurtenissen: shown = getoond, accepted = geaccepteerd, declined = geweigerd.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(lines.reversed.join('\n')),
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: Text(l10n.d('Kopiëren')),
                    onPressed: lines.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: lines.join('\n')),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
