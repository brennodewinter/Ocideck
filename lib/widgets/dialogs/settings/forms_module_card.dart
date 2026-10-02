import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/forms_provider.dart';
import '../../../state/module_registry.dart';
import '../../../theme/app_theme.dart';
import 'card_titles.dart';
import 'module_card.dart';

/// De modulekaart voor Formulieren en inzendingen op Instellingen → Uitbreidingen
/// (FORM_INTAKE.md §7).
///
/// Standaard uit. Aanzetten maakt de organisatorkant zichtbaar: inzendingen van een
/// formulier binnenhalen en bijhouden. Een formulier invullen heeft de schakelaar
/// niet nodig.
class FormsModuleCard extends ConsumerWidget {
  const FormsModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(formsEnabledProvider);
    return ModuleCard(
      child: SwitchListTile(
        value: enabled,
        onChanged: (v) => ref.read(formsProvider.notifier).setEnabled(v),
        title: Text(
          moduleCardTitle(ModuleId.forms, l10n),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          l10n.d(
            'Haal inzendingen van een formulier binnen, houd ze tegen het gepubliceerde formulier en bewaar ze met een register. Een formulier invullen kan ook als dit uit staat. Standaard uit.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        secondary: const Icon(Icons.inbox_outlined),
      ),
    );
  }
}
