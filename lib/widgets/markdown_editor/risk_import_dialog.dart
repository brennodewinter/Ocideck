import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/risk_dossier.dart';
import '../../services/risk_dossier_scaffold.dart';

/// De uitkomst van de importdialoog: welke methode het register krijgt en
/// welke bronkolom (index) op welke contract-sleutel uitkomt — `null` = de
/// kolom reist ongemoeid mee als vrije `x-*`-kolom (§7).
typedef RiskImportChoice = ({RiskMethod method, Map<int, String?> mapping});

/// De menselijk leesbare naam voor een contract-sleutel in de dropdowns.
/// De sleutel zelf staat ernaast: "Faalwijze" kan `failure` zijn, maar ook
/// iets anders — de gebruiker beslist, OciDeck raadt niet (§7).
String _keyLabel(BuildContext context, String key) {
  final header = ociContractHeaderLabels[key];
  return header == null ? key : '$header ($key)';
}

/// Vraagt per kolom van [headers] welke contractbetekenis hij heeft, met de
/// methode erboven. Geen één-op-één-gok: elke kolom begint op "vrij meenemen"
/// en de gebruiker wijst expliciet toe — de enige eerlijke import uit #2492.
Future<RiskImportChoice?> showRiskImportDialog(
  BuildContext context,
  List<String> headers,
) {
  final l10n = context.l10n;
  var method = RiskMethod.fmea;
  final mapping = <int, String?>{};
  return showDialog<RiskImportChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setState) {
        final contract = ociRiskContractCols(method);
        final used = mapping.values.whereType<String>().toSet();
        return AlertDialog(
          title: Text(l10n.d('Tabel als risicoregister markeren')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.d(
                      'Wijs toe welke kolom welke betekenis heeft. Kolommen zonder betekenis blijven als vrije kolom bestaan — er gaat niets verloren. Rijen zonder ID krijgen een R-nummer.',
                    ),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  RadioGroup<RiskMethod>(
                    groupValue: method,
                    onChanged: (v) => setState(() {
                      method = v!;
                      // Contractwissel: eerdere toewijzingen kunnen sleutels
                      // bevatten die deze methode niet kent.
                      mapping.removeWhere(
                        (_, key) => key != null && !contract.contains(key),
                      );
                    }),
                    child: Row(
                      children: [
                        Expanded(
                          child: RadioListTile<RiskMethod>(
                            value: RiskMethod.fmea,
                            dense: true,
                            title: Text(l10n.d('FMEA')),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<RiskMethod>(
                            value: RiskMethod.likelihoodImpact,
                            dense: true,
                            title: Text(l10n.d('Kans × impact')),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var c = 0; c < headers.length; c++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Tooltip(
                              message: headers[c],
                              child: Text(
                                headers[c].isEmpty
                                    ? '${l10n.d('Kolom')} ${c + 1}'
                                    : headers[c],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: mapping[c],
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(l10n.d('Vrij meenemen')),
                                ),
                                for (final key in contract)
                                  if (!used.contains(key) || mapping[c] == key)
                                    DropdownMenuItem<String?>(
                                      value: key,
                                      child: Text(
                                        _keyLabel(ctx, key),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                              ],
                              onChanged: (v) => setState(() => mapping[c] = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.d('Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                method: method,
                mapping: mapping,
              )),
              child: Text(l10n.d('Markeren')),
            ),
          ],
        );
      },
    ),
  );
}
