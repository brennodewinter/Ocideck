import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/import_module_provider.dart';
import '../../../theme/app_theme.dart';

/// De modulekaart voor Importeren op het tabblad Uitbreidingen (#772, B1).
///
/// Sinds #1158 gaat deze module nog over één bron: presentaties uit PowerPoint
/// (.pptx), Keynote (.key) en Impress (.odp) als bewerkbaar deck binnenhalen.
/// OpenKAT is losgemaakt tot een eigen integratie met een eigen schakelaar op
/// het tabblad Integraties — zie `openkat_provider.dart`. De presentatie-import
/// werkt op bytes (geen `dart:io`) en dus op elk platform, ook web.
class ImportModuleCard extends ConsumerWidget {
  const ImportModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(importModuleEnabledProvider);
    return Material(
      color: AppTheme.paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.iceBlue),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SwitchListTile(
        value: enabled,
        onChanged: (v) => ref.read(importModuleProvider.notifier).setEnabled(v),
        title: Text(
          l10n.d('Importeren'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          l10n.d(
            'Presentaties uit PowerPoint (.pptx), Keynote (.key) en Impress (.odp) binnenhalen als bewerkbaar deck. Koppelingen met andere systemen, zoals OpenKAT, staan onder Integraties.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        secondary: const Icon(Icons.move_to_inbox_outlined),
      ),
    );
  }
}
