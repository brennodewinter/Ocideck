import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/elearning_provider.dart';
import '../../../theme/app_theme.dart';

/// Module card for eLearning on Settings → Uitbreidingen (#1999).
///
/// Off by default. Switching it on reveals the eLearning slide types
/// (leerdoel, module, feedback, assessment-samenvatting) and
/// their picker tab; a deck that already carries such a slide reveals it
/// regardless (the shared module contract).
class ElearningModuleCard extends ConsumerWidget {
  const ElearningModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(elearningEnabledProvider);
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
                ref.read(elearningProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('eLearning'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Maak eLearning-inhoud: leerdoelen, modules, feedback en assessment-samenvattingen. Importeer SCORM, QTI, xAPI, AICC en OLX lokaal. Standaard uit; zet de uitbreiding aan om de dia-types te gebruiken.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.school_outlined),
          ),
        ],
      ),
    );
  }
}
