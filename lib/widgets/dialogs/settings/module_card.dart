// De gedeelde kaartvorm voor instellingen-modulekaarten.
//
// Tien modulekaarten in het instellingenvenster delen dezelfde Material-kaart:
// papierkleur, afgeronde hoeken, ijsblauwe rand. Deze widget centraliseert
// die vorm, zodat de kaarten zelf alleen hun schakelaar en inhoud hoeven te
// bouwen.
import 'package:material_ui/material_ui.dart';

import '../../../theme/app_theme.dart';

/// De kaartomslag voor een instellingen-modulekaart. Papierkleur, afgeronde
/// hoeken, ijsblauwe rand — het visuele kader dat alle modulekaarten delen.
class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.iceBlue),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}
