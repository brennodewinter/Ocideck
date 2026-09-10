import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Compacte, rechtstreeks vindbare ingang naar het slide-overzicht.
class SlideOverviewButton extends StatelessWidget {
  const SlideOverviewButton(this.onPressed, {super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('slide-overview-button'),
    tooltip: context.l10n.d('Slide-overzicht'),
    onPressed: onPressed,
    icon: const Icon(Icons.grid_view_rounded, size: 17),
    color: AppTheme.slate300,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
  );
}
