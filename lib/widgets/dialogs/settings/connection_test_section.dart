// De gedeelde verbindingstest-sectie voor S3 en WebDAV.
//
// Beide panels hadden een identieke _testSection-methode van ~70 regels.
// Deze widget neemt de test-state en callbacks als parameters, zodat de
// panels alleen hun formaat-specifieke velden hoeven te bouwen.
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

/// De staat die een verbindingstest bijhoudt: bezig, geslaagd, en de boodschap.
/// S3Form en WebdavForm implementeren deze via testOk/testMessage/testing/
/// testCertRejected, maar hebben geen gedeeld type — daarom een kleine
/// abstracte interface in plaats van een gedeeld basistype.
abstract class ConnectionTestState {
  bool get testing;
  bool? get testOk;
  String? get testMessage;
  bool get testCertRejected;
}

/// De knop, de uitslag, en — als het op het certificaat strandde — de weg om
/// dat te bekijken. Gedeeld tussen S3Panel en WebdavPanel.
class ConnectionTestSection extends StatelessWidget {
  const ConnectionTestSection({
    super.key,
    required this.state,
    required this.onTest,
    required this.onTrustCertificate,
  });

  final ConnectionTestState state;
  final Future<void> Function() onTest;
  final Future<void> Function() onTrustCertificate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final testMsg = state.testMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: state.testing ? null : onTest,
              icon: state.testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(l10n.d('Verbinding testen')),
            ),
            const SizedBox(width: 12),
            if (state.testOk == true)
              Row(
                children: [
                  Icon(Icons.check_circle, color: AppTheme.tealFg, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    l10n.d('Verbinding gelukt'),
                    style: TextStyle(fontSize: 12, color: AppTheme.tealFg),
                  ),
                ],
              ),
          ],
        ),
        if (state.testCertRejected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onTrustCertificate,
                icon: const Icon(Icons.verified_user_outlined, size: 16),
                label: Text(l10n.d('Certificaat bekijken')),
              ),
            ),
          ),
        if (state.testOk == false && testMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppTheme.danger600,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    testMsg,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.danger600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
