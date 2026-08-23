import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../theme/app_theme.dart';

/// Korte uitleg bij een charttype waarvan de datamapping niet vanzelfsprekend
/// is — of `null` voor de voor-de-hand-liggende (staaf, lijn, …).
String? chartTypeHint(AppLocalizations l10n, ChartType type) {
  if (type == ChartType.pie || type == ChartType.donut) {
    return l10n.d(
      'Bij een cirkel worden maximaal de eerste twee reeksen getoond; de labels vormen de segmenten.',
    );
  }
  return switch (type) {
    ChartType.radar => l10n.d(
      'Een spider-diagram heeft minstens drie labels (assen) nodig; elke reeks vormt een vlak.',
    ),
    ChartType.combo => l10n.d(
      'Laatste reeks als lijn op een tweede as; de rest als staven.',
    ),
    ChartType.waterfall => l10n.d(
      'Eerste reeks: elke waarde is een op- of neerwaartse stap op het vorige totaal.',
    ),
    ChartType.heatmap => l10n.d(
      'Reeks = rij, kolom = label, celkleur volgt de waarde. Label de assen kans en impact voor een risicomatrix.',
    ),
    ChartType.mainEffects || ChartType.interaction => l10n.d(
      'Eén reeks per factor met gecodeerde niveaus −1 en +1; laatste reeks is de respons (Y). Rijen zijn proefruns.',
    ),
    _ => null,
  };
}

/// Typekeuze plus acties (Gage R&R, DOE, plakken, CSV) buiten de editor-State.
///
/// De dropdown-items zijn puur presentatie; callbacks houden de State dun genoeg
/// voor het klasseplafond.
class ChartTypeToolbar extends StatelessWidget {
  final AppLocalizations l10n;
  final ChartType type;
  final bool revealProcesverbetering;
  final bool showVariants;
  final ValueChanged<ChartType> onTypeChanged;
  final VoidCallback onGageRr;
  final VoidCallback onDoeDesign;
  final VoidCallback? onCreateVariants;
  final VoidCallback onPasteClipboard;
  final VoidCallback onImportCsv;

  const ChartTypeToolbar({
    super.key,
    required this.l10n,
    required this.type,
    required this.revealProcesverbetering,
    required this.showVariants,
    required this.onTypeChanged,
    required this.onGageRr,
    required this.onDoeDesign,
    this.onCreateVariants,
    required this.onPasteClipboard,
    required this.onImportCsv,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          l10n.d('Type grafiek'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        DropdownButton<ChartType>(
          value: type,
          isDense: true,
          borderRadius: BorderRadius.circular(6),
          style: TextStyle(fontSize: 12, color: AppTheme.ink),
          items: [
            DropdownMenuItem(
              value: ChartType.bar,
              child: Text(l10n.d('Staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.horizontalBar,
              child: Text(l10n.d('Horizontale staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.stackedBar,
              child: Text(l10n.d('Gestapelde staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.horizontalStackedBar,
              child: Text(l10n.d('Horizontale gestapelde staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.combo,
              child: Text(l10n.d('Combo')),
            ),
            DropdownMenuItem(
              value: ChartType.line,
              child: Text(l10n.d('Lijn')),
            ),
            DropdownMenuItem(
              value: ChartType.area,
              child: Text(l10n.d('Vlak')),
            ),
            DropdownMenuItem(
              value: ChartType.pie,
              child: Text(l10n.d('Cirkel')),
            ),
            DropdownMenuItem(
              value: ChartType.donut,
              child: Text(l10n.d('Donut')),
            ),
            DropdownMenuItem(
              value: ChartType.radar,
              child: Text(l10n.d('Spider')),
            ),
            DropdownMenuItem(
              value: ChartType.scatter,
              child: Text(l10n.d('Spreiding')),
            ),
            DropdownMenuItem(
              value: ChartType.waterfall,
              child: Text(l10n.d('Waterval')),
            ),
            DropdownMenuItem(
              value: ChartType.heatmap,
              child: Text(l10n.d('Heatmap')),
            ),
            DropdownMenuItem(
              value: ChartType.bullet,
              child: Text(l10n.d('Norm en prestatie')),
            ),
            if (revealProcesverbetering) ...[
              DropdownMenuItem(
                value: ChartType.controlChart,
                child: Text(l10n.d('Regelkaart')),
              ),
              DropdownMenuItem(
                value: ChartType.histogram,
                child: Text(l10n.d('Histogram')),
              ),
              DropdownMenuItem(
                value: ChartType.pareto,
                child: Text(l10n.d('Pareto')),
              ),
              DropdownMenuItem(
                value: ChartType.runChart,
                child: Text(l10n.d('Run chart')),
              ),
              DropdownMenuItem(
                value: ChartType.boxPlot,
                child: Text(l10n.d('Boxplot')),
              ),
              DropdownMenuItem(
                value: ChartType.probabilityPlot,
                child: Text(l10n.d('Probability plot')),
              ),
              DropdownMenuItem(
                value: ChartType.mainEffects,
                child: Text(l10n.d('Hoofdeffecten')),
              ),
              DropdownMenuItem(
                value: ChartType.interaction,
                child: Text(l10n.d('Interactie')),
              ),
            ],
          ],
          onChanged: (v) {
            if (v != null) onTypeChanged(v);
          },
        ),
        if (revealProcesverbetering)
          TextButton.icon(
            key: const ValueKey('chart-gage-rr'),
            onPressed: onGageRr,
            icon: const Icon(Icons.straighten, size: 16),
            label: Text(l10n.d('Gage R&R…')),
          ),
        if (revealProcesverbetering)
          TextButton.icon(
            key: const ValueKey('chart-doe-design'),
            onPressed: onDoeDesign,
            icon: const Icon(Icons.grid_on, size: 16),
            label: Text(l10n.d('DOE-proefopzet…')),
          ),
        if (showVariants && onCreateVariants != null)
          TextButton.icon(
            key: const ValueKey('chart-create-variants'),
            onPressed: onCreateVariants,
            icon: const Icon(Icons.auto_awesome_motion, size: 16),
            label: Text(l10n.d('Varianten')),
          ),
        TextButton.icon(
          onPressed: onPasteClipboard,
          icon: const Icon(Icons.content_paste, size: 16),
          label: Text(l10n.d('Plakken uit klembord')),
        ),
        TextButton.icon(
          onPressed: onImportCsv,
          icon: const Icon(Icons.upload_file, size: 16),
          label: Text(l10n.d('CSV importeren')),
        ),
      ],
    );
  }
}
