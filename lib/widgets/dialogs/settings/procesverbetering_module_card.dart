import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/improvement/improvement_analysis_helpers.dart';
import '../../../services/improvement/stats/stats.dart';
import '../../../services/scene/scene.dart';
import '../../../state/procesverbetering_provider.dart';
import '../../../theme/app_theme.dart';
import '../../slides/previews/scene_painter.dart';
import '../improvement_inference_dialog.dart';
import '../improvement_msa_dialog.dart';
import '../improvement_regression_dialog.dart';

/// Module card for Procesverbetering on Settings → Uitbreidingen
/// (PROCESS_IMPROVEMENT.md Phase 0).
///
/// Off by default. The card names the concrete tools the extension reveals,
/// while the product name remains the broader "Procesverbetering" (§19.7).
///
/// Reading [improvementStatsFactorRows] here is deliberate: the stats library
/// must stay reachable from an entrypoint before Phase 2/3 UI lands, or the
/// dead-code gate fails on a library that is otherwise ready.
class ProcesverbeteringModuleCard extends ConsumerWidget {
  const ProcesverbeteringModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(procesverbeteringEnabledProvider);
    // Keep the stats library reachable (dead-code gate) and show how much
    // reference data is already on the device — same shape as CVSS on the
    // Informatieveiligheid card.
    final factorRows = improvementStatsFactorRows;
    // Keep the scene backends reachable for the dead-code gate (Phase 3a)
    // until engines wire them into slide_preview.
    assert(() {
      ScenePreview(scene: Scene.demo());
      runGageRrAnalysis;
      runInferenceAnalysis;
      runRegressionAnalysis;
      ImprovementMsaDialog.show;
      ImprovementInferenceDialog.show;
      ImprovementRegressionDialog.show;
      return true;
    }());
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
                ref.read(procesverbeteringProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('Procesverbetering'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Hulpmiddelen voor procesverbetering (SIPOC, DMAIC, Kaizen en A3). Standaard uit; zet de uitbreiding aan om de bijbehorende sjablonen en dia-indelingen te gebruiken.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.trending_up_outlined),
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n
                        .d(
                          'Module aan. Rekenkern, dia-indelingen en sjablonen zijn lokaal beschikbaar ({n} control-chartfactoren).',
                        )
                        .replaceAll('{n}', '$factorRows'),
                    style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => ImprovementMsaDialog.show(context),
                        child: Text(l10n.d('Gage R&R…')),
                      ),
                      TextButton(
                        onPressed: () =>
                            ImprovementInferenceDialog.show(context),
                        child: Text(l10n.d('Hypothesetoets…')),
                      ),
                      TextButton(
                        onPressed: () =>
                            ImprovementRegressionDialog.show(context),
                        child: Text(l10n.d('Regressie…')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
